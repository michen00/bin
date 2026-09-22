# bin Constitution

## Core Principles

### I. Script-First

Every utility is a standalone, independently executable script with a clear, single purpose, callable directly from the command line.

Scripts SHOULD depend on nothing beyond standard Unix utilities. A script MAY require an external tool where that tool is the point of the script, but it MUST then probe for it before use — `command -v <tool> >/dev/null 2>&1` — and fail with a message naming both the missing tool and how to install it. A missing dependency is a diagnosable condition, never a stack trace from the middle of a run.

### II. CLI Interface

All scripts MUST follow Unix conventions: text input and output via stdin/stdout/stderr, and exit codes that distinguish success from failure. Scripts MUST support both interactive and non-interactive usage.

Every script that accepts arguments MUST carry built-in help text. That help is the script's documentation of record for anyone at a terminal, so it MUST describe every argument and option the script accepts.

Help text MUST be a heredoc — `cat <<EOF` inside a `usage()` function, or a `HELP=$(cat <<EOF ...)` variable — never a run of `echo` calls. It MUST follow this shape:

- The first line is the synopsis, written `Usage: $SCRIPT_NAME <synopsis>` on one line. `SCRIPT_NAME` MUST be derived once near the top of the file with `SCRIPT_NAME=$(basename "$0")` and interpolated wherever the script names itself, so that a script reachable under more than one name reports the name it was actually called by.
- A prose description follows the synopsis directly, unlabelled. A `Description:` heading labels the obvious when there is only one prose block.
- Then, as needed and in this order: `Arguments:`, `Options:`, `Examples:`.
- `Options:` MUST list `-h, --help` last, described as "Show this help message and exit."
- `Examples:` MUST show real invocations with `$SCRIPT_NAME` interpolated.

Both `-h` and `--help` MUST be accepted. Arguments MUST be parsed by a `while [[ $# -gt 0 ]]; do case "$1" in ... esac done` loop rather than `getopts`, and an unrecognized dash-prefixed option MUST be rejected rather than silently treated as a positional argument. A script whose positional arguments could legitimately begin with a dash MUST support `--` as an end-of-options marker.

Help and diagnostics are different streams, and which one a script writes to MUST depend on why it is printing:

- Help that was **asked for** — `-h` or `--help` — is the successful output of the run. It goes to **stdout** and exits **0**.
- Help **reprinted after a usage error**, and every error and warning message, is diagnostic. It goes to **stderr** and exits **non-zero**.

Error messages MUST be prefixed `Error:` and non-fatal conditions `Warning:`, and MUST name the operation that failed and, where one exists, the remedy.

### III. Test-First

Every script in the project root MUST have comprehensive test coverage using bats, written before or alongside the implementation. Tests MUST cover happy paths, error cases, edge cases, and help output, and MUST all pass before merging. Test files belong in `tests/` and are named `[script-name].bats`.

This obligation applies to scripts in the project root — the utilities this repository distributes. Scripts elsewhere (`.github/scripts/`, development tooling, helper scripts) are not required to have tests, though they MAY have them.

### IV. Simplicity

Scripts MUST prioritize simplicity and maintainability. Follow YAGNI. Avoid unnecessary complexity, abstraction, or premature optimization. Scripts MUST be readable by developers familiar with bash. When complexity is unavoidable, it MUST be justified and documented — in a comment that names the failure mode it prevents, not one that restates the next line.

### V. Portability

Scripts distributed by this repository — those in the project root — MUST run on the oldest bash a supported platform ships. In practice that is macOS's `/bin/bash`, GPLv2-frozen at 3.2, so the root scripts MUST avoid `declare -A`, `mapfile`/`readarray`, `local -n` namerefs, and `${var^^}`/`${var,,}`. Every root script uses `#!/usr/bin/env bash`, which on a machine with a newer bash on `PATH` resolves to that one — so this constraint is invisible in normal use and breaks silently. Assume nothing tests it for you.

