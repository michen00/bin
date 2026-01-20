#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'test_helper'

VALIDATION_SCRIPT="$SCRIPTS_DIR/.github/scripts/validate-scripts.sh"

# Setup function - runs before each test
setup() {
	# Create a temporary directory for test files
	TEST_TEMP_DIR="$(mktemp -d)"
	cd "$TEST_TEMP_DIR" || return 1

	# Create basic repository structure
	mkdir -p tests
	mkdir -p .github/scripts

	# Copy validation script to test directory
	cp "$VALIDATION_SCRIPT" .github/scripts/validate-scripts.sh
	chmod +x .github/scripts/validate-scripts.sh

	# Create a basic README.md with Scripts section
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
- [`script2`](script2): Second test script.
EOF
}

# Teardown function - runs after each test
teardown() {
	# Clean up temporary directory
	if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
		rm -rf "$TEST_TEMP_DIR"
	fi
}

@test "validate-scripts: script has valid bash syntax" {
	bash -n "$VALIDATION_SCRIPT"
}

@test "validate-scripts: --help displays usage information" {
	run "$VALIDATION_SCRIPT" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "EXEMPTED_SCRIPT"
}

@test "validate-scripts: -h displays usage information" {
	run "$VALIDATION_SCRIPT" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "validate-scripts: validation passes when all scripts have README entries and test files" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	chmod +x script1 script2

	# Create test files
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	chmod +x tests/script1.bats tests/script2.bats

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
}

@test "validate-scripts: validation fails when script missing README entry" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	echo '#!/usr/bin/env bash' >script3 # Missing from README
	chmod +x script1 script2 script3

	# Create test files
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	echo '#!/usr/bin/env bats' >tests/script3.bats
	chmod +x tests/script1.bats tests/script2.bats tests/script3.bats

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	# With new validation order: correspondence check runs before count check
	# So specific error is reported (missing README entry for script3)
	assert_output_contains "Missing README Entries"
	assert_output_contains "script3"
}

@test "validate-scripts: validation fails when README entry references non-existent script" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1

	# Create test files
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README with entry for non-existent script
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
- [`nonexistent`](nonexistent): This script doesn't exist.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	# With new validation order: correspondence check runs before count check
	# So specific error is reported (orphaned README entry for nonexistent)
	assert_output_contains "Orphaned README Entries"
	assert_output_contains "nonexistent"
}

@test "validate-scripts: validation fails when script missing test file" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	chmod +x script1 script2

	# Create only one test file
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats
	# script2.bats is missing

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	assert_output_contains "Missing Test Files"
	assert_output_contains "script2"
}

@test "validate-scripts: exempted scripts are excluded from validation" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	echo '#!/usr/bin/env bash' >exempted-script # Will be exempted
	chmod +x script1 script2 exempted-script

	# Create test files (exempted-script has no test)
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	chmod +x tests/script1.bats tests/script2.bats

	# Update README (exempted-script not in README)
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
- [`script2`](script2): Second test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh exempted-script
	[ "$status" -eq 0 ]
}

@test "validate-scripts: orphaned test files are allowed" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1

	# Create test files (including orphaned one)
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/orphaned-test.bats # No corresponding script
	chmod +x tests/script1.bats tests/orphaned-test.bats

	# Ensure README has entry for script1
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
}

@test "validate-scripts: validation fails when README entry missing backticks" {
	# Create script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README with entry missing backticks
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [script1](script1): First test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	assert_output_contains "Formatting Errors"
}

@test "validate-scripts: validation fails when description doesn't start with capital letter" {
	# Create script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README with lowercase description
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): first test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	assert_output_contains "Formatting Errors"
}

@test "validate-scripts: validation fails when description doesn't end with period" {
	# Create script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README with description missing period
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	assert_output_contains "Formatting Errors"
}

@test "validate-scripts: validation fails when link text doesn't match link URL" {
	# Create script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README with mismatched link
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script2): First test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	assert_output_contains "Formatting Errors"
}

@test "validate-scripts: validation passes when all entries properly formatted" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	chmod +x script1 script2
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	chmod +x tests/script1.bats tests/script2.bats

	# Create properly formatted README
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
- [`script2`](script2): Second test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
}

