#!/usr/bin/env bats

load 'test_helper'

@test "chdirx: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/chdirx"
}

@test "chdirx: --help displays usage information" {
	run "$SCRIPTS_DIR/chdirx" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "directory"
}

@test "chdirx: -h displays usage information" {
	run "$SCRIPTS_DIR/chdirx" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "directory"
}

@test "chdirx: fails when no directory specified" {
	run "$SCRIPTS_DIR/chdirx"
	[ "$status" -ne 0 ]
	assert_output_contains "No directory specified"
}

@test "chdirx: fails when directory does not exist" {
	run "$SCRIPTS_DIR/chdirx" "nonexistent_dir"
	[ "$status" -ne 0 ]
	assert_output_contains "is not a directory"
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
