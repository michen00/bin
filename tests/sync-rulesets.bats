#!/usr/bin/env bats

load 'test_helper'

# A failing [[ ]] that is not the last command of a test does not fail the
# test under bash 3.2, so each [[ ]] check below ends with "|| false".

# The pull_request parameters of a rule that matches the baseline, with keys
# outside the baseline that the script must leave as they are.
MATCHING='{"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true,"require_last_push_approval":true,"required_review_thread_resolution":true,"require_code_owner_review":true,"allowed_merge_methods":["squash"],"required_reviewers":[]}'

# The same rule with three baseline parameters that differ: one with another
# value, one false and one unset.
DIFFERING='{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":true,"require_last_push_approval":false,"require_code_owner_review":true,"allowed_merge_methods":["squash"],"required_reviewers":[]}'

BASELINE_JSON='{"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true,"require_last_push_approval":true,"required_review_thread_resolution":true}'

# Stub gh so that sync-rulesets runs without the network. The stub answers
# "gh api ENDPOINT" with the file $GH_STUB_DIR/KEY, where KEY is the endpoint
# path without its query string and with each / replaced by __, and records
# every call it receives, one per line, in $GH_STUB_DIR/calls. A file
# KEY.fail makes that call fail with the file's contents on stderr. A PUT
# fails if KEY.put-fail exists; otherwise it saves its body in KEY.put and
# merges the body into KEY, as GitHub stores an update, or, if KEY.readback
# exists, replaces KEY with it to simulate GitHub storing something else.
stub_gh() {
	GH_STUB_DIR="$TEST_TEMP_DIR/gh-stub"
	export GH_STUB_DIR
	mkdir -p "$GH_STUB_DIR" "$TEST_TEMP_DIR/stubs"
	cat >"$TEST_TEMP_DIR/stubs/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$GH_STUB_DIR/calls"
case "$1" in
auth)
	if [[ -e $GH_STUB_DIR/auth.fail ]]; then
		echo "You are not logged into any GitHub hosts. To log in, run: gh auth login" >&2
		exit 1
	fi
	exit 0
	;;
api) shift ;;
*)
	echo "gh stub: unexpected command: $*" >&2
	exit 64
	;;
esac
method=GET
input=""
endpoint=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--method) method=$2 && shift 2 ;;
	--input) input=$2 && shift 2 ;;
	--paginate) shift ;;
	-f | -F) shift 2 ;;
	*) endpoint=$1 && shift ;;
	esac
done
path=${endpoint%%\?*}
key="$GH_STUB_DIR/${path//\//__}"
if [[ $method == PUT ]]; then
	if [[ -e $key.put-fail ]]; then
		echo "gh: Validation Failed (HTTP 422)" >&2
		exit 1
	fi
	if [[ $input == - ]]; then cat >"$key.put"; else cat "$input" >"$key.put"; fi
	if [[ -e $key.readback ]]; then
		cp "$key.readback" "$key"
	else
		jq -s '.[0] + .[1]' "$key" "$key.put" >"$key.new"
		mv "$key.new" "$key"
	fi
	cat "$key"
	exit 0
fi
if [[ -e $key.fail ]]; then
	cat "$key.fail" >&2
	exit 1
fi
if [[ ! -e $key ]]; then
	echo "gh: Not Found (HTTP 404)" >&2
	exit 1
fi
cat "$key"
EOF
	chmod +x "$TEST_TEMP_DIR/stubs/gh"
	export PATH="$TEST_TEMP_DIR/stubs:$PATH"
}

# Helper to turn an endpoint path into the stub's file for it
# Parameters:
#   $1 - endpoint path, such as repos/octo/bin/rulesets
stub_file() {
	local path=$1
	echo "$GH_STUB_DIR/${path//\//__}"
}

# Helper to serve stdin as the response to a GET of an endpoint
# Parameters:
#   $1 - endpoint path
serve() {
	cat >"$(stub_file "$1")"
}

