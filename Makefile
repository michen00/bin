.ONESHELL:

DEBUG    ?= false
VERBOSE  ?= false

ifeq ($(DEBUG),true)
    MAKEFLAGS += --debug=v
else ifneq ($(VERBOSE),true)
    MAKEFLAGS += --silent
endif

PRECOMMIT ?= pre-commit
ifneq ($(shell command -v prek >/dev/null 2>&1 && echo y),)
    PRECOMMIT := prek
    ifneq ($(filter true,$(DEBUG) $(VERBOSE)),)
        $(info Using prek for pre-commit checks)
        ifeq ($(DEBUG),true)
            PRECOMMIT := $(PRECOMMIT) -v
        endif
    endif
endif

# Terminal formatting (tput with fallbacks to ANSI codes)
_COLOR  := $(shell tput sgr0 2>/dev/null || printf '\033[0m')
BOLD    := $(shell tput bold 2>/dev/null || printf '\033[1m')
CYAN    := $(shell tput setaf 6 2>/dev/null || printf '\033[0;36m')
GREEN   := $(shell tput setaf 2 2>/dev/null || printf '\033[0;32m')
RED     := $(shell tput setaf 1 2>/dev/null || printf '\033[0;31m')
YELLOW  := $(shell tput setaf 3 2>/dev/null || printf '\033[0;33m')

.DEFAULT_GOAL := help
.PHONY: help
help: ## Show this help message
	@echo "$(BOLD)Available targets:$(_COLOR)"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
        awk 'BEGIN {FS = ":.*?## "; max = 0} \
            {if (length($$1) > max) max = length($$1)} \
            {targets[NR] = $$0} \
            END {for (i = 1; i <= NR; i++) { \
                split(targets[i], arr, FS); \
                printf "$(CYAN)%-*s$(_COLOR) %s\n", max + 2, arr[1], arr[2]}}'
	@echo
	@echo "$(BOLD)Environment variables:$(_COLOR)"
	@echo "  $(YELLOW)DEBUG$(_COLOR) = true|false    Set to true to enable debug output (default: false)"
	@echo "  $(YELLOW)VERBOSE$(_COLOR) = true|false  Set to true to enable verbose output (default: false)"

.PHONY: develop
WITH_HOOKS ?= true
develop: ## Set up the project for development (WITH_HOOKS={true|false}, default=true)
	@if ! git config --local --get-all include.path | grep -q ".gitconfigs/alias"; then \
        git config --local --add include.path "$(CURDIR)/.gitconfigs/alias"; \
    fi
	@git config blame.ignoreRevsFile .git-blame-ignore-revs
	@set -e; \
    if command -v git-lfs >/dev/null 2>&1; then \
        git lfs install --local --skip-repo || true; \
    fi; \
    current_branch=$$(git branch --show-current); \
    stash_was_needed=0; \
    cleanup() { \
        exit_code=$$?; \
        if [ "$$current_branch" != "$$(git branch --show-current)" ]; then \
            echo "$(YELLOW)Attempting to return to $$current_branch...$(_COLOR)"; \
            if git switch "$$current_branch" 2>/dev/null; then \
                echo "Successfully returned to $$current_branch"; \
            else \
                echo "$(RED)Error: Could not return to $$current_branch. You are on $$(git branch --show-current).$(_COLOR)" >&2; \
                if [ "$$exit_code" -eq 0 ]; then exit_code=1; fi; \
            fi; \
        fi; \
        if [ $$stash_was_needed -eq 1 ] && git stash list | head -1 | grep -q "Auto stash before switching to main"; then \
            echo "$(YELLOW)Note: Your stashed changes are still available. Run 'git stash pop' to restore them.$(_COLOR)"; \
        fi; \
        exit $$exit_code; \
    }; \
    trap cleanup EXIT; \
    if ! git diff --quiet || ! git diff --cached --quiet; then \
        git stash push -m "Auto stash before switching to main"; \
        stash_was_needed=1; \
    fi; \
    git switch main && git pull; \
    if command -v git-lfs >/dev/null 2>&1; then \
        git lfs pull || true; \
    fi; \
    git switch "$$current_branch"; \
    if [ $$stash_was_needed -eq 1 ]; then \
        if git stash apply; then \
            git stash drop; \
        else \
            echo "$(RED)Error: Stash apply had conflicts. Resolve them, then run: git stash drop$(_COLOR)"; \
        fi; \
    fi; \
    trap - EXIT
	@if [ "$(WITH_HOOKS)" = "true" ]; then \
        $(MAKE) enable-pre-commit; \
    fi