Repository tooling that is never distributed MAY require a newer bash. Where it does, it MUST state the requirement in a comment at the top of the file and enforce it at runtime with a `BASH_VERSINFO` check naming the version found, the version required, and how to install a newer one.

Avoid system-specific paths and assumptions. Prefer POSIX constructs where they cost nothing, but bash is the target language and `[[ ]]`, indexed arrays and `+=` are all fair use.

### VI. Self-Documenting

A script's documentation has two homes, and both are required:

1. Its **help text**, per Principle II — what a person gets from the script itself.
2. Its **README entry**, under `## Scripts`, formatted ``- [`script-name`](script-name): Description.`` — what a person gets before they run anything.

Because the help text already carries the full description of arguments, options and examples, a root script does NOT need a file-level comment block repeating them. A reader who opens the file sees the shebang, strict mode, and then code; the prose lives where a user can reach it.

The inverse is the rule that matters for everything else. **A script with no reachable help text MUST carry a file-level comment block instead** — its purpose, how it is invoked, and by what. A CI entry point, a git hook, a test fixture and a sourced library are all read far more often than they are run, and for them the header is the only documentation there is.

Comment blocks and help text MUST NOT duplicate each other. Whichever one a reader can reach is the one that carries the burden.

## Development Standards

### Bash Best Practices

- Scripts MUST enable strict mode — `set -euo pipefail` — before the first executable statement, immediately after the shebang and any file-level comment block. Position is free; presence is not. A script that must relax a flag MUST say why in a comment at the point of the exception. A script intended to be sourced MUST guard strict mode behind a sourcing check, since these flags persist into the caller's shell.
- Variables MUST be quoted to prevent word splitting and pathname expansion.
- Functions MUST be used for reusable logic. Locals MUST be `local`-declared and lower_snake_case; globals are UPPER_CASE. Where a command substitution's exit status matters, the declaration MUST be split from the assignment, since `local x=$(cmd)` masks that status from `set -e`.
- Scripts that create recoverable state — a temp file, a stash, a partially written file, an unstaged change — MUST install a `trap` that restores it, and MUST clear the trap on success paths that no longer need it. Scripts that create no such state do not need one.
- Scripts MUST validate inputs and provide clear error messages.
- Exit codes MUST distinguish a usage error — the caller invoked the script wrongly — from an operational failure. Both are non-zero; a script MUST NOT report them with the same code.

### Code Quality

- Scripts MUST pass shellcheck. A `# shellcheck disable=` directive MUST sit on the line above the statement it excuses and MUST carry a same-line justification naming why the warning does not apply.
- Scripts MUST follow consistent formatting, applied by `shfmt` through pre-commit. `shfmt` is deliberately given no arguments so that it reads `.editorconfig`, whose `[*.sh]` section matches only files ending in `.sh` — the root scripts, having no extension, are formatted by `shfmt`'s own defaults (tabs, unindented case arms, no space after redirection operators). The two groups are formatted by two different rule sets. This is intended; do not "fix" one to match the other.
- Complex logic MUST be commented for clarity, explaining why rather than what.

## Quality Assurance

### Testing Requirements

- All scripts in the project root MUST have corresponding test files in `tests/`, per Principle III.
- Tests MUST use the bats framework, minimum version 1.5.0.
- Tests MUST be independent and idempotent, and MUST clean up after themselves.
- Integration tests MUST use isolated test environments.
- Every script's test file MUST assert that the script parses (`bash -n`) and that its help text works — both `-h` and `--help`, each exiting 0 and containing the `Usage:` line.

### Correspondence

Every executable file at the project root with a shebang MUST have a matching `tests/<name>.bats` and a README entry under `## Scripts` — unless it is the target of a root symlink, in which case the **aliases** carry the README entries and the target carries none. `_mnn` is the case that defines the rule: `em_` and `en_` are listed, `_mnn` is not, and adding an entry for it would fail the count check.

README entries MUST be sorted, MUST have link text identical to the link target, and MUST have a description beginning with a capital letter and ending with a period.

Scripts and test files MUST have both a shebang and the executable bit; neither alone is sufficient.

