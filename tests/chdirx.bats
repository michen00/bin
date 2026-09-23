#!/usr/bin/env bats

load 'test_helper'

# A failing [[ ]] that is not the last command of a test does not fail the
# test under bash 3.2, so each [[ ]] check below ends with "|| false".

@test "chdirx: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/chdirx"
}

@test "chdirx: --help displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/chdirx" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "directory"
	[ -z "$stderr" ]
}

@test "chdirx: -h displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/chdirx" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "directory"
	[ -z "$stderr" ]
}

@test "chdirx: rejects an unknown option" {
	run --separate-stderr "$SCRIPTS_DIR/chdirx" --bogus
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '--bogus'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "chdirx: fails when no directory specified" {
	run --separate-stderr "$SCRIPTS_DIR/chdirx"
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: No directory specified."* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "chdirx: fails when more than one directory is specified" {
	mkdir dir1 dir2
	echo '#!/usr/bin/env bash' >dir1/script.sh
	chmod -x dir1/script.sh

	run --separate-stderr "$SCRIPTS_DIR/chdirx" dir1 dir2
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple directories specified: 'dir1' and 'dir2'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
	[ ! -x dir1/script.sh ]
}

@test "chdirx: rejects a directory given after an empty one" {
	mkdir testdir
	echo '#!/usr/bin/env bash' >testdir/script.sh
	chmod -x testdir/script.sh

	run --separate-stderr "$SCRIPTS_DIR/chdirx" '' testdir
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple directories specified: '' and 'testdir'"* ]] || false
	[ -z "$output" ]
	[ ! -x testdir/script.sh ]
}

@test "chdirx: rejects an empty directory given after a directory" {
	mkdir testdir

	run --separate-stderr "$SCRIPTS_DIR/chdirx" testdir ''
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple directories specified: 'testdir' and ''"* ]] || false
	[ -z "$output" ]
}

@test "chdirx: fails with exit 1 when the directory argument is empty" {
	run --separate-stderr "$SCRIPTS_DIR/chdirx" ''
	[ "$status" -eq 1 ]
	[ "$stderr" = "Error: '' is not a directory." ]
	[ -z "$output" ]
}

@test "chdirx: fails when directory does not exist" {
	run --separate-stderr "$SCRIPTS_DIR/chdirx" "nonexistent_dir"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: 'nonexistent_dir' is not a directory."* ]] || false
	[ -z "$output" ]
}

@test "chdirx: makes shebang files executable" {
	mkdir testdir
	echo '#!/usr/bin/env bash' >testdir/script.sh
	echo 'echo hello' >>testdir/script.sh
	chmod -x testdir/script.sh

	run "$SCRIPTS_DIR/chdirx" testdir
	[ "$status" -eq 0 ]
	assert_executable testdir/script.sh
}

@test "chdirx: ignores files without shebang" {
	mkdir testdir
	echo 'just text' >testdir/readme.txt
	chmod -x testdir/readme.txt

	run "$SCRIPTS_DIR/chdirx" testdir
	[ "$status" -eq 0 ]
	[ ! -x testdir/readme.txt ]
}

@test "chdirx: -r processes subdirectories recursively" {
	mkdir -p testdir/subdir
	echo '#!/usr/bin/env bash' >testdir/script1.sh
	echo '#!/usr/bin/env bash' >testdir/subdir/script2.sh
	chmod -x testdir/script1.sh testdir/subdir/script2.sh

	run "$SCRIPTS_DIR/chdirx" -r testdir
	[ "$status" -eq 0 ]
	assert_executable testdir/script1.sh
	assert_executable testdir/subdir/script2.sh
}

@test "chdirx: without -r does not process subdirectories" {
	mkdir -p testdir/subdir
	echo '#!/usr/bin/env bash' >testdir/subdir/script.sh
	chmod -x testdir/subdir/script.sh

	run "$SCRIPTS_DIR/chdirx" testdir
	[ "$status" -eq 0 ]
	[ ! -x testdir/subdir/script.sh ]
}

@test "chdirx: -- accepts a directory whose name begins with a dash" {
	mkdir -- -testdir
	echo '#!/usr/bin/env bash' >-testdir/script.sh
	chmod -- -x -testdir/script.sh

	run --separate-stderr "$SCRIPTS_DIR/chdirx" -- -testdir
	[ "$status" -eq 0 ]
	assert_executable -testdir/script.sh
	assert_output_contains "Added executable permission to: -testdir/script.sh"
	[ -z "$stderr" ]
}

@test "chdirx: -r -- processes subdirectories of a dash-prefixed directory" {
	mkdir -p -- -testdir/subdir
	echo '#!/usr/bin/env bash' >-testdir/subdir/script.sh
	chmod -- -x -testdir/subdir/script.sh

	run --separate-stderr "$SCRIPTS_DIR/chdirx" -r -- -testdir
	[ "$status" -eq 0 ]
	assert_executable -testdir/subdir/script.sh
	[ -z "$stderr" ]
}

@test "chdirx: -- without a directory is a usage error" {
	run --separate-stderr "$SCRIPTS_DIR/chdirx" --
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: No directory specified."* ]] || false
	[ -z "$output" ]
}

@test "chdirx: treats every argument after -- as a directory" {
	mkdir testdir

	run --separate-stderr "$SCRIPTS_DIR/chdirx" -- testdir -r
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple directories specified: 'testdir' and '-r'"* ]] || false
	[ -z "$output" ]
}

@test "chdirx: warns about an unreadable file and continues" {
	if [ "$(id -u)" -eq 0 ]; then
		skip "root can read every file"
	fi
	mkdir testdir
	echo '#!/usr/bin/env bash' >testdir/a-unreadable.sh
	echo '#!/usr/bin/env bash' >testdir/b-readable.sh
	chmod 000 testdir/a-unreadable.sh
	chmod -x testdir/b-readable.sh

	run --separate-stderr "$SCRIPTS_DIR/chdirx" testdir
	[ "$status" -eq 0 ]
	[[ "$stderr" == *"Warning: Skipping 'testdir/a-unreadable.sh' because it is not readable."* ]] || false
	[ ! -x testdir/a-unreadable.sh ]
	assert_executable testdir/b-readable.sh
}

@test "chdirx: fails with an error when chmod fails" {
	mkdir testdir
	echo '#!/usr/bin/env bash' >testdir/script.sh

	# Leaving chmod out of PATH makes the chmod call fail.
	run --separate-stderr env PATH="$(restricted_path bash basename head grep)" "$SCRIPTS_DIR/chdirx" testdir
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to add executable permission to 'testdir/script.sh'."* ]] || false
	[ -z "$output" ]
}