# Helper to make every call to an endpoint fail
# Parameters:
#   $1 - endpoint path
#   $2 - message that gh prints on stderr
fail_endpoint() {
	printf '%s\n' "$2" >"$(stub_file "$1").fail"
}

# Helper to print a ruleset as GitHub returns it, with a deletion rule, a
# pull_request rule and a required_status_checks rule, and with the fields
# that a GET returns but an update does not take (id, source_type,
# updated_at)
# Parameters:
#   $1 - ruleset id
#   $2 - ruleset name
#   $3 - parameters of the pull_request rule, as JSON
#   $4 - target (default: branch)
ruleset() {
	jq -cn --argjson id "$1" --arg name "$2" --argjson params "$3" --arg target "${4:-branch}" '{
		id: $id, name: $name, target: $target, source_type: "Repository",
		enforcement: "active",
		conditions: {ref_name: {exclude: [], include: ["~DEFAULT_BRANCH"]}},
		bypass_actors: [{actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "always"}],
		rules: [
			{type: "deletion"},
			{type: "pull_request", parameters: $params},
			{type: "required_status_checks", parameters: {
				strict_required_status_checks_policy: true,
				required_status_checks: [{context: "CI", integration_id: 15368}]}}
		],
		updated_at: "2026-10-25T00:00:00Z"
	}'
}

# Helper to serve the authenticated user "octo" and one page of the
# repositories that octo owns
# Parameters:
#   $@ - repository names
serve_account() {
	echo '{"login":"octo"}' | serve user
	jq -cn '{data: {repositoryOwner: {repositories: {
		nodes: [$ARGS.positional[] | {name: .}],
		pageInfo: {hasNextPage: false, endCursor: null}}}}}' --args "$@" | serve graphql
}

# Helper to serve a repository of octo: its rulesets list, and each ruleset
# Parameters:
#   $1 - repository name
#   $@ - (after $1) rulesets, as JSON from ruleset()
serve_repo() {
	local repo=$1 rs id
	shift
	printf '%s\n' "$@" | jq -cs 'map(select(. != null) | {id, name, target})' |
		serve "repos/octo/$repo/rulesets"
	for rs in "$@"; do
		id=$(jq -r .id <<<"$rs")
		printf '%s\n' "$rs" | serve "repos/octo/$repo/rulesets/$id"
	done
}

@test "sync-rulesets: script has valid bash syntax" {
	bash -n "$SCRIPTS_DIR/sync-rulesets"
}

@test "sync-rulesets: -h displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" -h
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Usage: sync-rulesets [--apply] [--owner OWNER] [--] [REPO ...]" ]
	[ -z "$stderr" ]
}

@test "sync-rulesets: --help displays usage information on stdout" {
	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --help
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
	assert_output_contains "--apply"
	assert_output_contains "--owner OWNER"
	[ -z "$stderr" ]
}

@test "sync-rulesets: --help lists sections in order with -h, --help last" {
	run "$SCRIPTS_DIR/sync-rulesets" --help
	[ "$status" -eq 0 ]
	[[ "$output" == "Usage: sync-rulesets "*"Arguments:"*"Options:"*"Examples:"*"Baseline"*"Exit Codes:"* ]] || false
	[[ "$output" == *"  -h, --help     Show this help message and exit."$'\n\n'"Examples:"* ]] || false
}

@test "sync-rulesets: --help prints the baseline and the exit codes" {
	run "$SCRIPTS_DIR/sync-rulesets" --help
	[ "$status" -eq 0 ]
	assert_output_contains '    "required_approving_review_count": 1,'
	assert_output_contains '    "dismiss_stale_reviews_on_push": true,'
	assert_output_contains '    "require_last_push_approval": true,'
	assert_output_contains '    "required_review_thread_resolution": true'
	assert_output_contains "  3  A dry run found rulesets that differ from the baseline."
}

@test "sync-rulesets: -h works when gh and jq are not installed" {
	# usage prints the help with cat, so cat must stay available.
	run --separate-stderr env PATH="$(restricted_path bash basename cat)" "$SCRIPTS_DIR/sync-rulesets" -h
	[ "$status" -eq 0 ]
	assert_output_contains "Usage:"
}

