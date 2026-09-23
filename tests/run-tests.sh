#!/usr/bin/env bash
set -euo pipefail

# Read configuration from environment with defaults
PARALLEL="${PARALLEL:-true}"
SCRIPTS="${SCRIPTS:-*}"
SCRIPT_NAME=$(basename "$0")

# A stream gets color codes only when it is a terminal, so that a line
# written to a file or a pipe begins with its text, such as "Error:". tput
# runs only for a terminal, and each code falls back to its ANSI sequence
# when tput fails. RED and YELLOW are for stderr; CYAN is for stdout.
RED=""
YELLOW=""
ERR_RESET=""
if [[ -t 2 ]]; then
  RED=$(tput setaf 1 2> /dev/null || printf '\033[0;31m')
  YELLOW=$(tput setaf 3 2> /dev/null || printf '\033[0;33m')
  ERR_RESET=$(tput sgr0 2> /dev/null || printf '\033[0m')
fi
CYAN=""
OUT_RESET=""
if [[ -t 1 ]]; then
  CYAN=$(tput setaf 6 2> /dev/null || printf '\033[0;36m')
  # The reset code depends on the terminal type, not on the stream, so
  # stdout reuses the stderr code instead of running tput a second time.
  OUT_RESET=${ERR_RESET:-$(tput sgr0 2> /dev/null || printf '\033[0m')}
fi

usage() {
  cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Run tests for project scripts using the bats framework.

Options:
  -h, --help  Show this help message and exit.

Examples:
  # Run all tests in parallel (default)
  $SCRIPT_NAME

  # Run all tests sequentially
  PARALLEL=false $SCRIPT_NAME

  # Run tests for specific scripts
  SCRIPTS=ach,git-shed $SCRIPT_NAME

  # Run specific scripts sequentially
  PARALLEL=false SCRIPTS=touchx,chdirx $SCRIPT_NAME

Environment Variables:
  PARALLEL    Run tests in parallel (true|false, default: true)
  SCRIPTS     Which scripts to test (* for all, or comma-separated list, default: *)

Exit Codes:
  0    All tests passed
  1    Tests failed, invalid configuration, or bats not installed
  2    Unknown option or unexpected argument
EOF
}

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        echo "${RED}Error: Unknown option '$1'${ERR_RESET}" >&2
        echo "Run '$SCRIPT_NAME --help' for usage information." >&2
        exit 2
        ;;
      *)
        echo "${RED}Error: Unexpected argument '$1'${ERR_RESET}" >&2
        echo "Run '$SCRIPT_NAME --help' for usage information." >&2
        exit 2
        ;;
    esac
  done

  if ! command -v bats > /dev/null 2>&1; then
    echo "${RED}Error: 'bats' is required but not installed.${ERR_RESET}" >&2
    echo "Install it from: https://github.com/bats-core/bats-core" >&2
    exit 1
  fi

  if [[ "$PARALLEL" != "true" && "$PARALLEL" != "false" ]]; then
    echo "${RED}Error: Invalid PARALLEL value '$PARALLEL'; use 'true' or 'false'.${ERR_RESET}" >&2
    exit 1
  fi

  # Discover test files based on SCRIPTS configuration
  local -a test_files=()

  if [[ "$SCRIPTS" == "*" ]]; then
    # Find all .bats files in tests directory
    local test_file
    while IFS= read -r -d '' test_file; do
      test_files+=("$test_file")
    done < <(find tests -maxdepth 1 -name '*.bats' -type f -print0 2> /dev/null)
  else
    # Parse comma-separated list of scripts
    local -a valid_tests=()
    local -a requested_scripts=()
    local invalid_scripts=""
    local script
    # read -a splits on commas without pathname expansion, so a name such
    # as "t*" is checked literally instead of expanding to the files in the
    # current directory. -d '' reads past newlines, so no name is dropped,
    # and printf adds no trailing newline to the last name, as a here-string
    # would. read returns 1 at the end of input because no NUL delimiter
    # arrives.
    IFS=, read -r -d '' -a requested_scripts < <(printf '%s' "$SCRIPTS") || true

    for script in ${requested_scripts[@]+"${requested_scripts[@]}"}; do
      # Trim whitespace
      script=$(printf '%s\n' "$script" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

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

    # Report errors if any invalid scripts found
    if [[ -n "$invalid_scripts" ]]; then
      echo "${RED}Error: The following scripts are invalid:${ERR_RESET}" >&2
      printf '%b' "$invalid_scripts" | sed 's/^/  - /' >&2
      echo "${YELLOW}Available scripts with tests:${ERR_RESET}" >&2

      # List available scripts
      local f
      local script_name
      while IFS= read -r -d '' f; do
        script_name=$(basename "$f" .bats)
        if [[ -f "$script_name" ]]; then
          echo "  - $script_name" >&2
        fi
      done < <(find tests -maxdepth 1 -name '*.bats' -type f -print0 2> /dev/null)

      exit 1
    fi

    test_files=(${valid_tests[@]+"${valid_tests[@]}"})
  fi

  # Verify at least one test file was found
  local script_count=${#test_files[@]}
  if [[ $script_count -eq 0 ]]; then
    echo "${RED}Error: No test files found in ./tests; run this script from the repository root.${ERR_RESET}" >&2
    exit 1
  fi

  # Run tests based on configuration
  # Note: We use 'env -i' to run bats in a clean environment because the Makefile's
  # .ONESHELL directive can set shell options that interfere with bats parallel mode
  if [[ $script_count -eq 1 ]]; then
    # Single test: always run sequentially
    echo "${CYAN}Running test sequentially (1 script)...${OUT_RESET}"
    env -i HOME="${HOME:-}" PATH="$PATH" TERM="${TERM:-}" bats "${test_files[0]}"
  elif [[ "$PARALLEL" == "true" ]]; then
    # Multiple tests with parallel mode enabled
    local jobs
    if [[ $script_count -lt 4 ]]; then
      jobs=$script_count
    else
      jobs=4
    fi

    echo "${CYAN}Running tests in parallel ($script_count scripts, --jobs $jobs)...${OUT_RESET}"
    env -i HOME="${HOME:-}" PATH="$PATH" TERM="${TERM:-}" bats --jobs "$jobs" --timing "${test_files[@]}"
  else
    # Multiple tests, sequential mode
    echo "${CYAN}Running tests sequentially ($script_count scripts)...${OUT_RESET}"
    env -i HOME="${HOME:-}" PATH="$PATH" TERM="${TERM:-}" bats "${test_files[@]}"
  fi
}

main "$@"
