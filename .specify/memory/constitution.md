<!--
Sync Impact Report:
Version: 1.0.0 → 1.0.1
Ratified: 2025-01-18
Last Amended: 2026-01-18

Principles Modified:
- III. Test-First: Clarified scope - only scripts in project root require testing

Sections Modified:
- Quality Assurance / Testing Requirements: Clarified scope

Templates Status:
✅ plan-template.md - No changes needed (generic testing guidance)
✅ spec-template.md - No changes needed (generic testing guidance)
✅ tasks-template.md - No changes needed (tests are optional per spec)
✅ Command files - No outdated references found

Version Bump Rationale: PATCH - Clarification of testing scope (scripts in project root vs other scripts like dev scripts). No breaking changes, backward compatible.
-->

# bin Constitution

## Core Principles

### I. Script-First

Every utility is a standalone, independently executable script. Scripts MUST be self-contained with no external runtime dependencies beyond standard Unix utilities. Each script MUST have a clear, single purpose. Scripts MUST be executable and callable directly from the command line.

### II. CLI Interface

All scripts MUST follow Unix conventions: text input/output via stdin/stdout/stderr, proper exit codes (0 for success, non-zero for failure), and comprehensive help messages via `--help` or `-h`. Scripts MUST support both interactive and non-interactive usage. Error messages MUST be clear and actionable, written to stderr.

### III. Test-First (NON-NEGOTIABLE)

Every script in the project root MUST have comprehensive test coverage using bats. Tests MUST be written before or alongside implementation. Tests MUST cover happy paths, error cases, edge cases, and help output. All tests MUST pass before merging. Test files MUST be located in `tests/` directory with naming convention `[script-name].bats`.

**Scope**: This requirement applies to scripts located in the project root directory. Scripts in other locations (e.g., `.github/scripts/`, development tooling, or helper scripts) may be exempt from testing requirements at the project's discretion, but scripts in the project root that are part of the main utility suite MUST have tests.

### IV. Simplicity

Scripts MUST prioritize simplicity and maintainability. Follow YAGNI (You Aren't Gonna Need It) principles. Avoid unnecessary complexity, abstraction, or premature optimization. Scripts MUST be readable and understandable by developers familiar with bash. When complexity is unavoidable, it MUST be justified and documented.

### V. Portability

Scripts MUST work across Unix-like systems (Linux, macOS, BSD). Use POSIX-compliant constructs where possible. When bash-specific features are required, scripts MUST use `#!/usr/bin/env bash` shebang and document the minimum bash version. Avoid system-specific paths or assumptions. Test on multiple platforms when feasible.

## Development Standards

### Bash Best Practices

- Scripts MUST use `set -euo pipefail` for strict error handling. Exceptions for `-u` may be justified when scripts need to check for unset variables using patterns like `${VAR:-default}` or explicit unset checks
- Variables MUST be quoted to prevent word splitting and pathname expansion
- Functions MUST be used for reusable logic
- Scripts MUST include proper cleanup handlers (trap) for error recovery
- Scripts MUST validate inputs and provide clear error messages

### Code Quality

- Scripts MUST pass shellcheck validation
- Scripts MUST follow consistent formatting (use .editorconfig)
- Scripts MUST include usage documentation in help output
- Complex logic MUST be commented for clarity

## Quality Assurance

### Testing Requirements

- All scripts in the project root MUST have corresponding test files in `tests/`
- Scripts in other locations (e.g., `.github/scripts/`, dev tooling) may be exempt from testing at project discretion
- Tests MUST use bats framework (minimum version 1.5.0)
- Tests MUST be independent and idempotent
- Tests MUST clean up after themselves
- Integration tests MUST use isolated test environments

### Continuous Integration

- All tests MUST pass in CI before merging
- Pre-commit hooks MUST validate script syntax and formatting
- Code review MUST verify test coverage and constitution compliance

## Governance

This constitution supersedes all other development practices and guidelines. All pull requests and code reviews MUST verify compliance with these principles.

**Amendment Process**: Amendments to this constitution require:

1. Documentation of the proposed change and rationale
2. Impact analysis on existing scripts and templates
3. Update of dependent templates and documentation
4. Version increment according to semantic versioning

**Versioning Policy**:

- MAJOR: Backward incompatible principle removals or redefinitions
- MINOR: New principle added or materially expanded guidance
- PATCH: Clarifications, wording improvements, typo fixes

**Compliance Review**: All PRs MUST include a constitution check. Violations MUST be justified in the Complexity Tracking section of implementation plans, or the PR MUST be updated to comply.

**Version**: 1.0.1 | **Ratified**: 2025-01-18 | **Last Amended**: 2026-01-18