@test "validate-scripts: validation passes when description contains parentheses with backticks" {
	# Create script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README with description containing parentheses and backticks
	# This tests that the link URL regex correctly extracts (script1) and not
	# the parentheses from the description
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): Add the last commit hash to a given file (`.git-blame-ignore-revs` file by default).
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
}

@test "validate-scripts: validation fails when README entries not sorted alphabetically" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	chmod +x script1 script2
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	chmod +x tests/script1.bats tests/script2.bats

	# Create README with entries out of order
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script2`](script2): Second test script.
- [`script1`](script1): First test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	assert_output_contains "Sorting Errors"
}

@test "validate-scripts: validation passes when entries are alphabetically sorted" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	chmod +x script1 script2
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	chmod +x tests/script1.bats tests/script2.bats

	# Create README with entries in alphabetical order
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
- [`script2`](script2): Second test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
}

@test "validate-scripts: validation fails when script count doesn't match README entry count" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	echo '#!/usr/bin/env bash' >script3
	chmod +x script1 script2 script3
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	echo '#!/usr/bin/env bats' >tests/script3.bats
	chmod +x tests/script1.bats tests/script2.bats tests/script3.bats

	# Create README with only 2 entries (but 3 scripts)
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
- [`script2`](script2): Second test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 1 ]
	# With new validation order: correspondence check runs before count check
	# So specific error is reported (missing README entry for script3)
	# Note: Count check still exists as a fallback but won't be triggered
	# when correspondence check catches the specific issue first
	assert_output_contains "Missing README Entries"
	assert_output_contains "script3"
}

@test "validate-scripts: validation passes when counts match (allows extra test files)" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	chmod +x script1 script2
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	echo '#!/usr/bin/env bats' >tests/orphaned-test.bats # Extra test file
	chmod +x tests/script1.bats tests/script2.bats tests/orphaned-test.bats

	# Create README with 2 entries (matching 2 scripts)
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
- [`script2`](script2): Second test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
}

@test "validate-scripts: success message shows counts when validation passes" {
	# Create scripts
	echo '#!/usr/bin/env bash' >script1
	echo '#!/usr/bin/env bash' >script2
	chmod +x script1 script2

	# Create test files
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '#!/usr/bin/env bats' >tests/script2.bats
	chmod +x tests/script1.bats tests/script2.bats

	# Create README with 2 entries
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): First test script.
- [`script2`](script2): Second test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
	# Verify success message contains counts
	assert_output_contains "Validation passed"
	assert_output_contains "Scripts:"
	assert_output_contains "Test files:"
	assert_output_contains "README entries:"
}

@test "validate-scripts: validation fails when script lacks shebang" {
	# Create script without shebang
	echo 'echo "test"' >script1
	chmod +x script1

	# Create README entry
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): Test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -ne 0 ]
	assert_output_contains "README-referenced script 'script1' lacks shebang"
}

@test "validate-scripts: validation fails when script lacks executable permissions" {
	# Create script with shebang but no executable permissions
	echo '#!/usr/bin/env bash' >script1
	chmod -x script1

	# Create README entry
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): Test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -ne 0 ]
	assert_output_contains "README-referenced script 'script1' lacks executable permissions"
}

@test "validate-scripts: validation fails when test file lacks shebang" {
	# Create valid script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1

	# Create test file without shebang
	echo '@test "test" { true; }' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README entry
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): Test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -ne 0 ]
	assert_output_contains "Test file 'tests/script1.bats' lacks shebang"
}

@test "validate-scripts: validation fails when test file lacks executable permissions" {
	# Create valid script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1

	# Create test file with shebang but no executable permissions
	echo '#!/usr/bin/env bats' >tests/script1.bats
	echo '@test "test" { true; }' >>tests/script1.bats
	chmod -x tests/script1.bats

	# Create README entry
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): Test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -ne 0 ]
	assert_output_contains "Test file 'tests/script1.bats' lacks executable permissions"
}

@test "validate-scripts: validation fails when README-referenced script lacks shebang or executable permissions" {
	# Create script with shebang but no executable permissions
	echo '#!/usr/bin/env bash' >script1
	chmod -x script1

	# Create README entry
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script1`](script1): Test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -ne 0 ]
	assert_output_contains "README-referenced script 'script1' lacks executable permissions"
}

