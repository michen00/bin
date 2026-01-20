#!/usr/bin/env bash

set -euo pipefail

# Trap SIGPIPE to handle broken pipes gracefully (common when output is piped)
# This prevents "Broken pipe" errors from causing script failure.
# Note: This trap prevents the script from exiting on SIGPIPE, but error messages
# may still be printed. We handle those at the command level with || true.
trap '' PIPE

SCRIPT_NAME=$(basename "$0")

# Exempted scripts (from command-line arguments)
declare -a exempted_scripts

usage() {
  cat << EOF
Usage: $SCRIPT_NAME [EXEMPTED_SCRIPT...]

Validates that all scripts in the project root have corresponding test files
and README.md entries, and that README entries are properly formatted and sorted.

Arguments:
  EXEMPTED_SCRIPT    Names of scripts to exempt from validation (optional, multiple)

Options:
  -h, --help         Show this help message and exit.

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME internal-helper
  $SCRIPT_NAME old-tool deprecated-script
EOF
  exit "${1:-0}"
}

# Check if a script is in the exemption list
is_exempted() {
  local script=$1
  for exempt in "${exempted_scripts[@]}"; do
    if [[ "$script" == "$exempt" ]]; then
      return 0
    fi
  done
  return 1
}

# Discover all scripts in project root (no extension, not hidden, not symlink, has shebang AND executable permissions)
discover_scripts() {
  local script
  while IFS= read -r -d '' script; do
    # Remove leading ./
    script="${script#./}"

    # Skip if script itself is a symlink (should be ignored)
    if [ -L "$script" ]; then
      continue
    fi

    # Check if script is a symlink target (should be ignored)
    local is_target=false
    for link in ./*; do
      if [ -L "$link" ]; then
        local target
        target=$(readlink "$link" 2> /dev/null || echo "")
        # Normalize paths for comparison (remove leading ./ if present)
        target="${target#./}"
        if [ "$target" = "$script" ]; then
          is_target=true
          break
        fi
      fi
    done
    if [ "$is_target" = true ]; then
      continue # Skip symlink targets
    fi

    # Check if file has shebang (starts with #!) AND executable permissions
    if head -n 1 "$script" 2> /dev/null | grep -q '^#!' && [ -x "$script" ]; then
      # Skip if exempted
      if ! is_exempted "$script"; then
        echo "$script" 2> /dev/null || true # Suppress broken pipe errors (expected when consumer exits early)
      fi
    fi
  done < <(find . -maxdepth 1 -type f ! -name '.*' ! -name '*.*' -print0)
}

# Discover all test files matching tests/*.bats (must have shebang AND executable permissions)
discover_tests() {
  if [[ ! -d "tests" ]]; then
    return 0
  fi

  local test_file
  while IFS= read -r -d '' test_file; do
    # Check if test file has shebang AND executable permissions
    if head -n 1 "$test_file" 2> /dev/null | grep -q '^#!' && [ -x "$test_file" ]; then
      # Extract script name (remove tests/ prefix and .bats suffix)
      local script_name="${test_file#tests/}"
      script_name="${script_name%.bats}"
      echo "$script_name" 2> /dev/null || true # Suppress broken pipe errors (expected when consumer exits early)
    fi
  done < <(find tests -maxdepth 1 -name '*.bats' -type f -print0 2> /dev/null || true)
}

# Discover README entries from ## Scripts section
discover_readme_entries() {
  if [[ ! -f "README.md" ]]; then
    echo "ERROR: README.md not found" >&2
    return 1
  fi

  # Check if Scripts section exists
  if ! grep -q '^## Scripts$' README.md; then
    echo "ERROR: README.md is missing '## Scripts' section" >&2
    return 1
  fi

  # Extract Scripts section (from ## Scripts to next ## or EOF)
  # Awk pattern explanation:
  #   /^## Scripts$/{flag=1; next}  - When we find "## Scripts" heading, set flag and skip to next line
  #   /^## /{flag=0}                 - When we find any other ## heading, clear flag (stop capturing)
  #   flag                           - Print line only if flag is set (we're in Scripts section)
  # This ensures we capture only the Scripts section, stopping before the next section
  local scripts_section
  scripts_section=$(awk '/^## Scripts$/{flag=1; next} /^## /{flag=0} flag' README.md)

  # Filter out HTML comments (single-line)
  # Remove lines that are purely HTML comments: <!-- ... -->
  # This preserves entry lines. Multi-line comments (<!-- ... --> spanning multiple lines)
  # are handled by removing the opening and closing lines separately.
  local filtered
  # Remove single-line HTML comments and comment boundary lines
  filtered=$(echo "$scripts_section" | sed '/^[[:space:]]*<!--.*-->[[:space:]]*$/d' | sed '/^[[:space:]]*<!--[[:space:]]*$/d' | sed '/^[[:space:]]*-->[[:space:]]*$/d')

  # Extract script names from entries matching pattern: - [`scriptname`](scriptname): ...
  # shellcheck disable=SC2016  # Single quotes intentional - backticks are literal regex chars, not command substitution
  echo "$filtered" | grep -E '^- \[`[^`]+`\]\([^)]+\):' | sed -E 's/^- \[`([^`]+)`\].*/\1/' 2> /dev/null || true # Suppress broken pipe errors
}