`.github/scripts/validate-scripts.sh` enforces the correspondence rules and pre-commit's `check-executables-have-shebangs` and `check-shebang-scripts-are-executable` enforce the pairing. Note what that does **not** amount to: `validate-scripts.yml` is path-filtered and then gated on a step that looks for a changed extensionless file starting with a shebang, so a README-only pull request runs the workflow and skips the check — which is exactly the pull request the sorting, capitalization and period rules exist for. The rules above hold whether or not a given pull request happens to run them.

### Continuous Integration

- All tests MUST pass in CI before merging.
- Pre-commit hooks MUST validate script syntax and formatting.
- Code review MUST verify test coverage and constitution compliance.

## Governance

This constitution supersedes all other development practices and guidelines. All pull requests and code reviews MUST verify compliance with these principles.

**Amendment Process**: Amendments require documentation of the proposed change and its rationale, an impact analysis naming every script the change puts in violation, and a version increment per the policy below. An amendment MAY create known deviations, provided it records them; a rule is written for the behavior wanted, not weakened to match the behavior present.

**Versioning Policy**:

- MAJOR: Backward incompatible principle removals or redefinitions
- MINOR: New principle added or materially expanded guidance
- PATCH: Clarifications, wording improvements, typo fixes

**Compliance Review**: A pull request that violates a principle MUST say so and justify it. Nothing in this repository blocks a merge on constitution grounds; the check is a human one.

**Discoverability**: A document that claims to supersede all other development practices has to be reachable from the documents contributors actually read. `README.md` and `CONTRIBUTING.md` MUST link to this file. Neither does today — the word "constitution" appears nowhere outside `.specify/`, so a contributor can read `CONTRIBUTING.md` end to end and never learn this exists.

## Known Deviations

The Amendment Process in § Governance requires an amendment to record the deviations it creates. Each entry below is open, and is to be resolved by a follow-up change rather than by weakening the rule that names it.

- § II sends help printed after a usage error to stderr. Only `git-shed` does this today; `chdirx`, `mergewith`, `touchx`, `update-mine`, `venv-now` and `.scripts/concat_gitignores.sh` call `usage 1`, whose `cat` writes to stdout.
- § II requires both `-h` and `--help`. `update-mine` accepts only `--help` and actively rejects `-h` as an unknown option.
- § II's help shape. `git-shed` lists `-h, --help` first in its `Options:` block rather than last, inlines `$(basename "$0")` instead of deriving `SCRIPT_NAME` once, and puts its `Description:` heading after `Arguments:`/`Options:` rather than leaving unlabelled prose under the synopsis. `gcfixup` opens with a name-and-tagline line rather than the `Usage:` synopsis, and lists `-h`/`--help` nowhere despite accepting both.
- § II requires error messages prefixed `Error:` and non-fatal conditions `Warning:`. `.github/scripts/validate-scripts.sh` follows that only in its bash-version guard and its `find` warning. Its README-not-found and missing-`## Scripts` paths use `ERROR:`, and its dominant failure style is a `❌ Validation Failed` banner over a labelled block, which carries no prefix at all.
- § V requires a declared and enforced minimum where a script needs a newer bash. `.github/scripts/validate-scripts.sh` fully complies. `scripts/test-prepare-readme.sh` enforces 4.3 at runtime but declares nothing at the top of the file, and its error names neither the version found nor how to install a newer one. `.scripts/concat_gitignores.sh` needs bash 4+ for `mapfile` and neither declares nor enforces anything.
- § Governance requires `README.md` and `CONTRIBUTING.md` to link here. Neither does.

### Deliberately Unsettled

**The exit code for an unrecognized option.** The corpus is split two against five — `_mnn` and `git-shed` exit 2; `chdirx`, `mergewith`, `touchx`, `update-mine` and `venv-now` route through `usage 1`. § Bash Best Practices requires only that usage errors and operational failures be distinguishable, because legislating either number silently puts the other group in violation.

**Version**: 1.1.0 | **Ratified**: 2026-01-18 | **Last Amended**: 2026-09-20