@test "sync-rulesets: fails with exit 2 on unknown option" {
	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --bogus
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Unknown option '--bogus'"* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "sync-rulesets: fails with exit 2 when --owner has no value" {
	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --owner
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"Error: Option '--owner' requires a value."* ]] || false
	[[ "$stderr" == *"Usage:"* ]] || false
	[ -z "$output" ]
}

@test "sync-rulesets: fails with exit 1 when the owner is empty" {
	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --owner ''
	[ "$status" -eq 1 ]
	[ "$stderr" = "Error: The owner is empty." ]
	[ -z "$output" ]
}

@test "sync-rulesets: fails with exit 1 when a repository includes its owner" {
	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" octo/bin
	[ "$status" -eq 1 ]
	[[ "$stderr" == "Error: Invalid repository 'octo/bin'; give the name alone and set its owner with --owner." ]] || false
	[ -z "$output" ]
}

@test "sync-rulesets: fails when gh is not installed" {
	run --separate-stderr env PATH="$(restricted_path bash basename)" "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: 'gh' (GitHub CLI) is required but not installed."* ]] || false
	[[ "$stderr" == *"https://cli.github.com/"* ]] || false
	[ -z "$output" ]
}

@test "sync-rulesets: fails when jq is not installed" {
	stub_gh

	run --separate-stderr env PATH="$(restricted_path bash basename gh)" "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: 'jq' is required but not installed."* ]] || false
	[ -z "$output" ]
}

@test "sync-rulesets: fails when gh is not authenticated" {
	stub_gh
	touch "$GH_STUB_DIR/auth.fail"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"You are not logged into any GitHub hosts."* ]] || false
	[[ "$stderr" == *"Error: gh is not authenticated. Run 'gh auth login' first."* ]] || false
	[ -z "$output" ]
	[[ "$(cat "$GH_STUB_DIR/calls")" != *"api"* ]] || false
}

@test "sync-rulesets: a ruleset that matches the baseline is reported as such and exits 0" {
	stub_gh
	serve_account bin
	serve_repo bin "$(ruleset 11 main-protect "$MATCHING")"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 0 ]
	assert_output_contains "Dry run over the rulesets of 'octo' (repositories: 1); nothing is changed"
	assert_output_contains "bin/main-protect (11): matches baseline"
	assert_output_contains "rulesets with a pull_request rule: 1 (matching the baseline: 1; would change: 0)."
	assert_output_not_contains "→"
	[ -z "$stderr" ]
}

@test "sync-rulesets: a dry run over a ruleset that differs reports old → new and exits 3" {
	stub_gh
	serve_account bin
	serve_repo bin "$(ruleset 11 main-protect "$DIFFERING")"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 3 ]
	assert_output_contains "bin/main-protect (11): would change"
	assert_output_contains "  required_approving_review_count: 0 → 1"
	assert_output_contains "  require_last_push_approval: false → true"
	assert_output_contains "  required_review_thread_resolution: unset → true"
	assert_output_not_contains "dismiss_stale_reviews_on_push:"
	assert_output_contains "(matching the baseline: 0; would change: 1)"
	[ -z "$stderr" ]
}

@test "sync-rulesets: a dry run sends no update" {
	stub_gh
	serve_account bin
	serve_repo bin "$(ruleset 11 main-protect "$DIFFERING")"

	run "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 3 ]
	[[ "$(cat "$GH_STUB_DIR/calls")" != *"PUT"* ]] || false
	[ ! -e "$(stub_file repos/octo/bin/rulesets/11).put" ]
}

