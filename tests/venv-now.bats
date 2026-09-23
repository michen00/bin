#!/usr/bin/env bats

load 'test_helper'

# A failing [[ ]] that is not the last command of a test does not fail the
# test under bash 3.2, so each [[ ]] check below ends with "|| false".

# Helper to put a stand-in interpreter in a directory. The stand-in records
# its name and fails, so that a test can see which interpreter the script ran.
# Parameters:
#   $1 - the directory to create it in
#   $2 - the command name, such as python or python3
fake_python() {
	local dir="$1"
	local name="$2"
	printf '#!/bin/sh\necho %s >>"%s/calls"\nexit 1\n' "$name" "$TEST_TEMP_DIR" >"$dir/$name"
	chmod +x "$dir/$name"
}

@test "venv-now: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/venv-now"
}

@test "venv-now: --help displays usage information" {
	run --separate-stderr "$SCRIPTS_DIR/venv-now" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "DIRECTORY"
	assert_output_contains "Show this help message and exit."
	[ -z "$stderr" ]
}

@test "venv-now: -h displays usage information" {
	run --separate-stderr "$SCRIPTS_DIR/venv-now" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "DIRECTORY"
	[ -z "$stderr" ]
}

@test "venv-now: help names the script when executed" {
	run --separate-stderr "$SCRIPTS_DIR/venv-now" -h
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Usage: venv-now [OPTIONS] [--] [DIRECTORY]" ]
}

@test "venv-now: creates .venv directory by default" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	run "$SCRIPTS_DIR/venv-now"
	[ "$status" -eq 0 ]
	assert_dir_exists ".venv"
	assert_file_exists ".venv/bin/activate"
}

@test "venv-now: creates custom-named venv directory" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	run "$SCRIPTS_DIR/venv-now" myenv
	[ "$status" -eq 0 ]
	assert_dir_exists "myenv"
	assert_file_exists "myenv/bin/activate"
}

@test "venv-now: --no-remove preserves existing venv" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	# Create initial venv with a marker file
	python3 -m venv .venv
	echo "marker" >.venv/marker.txt

	run "$SCRIPTS_DIR/venv-now" --no-remove
	[ "$status" -eq 0 ]
	# Marker file should still exist
	assert_file_exists ".venv/marker.txt"
}

@test "venv-now: removes existing venv by default" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	# Create initial venv with a marker file
	python3 -m venv .venv
	echo "marker" >.venv/marker.txt

	run "$SCRIPTS_DIR/venv-now"
	[ "$status" -eq 0 ]
	# Marker file should be gone (venv was recreated)
	[ ! -f ".venv/marker.txt" ]
}

@test "venv-now: -n is alias for --no-remove" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	python3 -m venv .venv
	echo "marker" >.venv/marker.txt

	run "$SCRIPTS_DIR/venv-now" -n
	[ "$status" -eq 0 ]
	assert_file_exists ".venv/marker.txt"
}

@test "venv-now: accepts an option after DIRECTORY" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	python3 -m venv myenv
	echo "marker" >myenv/marker.txt

	run "$SCRIPTS_DIR/venv-now" myenv -n
	[ "$status" -eq 0 ]
	assert_file_exists "myenv/marker.txt"
	[ ! -e .venv ]
}

@test "venv-now: -- treats a dash-prefixed argument as the directory" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	run --separate-stderr "$SCRIPTS_DIR/venv-now" -- -n
	[ "$status" -eq 0 ]
	assert_file_exists "-n/bin/activate"
	[ ! -e .venv ]
}

@test "venv-now: fails with unknown option" {
	run --separate-stderr "$SCRIPTS_DIR/venv-now" --unknown
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '--unknown'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "venv-now: fails with two directory arguments" {
	run --separate-stderr "$SCRIPTS_DIR/venv-now" one two
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple directory arguments specified: 'one' and 'two'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
	[ ! -e one ]
	[ ! -e two ]
}

@test "venv-now: fails with a second directory argument after --" {
	run --separate-stderr "$SCRIPTS_DIR/venv-now" one -- -two
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Multiple directory arguments specified: 'one' and '-two'"* ]] || false
	[ -z "$output" ]
	[ ! -e one ]
}

@test "venv-now: fails when Python is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename)" "$SCRIPTS_DIR/venv-now"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Python 3 is required but not installed."* ]] || false
	[[ "$stderr" == *"https://www.python.org/downloads/"* ]] || false
	[ -z "$output" ]
	[ ! -e .venv ]
}

@test "venv-now: prefers python to python3" {
	local dir
	dir="$(restricted_path bash basename)"
	fake_python "$dir" python
	fake_python "$dir" python3

	run --separate-stderr env PATH="$dir" "$SCRIPTS_DIR/venv-now"
	[ "$status" -eq 1 ]
	[ "$(cat calls)" = "python" ]
}

@test "venv-now: falls back to python3 when python is not installed" {
	local dir
	dir="$(restricted_path bash basename)"
	fake_python "$dir" python3

	run --separate-stderr env PATH="$dir" "$SCRIPTS_DIR/venv-now"
	[ "$status" -eq 1 ]
	[ "$(cat calls)" = "python3" ]
}

