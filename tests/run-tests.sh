#!/usr/bin/env bash
# Run tests for project scripts using bats framework
# Requires bash 4.0+ for array operations

# Read configuration from environment with defaults
PARALLEL="${PARALLEL:-true}"
SCRIPTS="${SCRIPTS:-*}"
SCRIPT_NAME=$(basename "$0")

# Terminal colors (tput with fallbacks to ANSI codes)
_COLOR=$(tput sgr0 2> /dev/null || printf '\033[0m')
CYAN=$(tput setaf 6 2> /dev/null || printf '\033[0;36m')
RED=$(tput setaf 1 2> /dev/null || printf '\033[0;31m')
YELLOW=$(tput setaf 3 2> /dev/null || printf '\033[0;33m')

usage() {
  cat << EOF
Usage: $SCRIPT_NAME

Run tests for project scripts using the bats framework.

Environment Variables:
  PARALLEL    Run tests in parallel (true|false, default: true)
  SCRIPTS     Which scripts to test (* for all, or comma-separated list, default: *)

Options:
  -h, --help  Show this help message and exit

Examples:
  # Run all tests in parallel (default)
  $SCRIPT_NAME

  # Run all tests sequentially
  PARALLEL=false $SCRIPT_NAME

  # Run tests for specific scripts
  SCRIPTS=ach,git-shed $SCRIPT_NAME

  # Run specific scripts sequentially
  PARALLEL=false SCRIPTS=touchx,chdirx $SCRIPT_NAME

Exit Codes:
  0    All tests passed
  1    Tests failed or invalid configuration
EOF
  exit "${1:-0}"
}

main() {
  # Parse arguments
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h | --help)
        usage 0
        ;;
      *)
        echo "${RED}Error: Unknown option '$1'${_COLOR}" >&2
        echo "Run '$SCRIPT_NAME --help' for usage information." >&2
        exit 1
        ;;
    esac
  fi

  # Discover test files based on SCRIPTS configuration
  local -a test_files=()

  if [[ "$SCRIPTS" == "*" ]]; then
    # Find all .bats files in tests directory
    while IFS= read -r -d '' test_file; do
      test_files+=("$test_file")
    done < <(find tests -maxdepth 1 -name '*.bats' -type f -print0 2> /dev/null)
  else
    # Parse comma-separated list of scripts
    local -a valid_tests=()
    local invalid_scripts=""
    local old_ifs=$IFS
    IFS=,

    for script in $SCRIPTS; do
      # Trim whitespace
      script=$(echo "$script" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # Validate script exists in project root
      if [[ ! -f "$script" ]]; then
        invalid_scripts="${invalid_scripts}${script} (script not found)\n"
      # Validate test file exists
      elif [[ ! -f "tests/$script.bats" ]]; then
        invalid_scripts="${invalid_scripts}${script} (test file not found)\n"
      else
        valid_tests+=("tests/$script.bats")
      fi
    done

    IFS=$old_ifs

    # Report errors if any invalid scripts found
    if [[ -n "$invalid_scripts" ]]; then
      echo "${RED}Error: The following scripts are invalid:${_COLOR}" >&2
      echo -e "$invalid_scripts" | sed 's/^/  - /' >&2
      echo "${YELLOW}Available scripts with tests:${_COLOR}" >&2

      # List available scripts
      while IFS= read -r -d '' f; do
        local script_name
        script_name=$(basename "$f" .bats)
        [[ -f "$script_name" ]] && echo "  - $script_name" >&2
      done < <(find tests -maxdepth 1 -name '*.bats' -type f -print0 2> /dev/null)

      exit 1
    fi

    test_files=("${valid_tests[@]}")
  fi

  # Verify at least one test file was found
  local script_count=${#test_files[@]}
  if [[ $script_count -eq 0 ]]; then
    echo "${RED}Error: No test files found${_COLOR}" >&2
    exit 1
  fi

  # Run tests based on configuration
  # Note: We use 'env -i' to run bats in a clean environment because the Makefile's
  # .ONESHELL directive can set shell options that interfere with bats parallel mode
  if [[ $script_count -eq 1 ]]; then
    # Single test: always run sequentially
    echo "${CYAN}Running test sequentially (1 script)...${_COLOR}"
    env -i HOME="$HOME" PATH="$PATH" TERM="${TERM:-}" bats "${test_files[0]}"
  elif [[ "$PARALLEL" == "true" ]]; then
    # Multiple tests with parallel mode enabled
    local jobs
    if [[ $script_count -lt 4 ]]; then
      jobs=$script_count
    else
      jobs=4
    fi

    echo "${CYAN}Running tests in parallel ($script_count scripts, --jobs $jobs)...${_COLOR}"
    env -i HOME="$HOME" PATH="$PATH" TERM="${TERM:-}" bats --jobs "$jobs" --timing "${test_files[@]}"
  else
    # Multiple tests, sequential mode
    echo "${CYAN}Running tests sequentially ($script_count scripts)...${_COLOR}"
    env -i HOME="$HOME" PATH="$PATH" TERM="${TERM:-}" bats "${test_files[@]}"
  fi
}

main "$@"