@test "sync-rulesets: --apply sets only the baseline keys and leaves other keys and rules untouched" {
	stub_gh
	serve_account bin
	local original
	original=$(ruleset 11 main-protect "$DIFFERING")
	serve_repo bin "$original"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --apply
	[ "$status" -eq 0 ]
	assert_output_contains "bin/main-protect (11): updated and confirmed"
	assert_output_contains "  require_last_push_approval: false → true"
	[ -z "$stderr" ]

	local sent
	sent=$(cat "$(stub_file repos/octo/bin/rulesets/11).put")
	# The body is the ruleset as read, without the fields an update does
	# not take, and with the baseline merged into the pull_request rule.
	[ "$(jq -n --argjson orig "$original" --argjson sent "$sent" --argjson baseline "$BASELINE_JSON" '
		($orig | {name, target, enforcement, conditions, bypass_actors, rules}
			| .rules[1].parameters += $baseline) == $sent')" = true ]
	# The same, spelled out for the keys that the baseline must not touch.
	[ "$(jq -c '.rules[1].parameters.require_code_owner_review' <<<"$sent")" = true ]
	[ "$(jq -c '.rules[1].parameters.allowed_merge_methods' <<<"$sent")" = '["squash"]' ]
	[ "$(jq -c '.rules[0]' <<<"$sent")" = "$(jq -c '.rules[0]' <<<"$original")" ]
	[ "$(jq -c '.rules[2]' <<<"$sent")" = "$(jq -c '.rules[2]' <<<"$original")" ]
	[ "$(jq -c '.bypass_actors' <<<"$sent")" = "$(jq -c '.bypass_actors' <<<"$original")" ]
	[ "$(jq -c 'has("id") or has("updated_at") or has("source_type")' <<<"$sent")" = false ]
}

@test "sync-rulesets: --apply reads each updated ruleset back" {
	stub_gh
	serve_account bin
	serve_repo bin "$(ruleset 11 main-protect "$DIFFERING")"

	run "$SCRIPTS_DIR/sync-rulesets" --apply
	[ "$status" -eq 0 ]
	run grep -n "repos/octo/bin/rulesets/11" "$GH_STUB_DIR/calls"
	[ "${#lines[@]}" -eq 3 ]
	[[ "${lines[1]}" == *"--method PUT"* ]] || false
	[[ "${lines[2]}" != *"PUT"* ]] || false
}

@test "sync-rulesets: --apply does not update a ruleset that matches the baseline" {
	stub_gh
	serve_account bin
	serve_repo bin "$(ruleset 11 main-protect "$MATCHING")"

	run "$SCRIPTS_DIR/sync-rulesets" --apply
	[ "$status" -eq 0 ]
	assert_output_contains "bin/main-protect (11): matches baseline"
	[[ "$(cat "$GH_STUB_DIR/calls")" != *"PUT"* ]] || false
}

@test "sync-rulesets: --apply fails when the read-back shows another difference" {
	stub_gh
	serve_account bin
	serve_repo bin "$(ruleset 11 main-protect "$DIFFERING")"
	# GitHub stores the baseline, but also changes allowed_merge_methods.
	ruleset 11 main-protect "$(jq -c '. + $b + {allowed_merge_methods: ["merge"]}' --argjson b "$BASELINE_JSON" <<<"$DIFFERING")" |
		serve repos/octo/bin/rulesets/11.readback

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --apply
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: The read-back of bin/main-protect (11) differs from the update sent, beyond the baseline."* ]] || false
	[[ "$stderr" == *"https://github.com/octo/bin/rules/11"* ]] || false
	[[ "$stderr" == *'<           "squash"'* ]] || false
	[[ "$stderr" == *'>           "merge"'* ]] || false
	assert_output_not_contains "updated and confirmed"
}

@test "sync-rulesets: --apply fails and stops when an update fails" {
	stub_gh
	serve_account bin ctrl-f
	serve_repo bin "$(ruleset 11 main-protect "$DIFFERING")"
	serve_repo ctrl-f "$(ruleset 22 main-protect "$DIFFERING")"
	touch "$(stub_file repos/octo/bin/rulesets/11).put-fail"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --apply
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"gh: Validation Failed (HTTP 422)"* ]] || false
	[[ "$stderr" == *"Error: Failed to update bin/main-protect (11). Check it at https://github.com/octo/bin/rules/11."* ]] || false
	[[ "$(cat "$GH_STUB_DIR/calls")" != *"repos/octo/ctrl-f"* ]] || false
}

