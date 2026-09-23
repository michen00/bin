#!/usr/bin/env bats

load 'test_helper'

# A failing [[ ]] that is not the last command of a test does not fail the
# test under bash 3.2, so each [[ ]] check below ends with "|| false".

@test "touchx: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/touchx"
}

@test "touchx: --help displays usage information" {
	run --separate-stderr "$SCRIPTS_DIR/touchx" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "file"
	[ -z "$stderr" ]
}

@test "touchx: -h displays usage information" {
	run --separate-stderr "$SCRIPTS_DIR/touchx" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "file"
	[ -z "$stderr" ]
}

@test "touchx: fails with usage error when no arguments provided" {
	run --separate-stderr "$SCRIPTS_DIR/touchx"
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: No files specified."* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "touchx: fails with usage error when only -- is provided" {
	run --separate-stderr "$SCRIPTS_DIR/touchx" --
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: No files specified."* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "touchx: creates new executable file" {
	run "$SCRIPTS_DIR/touchx" newscript.sh
	[ "$status" -eq 0 ]
	assert_file_exists newscript.sh
	assert_executable newscript.sh
}

@test "touchx: makes existing file executable" {
	echo "existing content" >existing.sh
	chmod -x existing.sh

	run "$SCRIPTS_DIR/touchx" existing.sh
	[ "$status" -eq 0 ]
	assert_executable existing.sh
	# Content should be preserved
	grep -q "existing content" existing.sh
}

@test "touchx: handles multiple files" {
	run "$SCRIPTS_DIR/touchx" file1.sh file2.sh file3.sh
	[ "$status" -eq 0 ]
	assert_file_exists file1.sh
	assert_file_exists file2.sh
	assert_file_exists file3.sh
	assert_executable file1.sh
	assert_executable file2.sh
	assert_executable file3.sh
}

@test "touchx: fails with unknown option" {
	run --separate-stderr "$SCRIPTS_DIR/touchx" --unknown
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '--unknown'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "touchx: -- allows a file name that begins with a dash" {
	run "$SCRIPTS_DIR/touchx" -- -dash.sh
	[ "$status" -eq 0 ]
	assert_file_exists -dash.sh
	assert_executable -dash.sh
}

@test "touchx: treats option-like arguments after -- as files" {
	run "$SCRIPTS_DIR/touchx" before.sh -- --help -h
	[ "$status" -eq 0 ]
	assert_output_not_contains "Usage:"
	assert_executable before.sh
	assert_executable --help
	assert_executable -h
}

@test "touchx: fails on an empty file name" {
	run --separate-stderr "$SCRIPTS_DIR/touchx" ""
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Invalid filename ''."* ]] || false
	[ -z "$output" ]
}

@test "touchx: fails when the file cannot be created" {
	run --separate-stderr "$SCRIPTS_DIR/touchx" missing-dir/file.sh
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to create or update 'missing-dir/file.sh'."* ]] || false
	[ -z "$output" ]
}

@test "touchx: fails when the execute permission cannot be set" {
	run --separate-stderr env PATH="$(restricted_path bash basename touch)" "$SCRIPTS_DIR/touchx" file.sh
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to set execute permission for 'file.sh'."* ]] || false
	[ -z "$output" ]
}