# Validate correspondence between scripts, tests, and README entries
validate_correspondence() {

  # Build associative arrays for O(1) lookup performance
  # Associative arrays (bash 4.0+) provide fast key-based lookups for correspondence checks
  declare -A script_map # Maps script names to 1 (exists)
  declare -A test_map   # Maps test script names to 1 (test file exists)
  declare -A readme_map # Maps README script names to 1 (documented)

  # Populate script map
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r script; do
    [[ -n "$script" ]] && script_map["$script"]=1
  done < <(discover_scripts)
  set -e # Re-enable -e

  # Populate test map
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r test_script; do
    [[ -n "$test_script" ]] && test_map["$test_script"]=1
  done < <(discover_tests)
  set -e # Re-enable -e

  # Populate README map
  # Note: We temporarily disable "set -e" because command substitution with set -e
  # would cause the script to exit immediately if discover_readme_entries returns non-zero.
  # We need to capture the exit code explicitly to handle errors gracefully.
  local readme_output
  set +e # Temporarily disable exit-on-error to capture exit code
  readme_output=$(discover_readme_entries)
  local readme_exit=$?
  set -e # Re-enable exit-on-error
  if [[ $readme_exit -ne 0 ]]; then
    # Re-run to get error message if function failed
    discover_readme_entries >&2
    exit 1
  fi
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r readme_script; do
    # Skip error messages (lines starting with ERROR)
    [[ "$readme_script" =~ ^ERROR: ]] && continue
    [[ -n "$readme_script" ]] && readme_map["$readme_script"]=1
  done <<< "$readme_output"
  set -e # Re-enable -e

  # Check each script for missing test file (fail-fast: exit on first error)
  for script in "${!script_map[@]}"; do
    if [[ ! ${test_map[$script]+_} ]]; then
      echo "❌ Validation Failed" >&2
      echo "" >&2
      echo "Missing Test Files:" >&2
      echo "  - Script '$script' has no test file tests/$script.bats" >&2
      exit 1
    fi
  done

  # Check each script for missing README entry (scripts → README) (fail-fast: exit on first error)
  for script in "${!script_map[@]}"; do
    if [[ ! ${readme_map[$script]+_} ]]; then
      echo "❌ Validation Failed" >&2
      echo "" >&2
      echo "Missing README Entries:" >&2
      echo "  - Script '$script' has no README entry" >&2
      exit 1
    fi
  done

  # Check each README entry for missing script (README → scripts) (fail-fast: exit on first error)
  for readme_script in "${!readme_map[@]}"; do
    if [[ ! ${script_map[$readme_script]+_} ]]; then
      echo "❌ Validation Failed" >&2
      echo "" >&2
      echo "Orphaned README Entries:" >&2
      echo "  - README entry for '$readme_script' references a non-existent script" >&2
      exit 1
    fi
  done

  return 0
}

