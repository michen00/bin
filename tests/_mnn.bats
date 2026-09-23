#!/usr/bin/env bats

load 'test_helper'

# Helper function to get clipboard content (platform-specific)
get_clipboard() {
	case "$(uname -s)" in
	Darwin*)
		pbpaste 2>/dev/null || echo ""
		;;
	Linux*)
		if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
			wl-paste 2>/dev/null || echo ""
		else
			xclip -selection clipboard -o 2>/dev/null || xsel --clipboard --output 2>/dev/null || echo ""
		fi
		;;
	CYGWIN* | MINGW* | MSYS*)
		# Windows clipboard reading is complex, skip for now
		echo ""
		;;
	*)
		echo ""
		;;
	esac
}

# Helper to check if clipboard tool is available
has_clipboard_tool() {
	case "$(uname -s)" in
	Darwin*)
		command -v pbcopy >/dev/null 2>&1
		;;
	Linux*)
		if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
			command -v wl-copy >/dev/null 2>&1
		else
			command -v xclip >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1
		fi
		;;
	CYGWIN* | MINGW* | MSYS*)
		command -v clip.exe >/dev/null 2>&1
		;;
	*)
		return 1
		;;
	esac
}

# Helper to write a stub command into a PATH directory, so that a test can make
# the script see a platform or a clipboard tool other than the host's without
# touching the system clipboard.
# Parameters:
#   $1 - directory to write the stub into
#   $2 - command name
#   $3 - shell code for the stub to run
stub_command() {
	printf '#!/bin/sh\n%s\n' "$3" >"$1/$2"
	chmod +x "$1/$2"
}

# Helper to put stubs for pbcopy and pbpaste first on PATH. On macOS, pbcopy
# then writes to a file in the test's temporary directory and pbpaste reads that
# file, so a test run leaves the developer's clipboard unchanged. On other
# platforms, neither the script nor these tests call pbcopy or pbpaste, so the
# stubs have no effect.
stub_macos_clipboard() {
	local bin_dir="$TEST_TEMP_DIR/clipboard-bin"
	mkdir -p "$bin_dir"
	# shellcheck disable=SC2016  # The stub expands $0 when it runs, not this helper.
	stub_command "$bin_dir" pbcopy 'cat >"${0%/*}/clipboard"'
	# shellcheck disable=SC2016  # The stub expands $0 when it runs, not this helper.
	stub_command "$bin_dir" pbpaste 'cat "${0%/*}/clipboard"'
	PATH="$bin_dir:$PATH"
}

# Helper to check that help text in $output attributes each dash to the command
# that copies it: every line that shows the en dash or U+2013 names en_, and
# every line that shows the em dash or U+2014 names em_. A line that shows a
# dash without naming its command says that the invoked name copies that dash.
assert_dashes_attributed_to_commands() {
	local stray
	stray=$(grep -E '–|U\+2013' <<<"$output" | grep -v 'en_' || true)
	stray+=$(grep -E '—|U\+2014' <<<"$output" | grep -v 'em_' || true)
	if [[ -n "$stray" ]]; then
		echo "Expected every dash to be attributed to en_ or em_; found: $stray"
		return 1
	fi
}

# On platforms other than macOS, the clipboard tests share one resource that no
# temporary directory can isolate: the system clipboard. Under `bats --jobs N`
# (CI uses 4), the tests in a file run concurrently, so a sibling test can copy
# between this test's copy and its read-back, and the read-back returns the
# other test's dash. Serialize this file on those platforms; it still runs in
# parallel with every other file in the suite. On macOS, stub_macos_clipboard
# gives each test its own clipboard file, so the tests need no serialization.
setup_file() {
	if [[ "$(uname -s)" != Darwin* ]]; then
		export BATS_NO_PARALLELIZE_WITHIN_FILE=true
	fi
}

@test "_mnn: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/_mnn"
}

# Phase 2: Foundational tests
@test "_mnn: shows error when invoked through an unrecognized name" {
	ln -s "$SCRIPTS_DIR/_mnn" "$TEST_TEMP_DIR/dash"

	run --separate-stderr "$TEST_TEMP_DIR/dash"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: This script must be invoked as 'en_' or 'em_'"* ]] || false
	[ -z "$output" ]
}

# Phase 3: User Story 1 - En Dash tests
@test "en_: copies en dash to clipboard" {
	stub_macos_clipboard
	skip_if_no_clipboard_tool
	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]

	local clipboard_content
	clipboard_content=$(get_clipboard)
	[ "$clipboard_content" = "–" ]
}

