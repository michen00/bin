#!/usr/bin/env bats

load 'test_helper'

# A failing [[ ]] that is not the last command of a test does not fail the
# test under bash 3.2, so each [[ ]] check below ends with "|| false".

@test "how-big: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/how-big"
}

@test "how-big: --help displays usage information" {
	run --separate-stderr "$SCRIPTS_DIR/how-big" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "directory"
	[ -z "$stderr" ]
}

@test "how-big: -h displays usage information" {
	run --separate-stderr "$SCRIPTS_DIR/how-big" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "directory"
	[ -z "$stderr" ]
}

@test "how-big: help has an Arguments section and the standard help description" {
	run "$SCRIPTS_DIR/how-big" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Arguments:"
	assert_output_contains "[directory]"
	assert_output_contains "Show this help message and exit."
}

@test "how-big: unknown option exits 2 with error on stderr" {
	run --separate-stderr "$SCRIPTS_DIR/how-big" -x
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '-x'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "how-big: second directory exits 2 with error on stderr" {
	mkdir -p dir1 dir2

	run --separate-stderr "$SCRIPTS_DIR/how-big" dir1 dir2
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unexpected argument 'dir2'"* ]] || false
	[ -z "$output" ]
}

@test "how-big: second directory after -- exits 2 with error on stderr" {
	mkdir -p dir1 dir2

	run --separate-stderr "$SCRIPTS_DIR/how-big" -- dir1 dir2
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unexpected argument 'dir2'"* ]] || false
	[ -z "$output" ]
}

@test "how-big: fails when directory does not exist" {
	run --separate-stderr "$SCRIPTS_DIR/how-big" "nonexistent_dir"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: 'nonexistent_dir' is not a valid directory."* ]] || false
	[ -z "$output" ]
}

@test "how-big: shows size of current directory by default" {
	mkdir -p subdir
	echo "test content" >subdir/file.txt

	run "$SCRIPTS_DIR/how-big"
	[ "$status" -eq 0 ]
	# Output should contain size information
	[[ "$output" =~ [0-9] ]] || false
}

@test "how-big: shows size of specified directory" {
	mkdir -p testdir/subdir
	echo "test content" >testdir/subdir/file.txt

	run "$SCRIPTS_DIR/how-big" testdir
	[ "$status" -eq 0 ]
	assert_output_contains "testdir"
}

@test "how-big: -- alone uses the current directory" {
	mkdir -p subdir

	run "$SCRIPTS_DIR/how-big" --
	[ "$status" -eq 0 ]
	assert_output_contains "./subdir"
}

@test "how-big: -- accepts a directory whose name begins with a dash" {
	mkdir -p -- -testdir/subdir

	run --separate-stderr "$SCRIPTS_DIR/how-big" -- -testdir
	[ "$status" -eq 0 ]
	assert_output_contains "./-testdir/subdir"
	[ -z "$stderr" ]
}

@test "how-big: -a with -- shows files in a directory whose name begins with a dash" {
	mkdir -p -- -testdir/subdir
	echo "content" >./-testdir/file.txt

	run --separate-stderr "$SCRIPTS_DIR/how-big" -a -- -testdir
	[ "$status" -eq 0 ]
	# The file line comes from find and the directory line from du, so both
	# carry the same ./ prefix.
	assert_output_contains "./-testdir/file.txt"
	assert_output_contains "./-testdir/subdir"
	# If find received the path as given, it would reject it and the script
	# would print a warning.
	[ -z "$stderr" ]
}

@test "how-big: -a shows individual file sizes" {
	mkdir -p testdir
	echo "content" >testdir/file.txt

	run "$SCRIPTS_DIR/how-big" -a testdir
	[ "$status" -eq 0 ]
	# Verify it shows the file (cross-platform fix uses find + du)
	assert_output_contains "file.txt"
}

@test "how-big: -a after the directory shows individual file sizes" {
	mkdir -p testdir
	echo "content" >testdir/file.txt

	run "$SCRIPTS_DIR/how-big" testdir -a
	[ "$status" -eq 0 ]
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

@test "how-big: unreadable entry prints partial results and a warning on stderr" {
	if [[ $EUID -eq 0 ]]; then
		skip "root can read a directory without read permission"
	fi
	mkdir -p testdir/locked testdir/readable
	echo "content" >testdir/readable/file.txt
	chmod 000 testdir/locked

	run --separate-stderr "$SCRIPTS_DIR/how-big" testdir
	# Restore access before any assertion so that teardown can remove it.
	chmod 755 testdir/locked
	[ "$status" -eq 0 ]
	assert_output_contains "testdir/readable"
	assert_output_not_contains "Warning:"
	[[ "$stderr" == *"Warning: Some entries could not be read"* ]] || false
}