# Validate that scripts referenced in README and test files have both shebang and executable permissions
validate_executable_permissions() {
  # Local arrays to collect error messages (used for fail-fast error reporting)
  local -a invalid_scripts
  local -a invalid_tests

  local invalid_scripts_count=0
  local invalid_tests_count=0

  # Validate scripts referenced in README entries have both shebang and executable permissions
  local readme_output
  set +e
  readme_output=$(discover_readme_entries)
  local readme_exit=$?
  set -e
  if [[ $readme_exit -eq 0 ]]; then
    set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
    while IFS= read -r readme_script; do
      [[ "$readme_script" =~ ^ERROR: ]] && continue
      [[ -z "$readme_script" ]] && continue

      # Skip if exempted
      if is_exempted "$readme_script"; then
        continue
      fi

      # Check if script exists
      if [[ ! -f "$readme_script" ]]; then
        continue # Already handled by validate_correspondence() orphaned README check
      fi

      local has_shebang=0
      local has_executable=0

      # Check shebang
      if head -n 1 "$readme_script" 2> /dev/null | grep -q '^#!'; then
        has_shebang=1
      fi

      # Check executable permissions
      if [ -x "$readme_script" ]; then
        has_executable=1
      fi

      # Report if missing either requirement
      if [[ $has_shebang -eq 0 ]] && [[ $has_executable -eq 0 ]]; then
        invalid_scripts+=("README-referenced script '$readme_script' lacks both shebang and executable permissions")
        ((invalid_scripts_count++))
      elif [[ $has_shebang -eq 0 ]]; then
        invalid_scripts+=("README-referenced script '$readme_script' lacks shebang (must start with #!)")
        ((invalid_scripts_count++))
      elif [[ $has_executable -eq 0 ]]; then
        invalid_scripts+=("README-referenced script '$readme_script' lacks executable permissions (must have chmod +x)")
        ((invalid_scripts_count++))
      fi
    done <<< "$readme_output"
    set -e # Re-enable -e
  fi

  # Validate all discovered test files have both shebang and executable permissions
  # Note: discover_tests() already filters, but we validate explicitly for clearer error messages
  if [[ -d "tests" ]]; then
    set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
    while IFS= read -r -d '' test_file; do
      local has_shebang=0
      local has_executable=0

      # Check shebang
      if head -n 1 "$test_file" 2> /dev/null | grep -q '^#!'; then
        has_shebang=1
      fi

      # Check executable permissions
      if [ -x "$test_file" ]; then
        has_executable=1
      fi

      # Report if missing either requirement
      if [[ $has_shebang -eq 0 ]] && [[ $has_executable -eq 0 ]]; then
        local test_name="${test_file#tests/}"
        test_name="${test_name%.bats}"
        invalid_tests+=("Test file '$test_file' lacks both shebang and executable permissions")
        ((invalid_tests_count++))
      elif [[ $has_shebang -eq 0 ]]; then
        invalid_tests+=("Test file '$test_file' lacks shebang (must start with #!)")
        ((invalid_tests_count++))
      elif [[ $has_executable -eq 0 ]]; then
        invalid_tests+=("Test file '$test_file' lacks executable permissions (must have chmod +x)")
        ((invalid_tests_count++))
      fi
    done < <(find tests -maxdepth 1 -name '*.bats' -type f -print0 2> /dev/null || true)
    set -e # Re-enable -e
  fi

  # Fail-fast: exit immediately on first error
  if [[ $invalid_scripts_count -gt 0 ]]; then
    echo "❌ Validation Failed" >&2
    echo "" >&2
    echo "Invalid Scripts:" >&2
    echo "  - ${invalid_scripts[0]}" >&2
    exit 1
  fi
  if [[ $invalid_tests_count -gt 0 ]]; then
    echo "❌ Validation Failed" >&2
    echo "" >&2
    echo "Invalid Test Files:" >&2
    echo "  - ${invalid_tests[0]}" >&2
    exit 1
  fi
  return 0
}