@test "en_: overwrites previous clipboard content" {
	stub_macos_clipboard
	skip_if_no_clipboard_tool

	# Put something in clipboard first
	case "$(uname -s)" in
	Darwin*)
		echo -n "test content" | pbcopy
		;;
	Linux*)
		if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
			echo -n "test content" | wl-copy
		else
			echo -n "test content" | xclip -selection clipboard 2>/dev/null || echo -n "test content" | xsel --clipboard 2>/dev/null
		fi
		;;
	CYGWIN* | MINGW* | MSYS*)
		echo "test content" | clip.exe
		;;
	esac

	# Run en_ and verify it overwrote
	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]

	local clipboard_content
	clipboard_content=$(get_clipboard)
	[ "$clipboard_content" = "–" ]
	[ "$clipboard_content" != "test content" ]
}

@test "en_: exits with code 0 on success" {
	stub_macos_clipboard
	skip_if_no_clipboard_tool
	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
}

# Phase 4: User Story 2 - Em Dash tests
@test "em_: copies em dash to clipboard" {
	stub_macos_clipboard
	skip_if_no_clipboard_tool
	run "$SCRIPTS_DIR/em_"
	[ "$status" -eq 0 ]

	local clipboard_content
	clipboard_content=$(get_clipboard)
	[ "$clipboard_content" = "—" ]
}

@test "em_: overwrites previous clipboard content" {
	stub_macos_clipboard
	skip_if_no_clipboard_tool

	# Put something in clipboard first
	case "$(uname -s)" in
	Darwin*)
		echo -n "test content" | pbcopy
		;;
	Linux*)
		if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
			echo -n "test content" | wl-copy
		else
			echo -n "test content" | xclip -selection clipboard 2>/dev/null || echo -n "test content" | xsel --clipboard 2>/dev/null
		fi
		;;
	CYGWIN* | MINGW* | MSYS*)
		echo "test content" | clip.exe
		;;
	esac

	# Run em_ and verify it overwrote
	run "$SCRIPTS_DIR/em_"
	[ "$status" -eq 0 ]

	local clipboard_content
	clipboard_content=$(get_clipboard)
	[ "$clipboard_content" = "—" ]
	[ "$clipboard_content" != "test content" ]
}

@test "em_: exits with code 0 on success" {
	stub_macos_clipboard
	skip_if_no_clipboard_tool
	run "$SCRIPTS_DIR/em_"
	[ "$status" -eq 0 ]
}

# Phase 5: User Story 3 - Cross-platform tests
@test "en_: works on macOS with pbcopy" {
	[[ "$(uname -s)" == "Darwin" ]] || skip "Not macOS"
	stub_macos_clipboard

	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
	# A command substitution would remove a newline that the script copied
	# after the dash. The test reads the clipboard with --keep-empty-lines,
	# which keeps that newline in $output, so the comparison detects it.
	run --keep-empty-lines pbpaste
	[ "$output" = "–" ]
}

@test "em_: works on macOS with pbcopy" {
	[[ "$(uname -s)" == "Darwin" ]] || skip "Not macOS"
	stub_macos_clipboard

	run "$SCRIPTS_DIR/em_"
	[ "$status" -eq 0 ]
	run --keep-empty-lines pbpaste
	[ "$output" = "—" ]
}

@test "en_: works on Linux X11 with xclip" {
	[[ "$(uname -s)" == "Linux" ]] || skip "Not Linux"
	[[ -z "${WAYLAND_DISPLAY:-}" ]] || skip "Not X11"
	command -v xclip >/dev/null 2>&1 || skip "xclip not available"

	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
}

@test "en_: falls back to xsel when xclip unavailable on X11" {
	[[ "$(uname -s)" == "Linux" ]] || skip "Not Linux"
	[[ -z "${WAYLAND_DISPLAY:-}" ]] || skip "Not X11"
	command -v xsel >/dev/null 2>&1 || skip "xsel not available"
	# Only test if xclip is not available
	command -v xclip >/dev/null 2>&1 && skip "xclip is available"

	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
}

@test "en_: works on Linux Wayland with wl-copy" {
	[[ "$(uname -s)" == "Linux" ]] || skip "Not Linux"
	[[ -n "${WAYLAND_DISPLAY:-}" ]] || skip "Not Wayland"
	command -v wl-copy >/dev/null 2>&1 || skip "wl-copy not available"

	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
}

@test "en_: works on Windows with clip.exe" {
	[[ "$(uname -s)" =~ ^(CYGWIN|MINGW|MSYS) ]] || skip "Not Windows"
	command -v clip.exe >/dev/null 2>&1 || skip "clip.exe not available"

	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
}