@test "sync-rulesets: a failed rulesets list fails the run instead of reading as no rulesets" {
	stub_gh
	serve_account bin
	fail_endpoint repos/octo/bin/rulesets "gh: Server Error (HTTP 500)"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"gh: Server Error (HTTP 500)"* ]] || false
	[[ "$stderr" == *"Error: Failed to list the rulesets of 'octo/bin'."* ]] || false
	assert_output_not_contains "no review rule"
}

@test "sync-rulesets: a failed ruleset read fails the run" {
	stub_gh
	serve_account bin
	serve_repo bin "$(ruleset 11 main-protect "$MATCHING")"
	fail_endpoint repos/octo/bin/rulesets/11 "gh: Forbidden (HTTP 403)"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to read ruleset 11 of 'octo/bin'."* ]] || false
	assert_output_not_contains "no review rule"
}

@test "sync-rulesets: a failed repository list fails the run" {
	stub_gh
	serve_account bin
	fail_endpoint graphql "gh: Something went wrong"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to list the repositories of 'octo'."* ]] || false
	[ -z "$output" ]
}

@test "sync-rulesets: a failed lookup of the authenticated user fails the run" {
	stub_gh
	fail_endpoint user "gh: Bad credentials (HTTP 401)"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to read the authenticated user from GitHub. Pass --owner OWNER."* ]] || false
	[ -z "$output" ]
}

@test "sync-rulesets: an owner that does not exist fails the run" {
	stub_gh
	echo '{"data":{"repositoryOwner":null}}' | serve graphql

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --owner nobody
	[ "$status" -eq 1 ]
	[ "$stderr" = "Error: GitHub has no user or organization named 'nobody'." ]
	[ -z "$output" ]
}

@test "sync-rulesets: reads every page of the repository list" {
	stub_gh
	echo '{"login":"octo"}' | serve user
	{
		echo '{"data":{"repositoryOwner":{"repositories":{"nodes":[{"name":"zeta"}],"pageInfo":{"hasNextPage":true,"endCursor":"c1"}}}}}'
		echo '{"data":{"repositoryOwner":{"repositories":{"nodes":[{"name":"alpha"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}'
	} | serve graphql
	serve_repo alpha "$(ruleset 1 main-protect "$MATCHING")"
	serve_repo zeta "$(ruleset 2 main-protect "$MATCHING")"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "alpha/main-protect (1): matches baseline" ]
	[ "${lines[2]}" = "zeta/main-protect (2): matches baseline" ]
	grep -q "^api graphql --paginate " "$GH_STUB_DIR/calls"
}

@test "sync-rulesets: reads every page of a rulesets list" {
	stub_gh
	serve_account bin
	ruleset 11 main-protect "$MATCHING" | serve repos/octo/bin/rulesets/11
	ruleset 12 require-review "$DIFFERING" | serve repos/octo/bin/rulesets/12
	{
		echo '[{"id":11,"name":"main-protect","target":"branch"}]'
		echo '[{"id":12,"name":"require-review","target":"branch"}]'
	} | serve repos/octo/bin/rulesets

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 3 ]
	assert_output_contains "bin/main-protect (11): matches baseline"
	assert_output_contains "bin/require-review (12): would change"
	grep -q "^api --paginate repos/octo/bin/rulesets?" "$GH_STUB_DIR/calls"
}

@test "sync-rulesets: reports a repository without a branch review rule and creates none" {
	stub_gh
	serve_account bare tags-only checks-only
	serve_repo bare
	serve_repo tags-only "$(ruleset 31 tags-protect "$DIFFERING" tag)"
	serve_repo checks-only "$(jq -c '.rules |= map(select(.type != "pull_request"))' <<<"$(ruleset 41 main-protect "$MATCHING")")"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --apply
	[ "$status" -eq 0 ]
	assert_output_contains "bare: no review rule (not created; required checks are per-repo)"
	assert_output_contains "tags-only: no review rule (not created; required checks are per-repo)"
	assert_output_contains "checks-only: no review rule (not created; required checks are per-repo)"
	assert_output_contains "rulesets with a pull_request rule: 0 (matching the baseline: 0; updated: 0). Repositories with no review rule: 3."
	[[ "$(cat "$GH_STUB_DIR/calls")" != *"--method"* ]] || false
	# A tag ruleset is not read past the list.
	[[ "$(cat "$GH_STUB_DIR/calls")" != *"rulesets/31"* ]] || false
}

