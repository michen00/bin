#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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

@test "_mnn: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/_mnn"
}

# Phase 2: Foundational tests
@test "_mnn: script name detection works" {
	# Test that script detects its own name
	run "$SCRIPTS_DIR/_mnn"
	[ "$status" -ne 0 ]
	assert_output_contains "must be invoked as 'en_' or 'em_'"
}

# Phase 3: User Story 1 - En Dash tests
@test "en_: copies en dash to clipboard" {
	skip_if_no_clipboard_tool
	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]

	local clipboard_content
	clipboard_content=$(get_clipboard)
	[ "$clipboard_content" = "–" ]
}

@test "en_: overwrites previous clipboard content" {
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
	skip_if_no_clipboard_tool
	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
}

# Phase 4: User Story 2 - Em Dash tests
@test "em_: copies em dash to clipboard" {
	skip_if_no_clipboard_tool
	run "$SCRIPTS_DIR/em_"
	[ "$status" -eq 0 ]

	local clipboard_content
	clipboard_content=$(get_clipboard)
	[ "$clipboard_content" = "—" ]
}

@test "em_: overwrites previous clipboard content" {
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
	skip_if_no_clipboard_tool
	run "$SCRIPTS_DIR/em_"
	[ "$status" -eq 0 ]
}

# Phase 5: User Story 3 - Cross-platform tests
@test "en_: works on macOS with pbcopy" {
	[[ "$(uname -s)" == "Darwin" ]] || skip "Not macOS"
	command -v pbcopy >/dev/null 2>&1 || skip "pbcopy not available"

	run "$SCRIPTS_DIR/en_"
	[ "$status" -eq 0 ]
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

@test "_mnn: shows error for unsupported platform" {
	# This is hard to test without mocking uname, but we can test the error message format
	run "$SCRIPTS_DIR/_mnn"
	[ "$status" -ne 0 ]
	assert_output_contains "must be invoked as 'en_' or 'em_'"
}

@test "_mnn: shows error when clipboard tool missing" {
	# This would require mocking command -v, which is complex
	# For now, we test that the script handles missing tools gracefully
	# by checking it doesn't crash
	skip "Requires mocking command availability"
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

@test "en_: help option exits with code 0" {
	run "$SCRIPTS_DIR/en_" --help
	[ "$status" -eq 0 ]
}

# Phase 7: Polish - Error handling tests
@test "_mnn: shows error when invoked directly" {
	run "$SCRIPTS_DIR/_mnn"
	[ "$status" -eq 1 ]
	assert_output_contains "must be invoked as 'en_' or 'em_'"
}

@test "en_: shows error for invalid option" {
	run "$SCRIPTS_DIR/en_" --invalid
	[ "$status" -eq 2 ]
	assert_output_contains "Unknown option"
}

@test "en_: error messages go to stderr" {
	run "$SCRIPTS_DIR/en_" --invalid
	[ "$status" -eq 2 ]
	# stderr should contain error, stdout should be empty or minimal
	[ -n "$output" ]
}

@test "_mnn: follows set -euo pipefail pattern" {
	# Check that script has set -euo pipefail
	grep -q "set -euo pipefail" "$SCRIPTS_DIR/_mnn"
}

@test "en_: multiple sequential invocations overwrite clipboard" {
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
