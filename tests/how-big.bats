#!/usr/bin/env bats

load 'test_helper'

@test "how-big: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/how-big"
}

@test "how-big: --help displays usage information" {
	run "$SCRIPTS_DIR/how-big" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "directory"
}

@test "how-big: -h displays usage information" {
	run "$SCRIPTS_DIR/how-big" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "directory"
}

@test "how-big: fails when directory does not exist" {
	run "$SCRIPTS_DIR/how-big" "nonexistent_dir"
	[ "$status" -ne 0 ]
	assert_output_contains "not a valid directory"
}

@test "how-big: shows size of current directory by default" {
	mkdir -p subdir
	echo "test content" >subdir/file.txt

	run "$SCRIPTS_DIR/how-big"
	[ "$status" -eq 0 ]
	# Output should contain size information
	[[ "$output" =~ [0-9] ]]
}

@test "how-big: shows size of specified directory" {
	mkdir -p testdir/subdir
	echo "test content" >testdir/subdir/file.txt

	run "$SCRIPTS_DIR/how-big" testdir
	[ "$status" -eq 0 ]
	assert_output_contains "testdir"
}

@test "how-big: -a shows individual file sizes" {
	mkdir -p testdir
	echo "content" >testdir/file.txt

	run "$SCRIPTS_DIR/how-big" -a testdir
	[ "$status" -eq 0 ]
	# Verify it shows the file (cross-platform fix uses find + du)
	assert_output_contains "file.txt"
}

@test "how-big: -a shows both files and subdirectories" {
	mkdir -p testdir/subdir
	echo "file content" >testdir/myfile.txt
	echo "subdir content" >testdir/subdir/nested.txt

	run "$SCRIPTS_DIR/how-big" -a testdir
	[ "$status" -eq 0 ]
	# Should show both the file and the subdirectory
	assert_output_contains "myfile.txt"
	assert_output_contains "subdir"
}

@test "how-big: without -a does not show individual files" {
	mkdir -p testdir/subdir
	echo "file content" >testdir/standalone.txt
	echo "subdir content" >testdir/subdir/nested.txt

	run "$SCRIPTS_DIR/how-big" testdir
	[ "$status" -eq 0 ]
	# Should show subdirectory but NOT the standalone file
	assert_output_contains "subdir"
	assert_output_not_contains "standalone.txt"
}

@test "how-big: -a works with current directory" {
	echo "root file" >rootfile.txt
	mkdir -p subdir
	echo "nested" >subdir/nested.txt

	run "$SCRIPTS_DIR/how-big" -a
	[ "$status" -eq 0 ]
	assert_output_contains "rootfile.txt"
}