@test "sync-rulesets: checks only the named repositories of --owner" {
	stub_gh
	printf '%s\n' '[{"id":11,"name":"main-protect","target":"branch"}]' | serve repos/acme/web/rulesets
	ruleset 11 main-protect "$MATCHING" | serve repos/acme/web/rulesets/11

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" --owner acme web
	[ "$status" -eq 0 ]
	assert_output_contains "Dry run over the rulesets of 'acme' (repositories: 1)"
	assert_output_contains "web/main-protect (11): matches baseline"
	[[ "$(cat "$GH_STUB_DIR/calls")" != *"api user"* ]] || false
	[[ "$(cat "$GH_STUB_DIR/calls")" != *"graphql"* ]] || false
}

@test "sync-rulesets: treats arguments after -- as repositories" {
	stub_gh
	serve_account

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets" -- --apply
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Error: Failed to list the rulesets of 'octo/--apply'."* ]] || false
	assert_output_contains "Dry run"
}

@test "sync-rulesets: reports settings outside the baseline that differ between rulesets" {
	stub_gh
	serve_account bin ctrl-f freeze-pr-links
	local all_methods squash_only linear
	all_methods=$(jq -c '.allowed_merge_methods = ["merge","squash","rebase"]' <<<"$MATCHING")
	squash_only=$(jq -c '.allowed_merge_methods = ["squash"]' <<<"$MATCHING")
	linear=$(jq -c '.rules += [{type: "required_linear_history"}]' <<<"$(ruleset 31 main-protect "$squash_only")")
	serve_repo bin "$(ruleset 11 main-protect "$all_methods")" "$(ruleset 12 require-review "$all_methods")"
	serve_repo ctrl-f "$(ruleset 21 main-protect "$all_methods")"
	serve_repo freeze-pr-links "$linear"

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 0 ]
	assert_output_contains "Settings that differ between the 4 branch rulesets read (not changed):"
	assert_output_contains "  pull_request allowed_merge_methods:"
	assert_output_contains '    ["merge","squash","rebase"]: bin/main-protect, bin/require-review, ctrl-f'
	assert_output_contains '    ["squash"]: freeze-pr-links'
	assert_output_contains "    required_linear_history: in 1 of 4: freeze-pr-links"
	# Settings that are the same everywhere are not reported.
	assert_output_not_contains "require_code_owner_review"
	assert_output_not_contains "    deletion:"
}

@test "sync-rulesets: reports none when the rulesets agree" {
	stub_gh
	serve_account bin ctrl-f
	serve_repo bin "$(ruleset 11 main-protect "$MATCHING")"
	serve_repo ctrl-f "$(ruleset 21 main-protect "$MATCHING")"

	run "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 0 ]
	[ "${lines[${#lines[@]} - 1]}" = "  none" ]
}

@test "sync-rulesets: marks a ruleset that is not active" {
	stub_gh
	serve_account bin
	serve_repo bin "$(jq -c '.enforcement = "evaluate"' <<<"$(ruleset 11 main-protect "$MATCHING")")"

	run "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 0 ]
	assert_output_contains "bin/main-protect (11) [enforcement: evaluate]: matches baseline"
}

@test "sync-rulesets: exits 0 when the owner has no repositories" {
	stub_gh
	serve_account

	run --separate-stderr "$SCRIPTS_DIR/sync-rulesets"
	[ "$status" -eq 0 ]
	[ "$output" = "No repositories of 'octo' to check." ]
	[ -z "$stderr" ]
}