@test "en_: shows error for unsupported platform" {
	local bin_dir
	bin_dir=$(restricted_path bash basename)
	stub_command "$bin_dir" uname 'echo Plan9'

	run --separate-stderr env PATH="$bin_dir" "$SCRIPTS_DIR/en_"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Unsupported platform: Plan9."* ]] || false
	[ -z "$output" ]
}

@test "en_: shows error when pbcopy is missing on macOS" {
	local bin_dir
	bin_dir=$(restricted_path bash basename)
	stub_command "$bin_dir" uname 'echo Darwin'

	run --separate-stderr env PATH="$bin_dir" "$SCRIPTS_DIR/en_"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Clipboard tool 'pbcopy' not found. macOS installs it in /usr/bin; add /usr/bin to PATH."* ]] || false
	[ -z "$output" ]
}

@test "en_: shows error when xclip and xsel are missing on X11" {
	local bin_dir
	bin_dir=$(restricted_path bash basename)
	stub_command "$bin_dir" uname 'echo Linux'

	run --separate-stderr env -u WAYLAND_DISPLAY PATH="$bin_dir" "$SCRIPTS_DIR/en_"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Clipboard tool 'xclip' or 'xsel' not found."* ]] || false
	[ -z "$output" ]
}

@test "en_: shows error when wl-copy is missing on Wayland" {
	local bin_dir
	bin_dir=$(restricted_path bash basename)
	stub_command "$bin_dir" uname 'echo Linux'

	run --separate-stderr env WAYLAND_DISPLAY=wayland-0 PATH="$bin_dir" "$SCRIPTS_DIR/en_"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Clipboard tool 'wl-copy' not found."* ]] || false
	[ -z "$output" ]
}

@test "en_: shows error when clip.exe is missing on Windows" {
	local bin_dir
	bin_dir=$(restricted_path bash basename)
	stub_command "$bin_dir" uname 'echo MINGW64_NT-10.0'

	run --separate-stderr env PATH="$bin_dir" "$SCRIPTS_DIR/en_"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Clipboard tool 'clip.exe' not found. Windows installs it in its System32 directory; add that directory to PATH."* ]] || false
	[ -z "$output" ]
}

@test "en_: passes the clipboard command's arguments as separate words" {
	local bin_dir
	bin_dir=$(restricted_path bash basename cat)
	stub_command "$bin_dir" uname 'echo Linux'
	# shellcheck disable=SC2016  # The stub expands these when it runs, not this test.
	stub_command "$bin_dir" xclip 'printf "%s\n" "$@" >"${0%/*}/xclip-args"; cat >"${0%/*}/xclip-input"'

	run --separate-stderr env -u WAYLAND_DISPLAY PATH="$bin_dir" "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
	[ "$(cat "$bin_dir/xclip-args")" = $'-selection\nclipboard' ]
	[ "$(cat "$bin_dir/xclip-input")" = "–" ]
}

@test "en_: shows error when the clipboard command fails" {
	local bin_dir
	bin_dir=$(restricted_path bash basename cat)
	stub_command "$bin_dir" uname 'echo Linux'
	stub_command "$bin_dir" xclip 'cat >/dev/null; exit 3'

	run --separate-stderr env -u WAYLAND_DISPLAY PATH="$bin_dir" "$SCRIPTS_DIR/en_"
	[ "$status" -eq 1 ]
	[ "$stderr" = "Error: Failed to copy to clipboard with 'xclip' (exit status 3)." ]
	[ -z "$output" ]
}

# Phase 6: User Story 4 - Help tests
@test "en_: --help displays help message" {
	run "$SCRIPTS_DIR/en_" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "en dash"
	assert_output_contains "U+2013"
}

@test "en_: -h displays help message" {
	run "$SCRIPTS_DIR/en_" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "en dash"
}

@test "em_: --help displays help message" {
	run "$SCRIPTS_DIR/em_" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "em dash"
	assert_output_contains "U+2014"
}

@test "em_: -h displays help message" {
	run "$SCRIPTS_DIR/em_" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "em dash"
}

@test "en_: help goes to stdout with nothing on stderr" {
	run --separate-stderr "$SCRIPTS_DIR/en_" -h
	[ "$status" -eq 0 ]
	[[ "$output" == "Usage: en_ [OPTIONS]"* ]] || false
	[ -z "$stderr" ]
}

@test "en_: help option exits with code 0" {
	run "$SCRIPTS_DIR/en_" --help
	[ "$status" -eq 0 ]
}

@test "en_: help points to em_ for an em dash" {
	run "$SCRIPTS_DIR/en_" --help
	[ "$status" -eq 0 ]
	grep -q 'em_.*em dash' <<<"$output"
}