# Validate README entry formatting
validate_formatting() {

  if [[ ! -f "README.md" ]]; then
    return 0
  fi

  # Extract Scripts section
  local scripts_section
  scripts_section=$(awk '/^## Scripts$/{flag=1; next} /^## /{flag=0} flag' README.md)

  # Filter out HTML comments (single-line)
  # Remove lines that are purely HTML comments: <!-- ... -->
  # This preserves entry lines. Multi-line comments (<!-- ... --> spanning multiple lines)
  # are handled by removing the opening and closing lines separately.
  local filtered
  # Remove single-line HTML comments and comment boundary lines
  filtered=$(echo "$scripts_section" | sed '/^[[:space:]]*<!--.*-->[[:space:]]*$/d' | sed '/^[[:space:]]*<!--[[:space:]]*$/d' | sed '/^[[:space:]]*-->[[:space:]]*$/d')

  # Process each README entry line
  # Get line numbers from original README for accurate reporting
  local scripts_section_start_line
  scripts_section_start_line=$(grep -n '^## Scripts$' README.md | cut -d: -f1)

  # Process filtered section but track original line numbers for error reporting
  # Line number tracking is approximate (doesn't account for filtered HTML comments)
  # but provides useful context for developers fixing formatting errors
  local line_number_in_section=0
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r line; do
    ((line_number_in_section++))
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Check if this is a README entry line (starts with "-")
    if [[ "$line" =~ ^-.* ]]; then
      # Calculate approximate line number in README for error messages
      # Note: This is approximate because HTML comments are filtered but line numbers aren't adjusted
      local current_line=$((scripts_section_start_line + line_number_in_section))
      local script_name
      local link_text
      local link_url
      local description

      # Extract script name and link URL from markdown link: [`scriptname`](scriptname)
      # Pattern: [`scriptname`](scriptname) - extract both the link text and URL
      # shellcheck disable=SC2016  # Single quotes intentional - backticks are literal regex chars, not command substitution
      if ! echo "$line" | grep -qE '\[`[^`]+`\]\([^)]+\)'; then
        echo "❌ Validation Failed" >&2
        echo "" >&2
        echo "Formatting Errors:" >&2
        echo "  - README entry missing backticks or link URL (line $current_line): $line" >&2
        exit 1
      fi
      # Extract link text from backticks: [`scriptname`]
      # shellcheck disable=SC2016  # Single quotes intentional - backticks are literal regex chars, not command substitution
      link_text=$(echo "$line" | sed -nE 's/.*\[`([^`]+)`\].*/\1/p')
      # Extract link URL immediately after the backticked link text: (scriptname)
      # This ensures we get the URL from the markdown link, not from parentheses in the description
      # shellcheck disable=SC2016  # Single quotes intentional - backticks are literal regex chars, not command substitution
      link_url=$(echo "$line" | sed -nE 's/.*\[`[^`]+`\]\(([^)]+)\).*/\1/p')
      if [[ -z "$link_url" ]]; then
        echo "❌ Validation Failed" >&2
        echo "" >&2
        echo "Formatting Errors:" >&2
        echo "  - README entry missing link URL (line $current_line): $line" >&2
        exit 1
      fi

      # Check if link text matches URL
      if [[ "$link_text" != "$link_url" ]]; then
        echo "❌ Validation Failed" >&2
        echo "" >&2
        echo "Formatting Errors:" >&2
        echo "  - README entry link text '$link_text' doesn't match URL '$link_url' (line $current_line)" >&2
        exit 1
      fi

      # Extract description (after colon)
      description=$(echo "$line" | sed -nE 's/.*:[[:space:]]*(.+)/\1/p')
      if [[ -z "$description" ]]; then
        echo "❌ Validation Failed" >&2
        echo "" >&2
        echo "Formatting Errors:" >&2
        echo "  - README entry missing description (line $current_line): $line" >&2
        exit 1
      fi

      # Check if description starts with capital letter
      if [[ ! "$description" =~ ^[A-Z] ]]; then
        echo "❌ Validation Failed" >&2
        echo "" >&2
        echo "Formatting Errors:" >&2
        echo "  - README entry for '$link_text' must start with capital letter (line $current_line)" >&2
        exit 1
      fi

      # Check if description ends with period
      if [[ ! "$description" =~ \.$ ]]; then
        echo "❌ Validation Failed" >&2
        echo "" >&2
        echo "Formatting Errors:" >&2
        echo "  - README entry for '$link_text' must end with period (line $current_line)" >&2
        exit 1
      fi
    fi
  done <<< "$filtered"
  set -e # Re-enable -e

  return 0
}