@test "validate-scripts: validation stops immediately on first error (fail-fast behavior)" {
	# Create script without README entry (first error)
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create another script with formatting error (second error - should not be reported)
	echo '#!/usr/bin/env bash' >script2
	chmod +x script2
	echo '#!/usr/bin/env bats' >tests/script2.bats
	chmod +x tests/script2.bats

	# Create README with only script2 entry (missing script1, malformed script2 entry)
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`script2`](script2): first test script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -ne 0 ]
	# With new validation order: formatting check runs first
	# Should only report the first error (formatting error for script2: lowercase 'first')
	assert_output_contains "Formatting Errors"
	assert_output_contains "script2"
	assert_output_contains "must start with capital letter"
	# Should NOT report the count mismatch or missing README entry (fail-fast stops at first error)
	assert_output_not_contains "Missing README Entries"
	assert_output_not_contains "Count Mismatch"
}

@test "validate-scripts: HTML comments in README Scripts section are ignored" {
	# Create script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README with HTML comments
	cat >README.md <<'EOF'
# Test Repository

## Scripts

<!-- This is a comment -->
- [`script1`](script1): First test script.
<!-- Another comment -->
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
}

@test "validate-scripts: files with extensions in project root are ignored" {
	# Create script without extension (should be validated)
	echo '#!/usr/bin/env bash' >validscript
	chmod +x validscript
	echo '#!/usr/bin/env bats' >tests/validscript.bats
	chmod +x tests/validscript.bats

	# Create files with extensions (should be ignored)
	echo '#!/usr/bin/env bash' >ignored.sh
	chmod +x ignored.sh
	echo '#!/usr/bin/env python' >ignored.py
	chmod +x ignored.py

	# Create README with only valid script
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`validscript`](validscript): Valid script without extension.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
	# Should not complain about ignored.sh or ignored.py
	assert_output_not_contains "ignored.sh"
	assert_output_not_contains "ignored.py"
}

@test "validate-scripts: hidden files in project root are ignored" {
	# Create script (should be validated)
	echo '#!/usr/bin/env bash' >validscript
	chmod +x validscript
	echo '#!/usr/bin/env bats' >tests/validscript.bats
	chmod +x tests/validscript.bats

	# Create hidden file (should be ignored)
	echo '#!/usr/bin/env bash' >.hidden-script
	chmod +x .hidden-script

	# Create README with only valid script
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`validscript`](validscript): Valid script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
	# Should not complain about .hidden-script
	assert_output_not_contains ".hidden-script"
}

@test "validate-scripts: symbolic links in project root are ignored" {
	# Create script (should be validated)
	echo '#!/usr/bin/env bash' >validscript
	chmod +x validscript
	echo '#!/usr/bin/env bats' >tests/validscript.bats
	chmod +x tests/validscript.bats

	# Create symbolic link (should be ignored)
	echo '#!/usr/bin/env bash' >target-script
	chmod +x target-script
	ln -s target-script symlink-script

	# Create README with only valid script
	cat >README.md <<'EOF'
# Test Repository

## Scripts

- [`validscript`](validscript): Valid script.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -eq 0 ]
	# Should not complain about symlink-script
	assert_output_not_contains "symlink-script"
}

@test "validate-scripts: validation fails when README is malformed (missing Scripts section)" {
	# Create script
	echo '#!/usr/bin/env bash' >script1
	chmod +x script1
	echo '#!/usr/bin/env bats' >tests/script1.bats
	chmod +x tests/script1.bats

	# Create README without Scripts section
	cat >README.md <<'EOF'
# Test Repository

## Other Section

Some content here.
EOF

	run bash ./.github/scripts/validate-scripts.sh
	[ "$status" -ne 0 ]
	assert_output_contains "README.md is missing '## Scripts' section"
}

@test "validate-scripts: validation handles empty repository gracefully" {
	# Create empty repository (no scripts, no tests)
	# README with empty Scripts section
	cat >README.md <<'EOF'
# Test Repository

## Scripts

EOF

	run bash ./.github/scripts/validate-scripts.sh
	# Should pass (0 scripts = 0 README entries = 0 test files)
	[ "$status" -eq 0 ]
	assert_output_contains "Validation passed"
	assert_output_contains "Scripts: 0"
	assert_output_contains "README entries: 0"
}