@test "em_: help points to en_ for an en dash" {
	run "$SCRIPTS_DIR/em_" --help
	[ "$status" -eq 0 ]
	grep -q 'en_.*en dash' <<<"$output"
}

@test "en_: help omits the note about invoking the script by another name" {
	run "$SCRIPTS_DIR/en_" --help
	[ "$status" -eq 0 ]
	assert_output_not_contains "must be invoked as"
}

@test "_mnn: help lists the dash that each command copies" {
	run "$SCRIPTS_DIR/_mnn" --help
	[ "$status" -eq 0 ]
	grep -Eq '^ *en_ .*U\+2013' <<<"$output"
	grep -Eq '^ *em_ .*U\+2014' <<<"$output"
}

@test "_mnn: help does not say that _mnn copies a dash" {
	run "$SCRIPTS_DIR/_mnn" --help
	[ "$status" -eq 0 ]
	assert_dashes_attributed_to_commands
}

@test "_mnn: help under an unrecognized name does not say that name copies a dash" {
	ln -s "$SCRIPTS_DIR/_mnn" "$TEST_TEMP_DIR/dash"

	run "$TEST_TEMP_DIR/dash" --help
	[ "$status" -eq 0 ]
	grep -Eq '^ *en_ .*U\+2013' <<<"$output"
	grep -Eq '^ *em_ .*U\+2014' <<<"$output"
	assert_dashes_attributed_to_commands
}

# Phase 7: Polish - Error handling tests
@test "_mnn: shows error when invoked directly" {
	run --separate-stderr "$SCRIPTS_DIR/_mnn"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: This script must be invoked as 'en_' or 'em_'"* ]] || false
	[ -z "$output" ]
}

@test "_mnn: --help works when invoked directly" {
	run --separate-stderr "$SCRIPTS_DIR/_mnn" --help
	[ "$status" -eq 0 ]
	[[ "$output" == "Usage: _mnn [OPTIONS]"* ]] || false
	[ -z "$stderr" ]
}

@test "_mnn: -h works when invoked directly" {
	run --separate-stderr "$SCRIPTS_DIR/_mnn" -h
	[ "$status" -eq 0 ]
	[[ "$output" == "Usage: _mnn [OPTIONS]"* ]] || false
	[ -z "$stderr" ]
}

@test "_mnn: unknown option exits 2 when invoked directly" {
	run --separate-stderr "$SCRIPTS_DIR/_mnn" --invalid
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '--invalid'"* ]] || false
	[[ "$stderr" == *"Run '_mnn --help' for usage information."* ]] || false
	[ -z "$output" ]
}

@test "en_: shows error for invalid option" {
	run --separate-stderr "$SCRIPTS_DIR/en_" --invalid
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '--invalid'"* ]] || false
	[ -z "$output" ]
}

@test "en_: error messages go to stderr" {
	run --separate-stderr "$SCRIPTS_DIR/en_" --invalid
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Run 'en_ --help' for usage information."* ]] || false
	[ -z "$output" ]
}

@test "en_: shows error for unexpected argument" {
	run --separate-stderr "$SCRIPTS_DIR/en_" foo
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unexpected argument 'foo'; en_ accepts no arguments."* ]] || false
	[[ "$stderr" == *"Run 'en_ --help' for usage information."* ]] || false
	[[ "$stderr" != *"Unknown option"* ]] || false
	[ -z "$output" ]
}

@test "em_: shows error for unexpected argument before -h" {
	run --separate-stderr "$SCRIPTS_DIR/em_" foo -h
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unexpected argument 'foo'"* ]] || false
	[ -z "$output" ]
}

@test "_mnn: follows set -euo pipefail pattern" {
	# Check that script has set -euo pipefail
	grep -q "set -euo pipefail" "$SCRIPTS_DIR/_mnn"
}

@test "en_: multiple sequential invocations overwrite clipboard" {
	stub_macos_clipboard
	skip_if_no_clipboard_tool

	# Run en_ first
	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]

	local clipboard1
	clipboard1=$(get_clipboard)
	[ "$clipboard1" = "–" ]

	# Run em_ second - should overwrite
	run "$SCRIPTS_DIR/em_"
	[ "$status" -eq 0 ]

	local clipboard2
	clipboard2=$(get_clipboard)
	[ "$clipboard2" = "—" ]
	[ "$clipboard2" != "$clipboard1" ]
}

# Helper function to skip tests if clipboard tool is not available
skip_if_no_clipboard_tool() {
	has_clipboard_tool || skip "Clipboard tool not available on this platform"
}