.PHONY: test
PARALLEL ?= true
SCRIPTS ?= *
test: ## Run tests for specified scripts (PARALLEL={true|false}, SCRIPTS={script1,script2,...}, defaults: true, *)
	@if [ "$(SCRIPTS)" = "*" ]; then \
        test_files=$$(ls tests/*.bats 2>/dev/null); \
        script_count=$$(echo "$$test_files" | grep -c .); \
    else \
        valid_tests=""; \
        invalid_scripts=""; \
        scripts_var="$(SCRIPTS)"; \
        old_ifs=$$IFS; \
        IFS=,; \
        for script in $$scripts_var; do \
            script=$$(echo "$$script" | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
            if [ ! -f "$(CURDIR)/$$script" ]; then \
                invalid_scripts="$$invalid_scripts$$script (script not found)\n"; \
            elif [ ! -f "tests/$$script.bats" ]; then \
                invalid_scripts="$$invalid_scripts$$script (test file not found)\n"; \
            else \
                valid_tests="$$valid_tests tests/$$script.bats"; \
            fi; \
        done; \
        IFS=$$old_ifs; \
        if [ -n "$$invalid_scripts" ]; then \
            echo "$(RED)Error: The following scripts are invalid:$(_COLOR)" >&2; \
            echo "$$invalid_scripts" | sed 's/^/  - /' >&2; \
            echo "$(YELLOW)Available scripts with tests:$(_COLOR)" >&2; \
            for f in tests/*.bats; do \
                script=$$(basename "$$f" .bats); \
                [ -f "$(CURDIR)/$$script" ] && echo "  - $$script" >&2; \
            done; \
            exit 1; \
        fi; \
        test_files=$$valid_tests; \
        script_count=$$(echo $$valid_tests | wc -w | tr -d ' '); \
    fi; \
    if [ -z "$$test_files" ]; then \
        echo "$(RED)Error: No test files found$(_COLOR)" >&2; \
        exit 1; \
    fi; \
    if [ "$$script_count" -eq 1 ]; then \
        echo "$(CYAN)Running test sequentially (1 script)...$(_COLOR)"; \
        bats $$test_files; \
    elif [ "$(PARALLEL)" = "true" ]; then \
        if [ "$$script_count" -le 3 ]; then \
            jobs=$$script_count; \
        else \
            jobs=4; \
        fi; \
        echo "$(CYAN)Running tests in parallel ($$script_count scripts, --jobs $$jobs)...$(_COLOR)"; \
        bats --jobs $$jobs --timing $$test_files; \
    else \
        echo "$(CYAN)Running tests sequentially ($$script_count scripts)...$(_COLOR)"; \
        bats $$test_files; \
    fi

.PHONY: check
check: run-pre-commit test ## Run all code quality checks and tests

.PHONY: enable-pre-commit
enable-pre-commit: ## Enable pre-commit hooks (along with commit-msg and pre-push hooks)
	@if command -v pre-commit >/dev/null 2>&1; then \
        pre-commit install --hook-type commit-msg --hook-type pre-commit --hook-type pre-push --hook-type prepare-commit-msg ; \
    else \
        echo "$(YELLOW)Warning: pre-commit is not installed. Skipping hook installation.$(_COLOR)"; \
        echo "Install it with: pip install pre-commit (or brew install pre-commit on macOS)"; \
    fi

.PHONY: run-pre-commit
run-pre-commit: ## Run the pre-commit checks
	$(PRECOMMIT) run --all-files
