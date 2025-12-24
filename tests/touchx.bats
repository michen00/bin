#!/usr/bin/env bats

load 'test_helper'

@test "touchx: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/touchx"
}

@test "touchx: --help displays usage information" {
	run "$SCRIPTS_DIR/touchx" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "file"
}

@test "touchx: -h displays usage information" {
	run "$SCRIPTS_DIR/touchx" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "file"
}

@test "touchx: displays usage when no arguments provided" {
	run "$SCRIPTS_DIR/touchx"
	[ "$status" -ne 0 ]
	assert_output_contains "Usage:"
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
	run "$SCRIPTS_DIR/touchx" --unknown
	[ "$status" -ne 0 ]
	assert_output_contains "Unknown option"
}