# A child shell runs this: it sources the script named by $1 with the
# remaining arguments, then prints the status of the source command, the active
# virtual environment, and any shell option that the sourced run turned on. A
# test can see from this output where a sourced run stopped and that the shell
# that sourced it kept running.
# shellcheck disable=SC2016 # The child shell expands these, not this file.
SOURCE_VENV_NOW='
script="$1"
shift
. "$script" "$@"
echo "status=$?"
echo "VIRTUAL_ENV=${VIRTUAL_ENV:-}"
case $- in *e* | *u*) echo "options changed: $-" ;; esac
if shopt -qo pipefail; then echo "options changed: pipefail"; fi
'

@test "venv-now: -h returns 0 from a sourced run without creating a venv" {
	run --separate-stderr bash -c "$SOURCE_VENV_NOW" _ "$SCRIPTS_DIR/venv-now" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "status=0"
	[ -z "$stderr" ]
	[ ! -e .venv ]
}

@test "venv-now: help names the script when sourced" {
	run --separate-stderr bash -c "$SOURCE_VENV_NOW" bash "$SCRIPTS_DIR/venv-now" -h
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Usage: venv-now [OPTIONS] [--] [DIRECTORY]" ]
	assert_output_contains "status=0"
	[ -z "$stderr" ]
}

@test "venv-now: help names the script when sourced from a login shell" {
	# A login shell's $0 is -bash, which basename would read as an option.
	run --separate-stderr bash -c "$SOURCE_VENV_NOW" -bash "$SCRIPTS_DIR/venv-now" -h
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Usage: venv-now [OPTIONS] [--] [DIRECTORY]" ]
	assert_output_contains "status=0"
	[ -z "$stderr" ]
}

@test "venv-now: unknown option returns 2 from a sourced run" {
	run --separate-stderr bash -c "$SOURCE_VENV_NOW" _ "$SCRIPTS_DIR/venv-now" --unknown
	[ "$status" -eq 0 ]
	assert_output_contains "status=2"
	assert_output_not_contains "Usage:"
	[[ "$stderr" == *"Error: Unknown option '--unknown'"* ]] || false
	assert_stderr_contains "Usage: venv-now [OPTIONS] [--] [DIRECTORY]"
	[ ! -e .venv ]
}

@test "venv-now: dangerous path returns 1 from a sourced run before any removal" {
	local home
	mkdir home
	touch home/keep
	home="$(cd home && pwd -P)"

	run --separate-stderr env HOME="$home" bash -c "$SOURCE_VENV_NOW" _ "$SCRIPTS_DIR/venv-now" "$home"
	[ "$status" -eq 0 ]
	assert_output_contains "status=1"
	assert_output_not_contains "Removing existing virtual environment"
	[[ "$stderr" == *"Error: Refusing to use dangerous path"* ]] || false
	assert_file_exists home/keep
	[ ! -e home/bin ]
}

@test "venv-now: missing Python returns 1 from a sourced run" {
	run --separate-stderr env PATH="$(restricted_path bash basename)" \
		bash -c "$SOURCE_VENV_NOW" _ "$SCRIPTS_DIR/venv-now"
	[ "$status" -eq 0 ]
	assert_output_contains "status=1"
	[[ "$stderr" == *"Error: Python 3 is required but not installed."* ]] || false
}

@test "venv-now: a sourced run does not change the calling shell's options" {
	run --separate-stderr bash -c "$SOURCE_VENV_NOW" _ "$SCRIPTS_DIR/venv-now" -h
	[ "$status" -eq 0 ]
	assert_output_contains "status=0"
	assert_output_not_contains "options changed"
}

@test "venv-now: a sourced run activates the venv given after --" {
	# Skip if python3 is not available
	if ! command -v python3 &>/dev/null; then
		skip "python3 not available"
	fi

	run --separate-stderr bash -c "$SOURCE_VENV_NOW" _ "$SCRIPTS_DIR/venv-now" -- -myenv
	[ "$status" -eq 0 ]
	assert_output_contains "Virtual environment activated: -myenv"
	assert_output_contains "status=0"
	[[ "$output" == *"VIRTUAL_ENV="*"/-myenv"* ]] || false
	assert_output_not_contains "options changed"
}

# Unit tests for is_dangerous_venv_path() - completely safe, no file operations
# These test the validation logic directly without invoking any dangerous ops

@test "is_dangerous_venv_path: rejects empty path" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "" "/some/path" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects dot" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "." "/current" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects double-dot" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path ".." "/parent" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects root path" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "/" "/" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects tilde" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "~" "$HOME" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects path resolving to HOME" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "some/path" "$HOME" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects path resolving to root" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "some/path" "/" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: rejects path resolving to current dir" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "foo/.." "/current" "/current"
	[ "$status" -eq 0 ] # 0 = dangerous
}

@test "is_dangerous_venv_path: accepts safe path" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path ".venv" "/project/.venv" "/project"
	[ "$status" -eq 1 ] # 1 = safe
}

@test "is_dangerous_venv_path: accepts custom venv name" {
	VENV_NOW_SOURCE_ONLY=1 source "$SCRIPTS_DIR/venv-now"
	run is_dangerous_venv_path "myenv" "/project/myenv" "/project"
	[ "$status" -eq 1 ] # 1 = safe
}

# Integration test for dangerous path rejection (uses safe test directory)
@test "venv-now: integration test rejects path resolving to current dir" {
	mkdir -p testdir
	# testdir/.. resolves to TEST_TEMP_DIR (current dir) - safe to test
	run --separate-stderr "$SCRIPTS_DIR/venv-now" "testdir/.."
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"dangerous path"* ]] || false
	[ -z "$output" ]
}