# Validate alphabetical sorting of README entries
validate_sorting() {

  if [[ ! -f "README.md" ]]; then
    return 0
  fi

  # Extract Scripts section
  local scripts_section
  scripts_section=$(awk '/^## Scripts$/{flag=1; next} /^## /{flag=0} flag' README.md)

  # Filter out HTML comments (single-line)
  # Remove lines that are purely HTML comments: <!-- ... -->
  # This preserves entry lines. Multi-line comments (<!-- ... --> spanning multiple lines)
  # are handled by removing the opening and closing lines separately.
  local filtered
  # Remove single-line HTML comments and comment boundary lines
  filtered=$(echo "$scripts_section" | sed '/^[[:space:]]*<!--.*-->[[:space:]]*$/d' | sed '/^[[:space:]]*<!--[[:space:]]*$/d' | sed '/^[[:space:]]*-->[[:space:]]*$/d')

  # Extract script names in order from README entries
  local names_in_order=()
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r line; do
    if [[ "$line" =~ ^-.* ]]; then
      local script_name
      # shellcheck disable=SC2016  # Single quotes intentional - backticks are literal regex chars, not command substitution
      script_name=$(echo "$line" | sed -nE 's/.*\[`([^`]+)`\].*/\1/p')
      if [[ -n "$script_name" ]]; then
        names_in_order+=("$script_name")
      fi
    fi
  done <<< "$filtered"
  set -e # Re-enable -e

  # Create sorted version (case-sensitive alphabetical order)
  local names_sorted=()
  if [[ ${#names_in_order[@]} -gt 0 ]]; then
    # Use printf and sort to create sorted array (case-sensitive)
    mapfile -t names_sorted < <(printf '%s\n' "${names_in_order[@]}" | sort)
  fi

  # Compare order (fail-fast: exit on first error)
  if [[ "${names_in_order[*]}" != "${names_sorted[*]}" ]]; then
    # Find first out-of-order entry for better error message
    local i
    for ((i = 0; i < ${#names_in_order[@]}; i++)); do
      if [[ "${names_in_order[$i]}" != "${names_sorted[$i]}" ]]; then
        echo "❌ Validation Failed" >&2
        echo "" >&2
        echo "Sorting Errors:" >&2
        echo "  - README entries must be sorted alphabetically" >&2
        echo "  - Found '${names_in_order[$i]}' but expected '${names_sorted[$i]}'" >&2
        exit 1
      fi
    done
  fi

  return 0
}

# Validate count consistency
validate_counts() {

  # Count scripts (non-exempted)
  local script_count=0
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r script; do
    [[ -n "$script" ]] && ((script_count++))
  done < <(discover_scripts)
  set -e # Re-enable -e

  # Count README entries
  local readme_count=0
  local readme_output
  # Temporarily disable -e to capture exit code
  set +e
  readme_output=$(discover_readme_entries)
  local readme_exit=$?
  set -e
  if [[ $readme_exit -ne 0 ]]; then
    # Re-run to get error message if function failed
    discover_readme_entries >&2
    exit 1
  fi
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r readme_script; do
    # Skip error messages (lines starting with ERROR)
    [[ "$readme_script" =~ ^ERROR: ]] && continue
    [[ -n "$readme_script" ]] && ((readme_count++))
  done <<< "$readme_output"
  set -e # Re-enable -e

  # Count test files (for informational purposes, but not required to match)
  local test_count=0
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r test_script; do
    [[ -n "$test_script" ]] && ((test_count++))
  done < <(discover_tests)
  set -e # Re-enable -e

  # Check if script count matches README entry count (fail-fast: exit on first error)
  if [[ $script_count -ne $readme_count ]]; then
    echo "❌ Validation Failed" >&2
    echo "" >&2
    echo "Count Mismatch:" >&2
    echo "  - Count mismatch: $script_count scripts, $readme_count README entries, $test_count test files" >&2
    exit 1
  fi

  return 0
}

# Note: report_errors() removed - fail-fast behavior means each validation function
# reports and exits immediately on first error, so no aggregation needed

main() {
  # Parse arguments
  exempted_scripts=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage 0
        ;;
      *)
        exempted_scripts+=("$1")
        ;;
    esac
    shift
  done

  # Cache counts for success message (calculate before validation)
  # We count before validation so we can display counts even if validation fails
  # This provides useful context in the success message
  local script_count=0
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r script; do
    [[ -n "$script" ]] && ((script_count++))
  done < <(discover_scripts)
  set -e # Re-enable -e

  local test_count=0
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r test_script; do
    [[ -n "$test_script" ]] && ((test_count++))
  done < <(discover_tests)
  set -e # Re-enable -e

  local readme_count=0
  local readme_output
  # Temporarily disable -e to capture exit code
  set +e
  readme_output=$(discover_readme_entries)
  local readme_exit=$?
  set -e
  if [[ $readme_exit -ne 0 ]]; then
    # Re-run to get error message if function failed
    discover_readme_entries >&2
    exit 1
  fi
  set +e # Temporarily disable -e for while loop (read returns non-zero on EOF)
  while IFS= read -r readme_script; do
    # Skip error messages (lines starting with ERROR)
    [[ "$readme_script" =~ ^ERROR: ]] && continue
    [[ -n "$readme_script" ]] && ((readme_count++))
  done <<< "$readme_output"
  set -e # Re-enable -e

  # Run validation in order of cost (cheapest first for early failure)
  # Fail-fast: each validation function exits immediately on first error
  # Order optimized for performance: fastest checks run first to fail early
  #
  # 0. Executable permissions check - O(n) file attribute checks (very fast)
  validate_executable_permissions

  # 1. Formatting check - O(n) regex parsing per entry (catches malformed entries)
  #    Validates: backticks, capitalization, periods, link format
  #    Must run before correspondence to catch malformed entries that won'''t be discovered
  validate_formatting

  # 2. Correspondence checks - O(n) associative array lookups (P1 priority)
  #    Checks: scripts→tests, scripts→README, README→scripts
  #    Runs before count check to provide specific error messages instead of generic "Count Mismatch"
  validate_correspondence

  # 3. Count check - O(n) counting operations (catches obvious mismatches)
  #    Validates: script count == README entry count
  #    Runs after correspondence so specific errors are reported first
  validate_counts

  # 4. Sorting check - O(n log n) sorting operation (most expensive)
  #    Validates alphabetical order (case-sensitive)
  validate_sorting

  local exempted_count=${#exempted_scripts[@]}

  echo "✓ Validation passed: All scripts are properly documented and tested"
  echo "  - Scripts: $script_count"
  echo "  - Test files: $test_count"
  echo "  - README entries: $readme_count"
  echo "  - Exempted: $exempted_count"
  exit 0
}

main "$@"
