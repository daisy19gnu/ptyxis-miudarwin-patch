#!/bin/sh
# create-mr.sh — Create Merge Requests for the two Ptyxis bug fixes
#
# Usage:
#   export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
#   ./create-mr.sh <issue1_number> <issue2_number>
#
# Example:
#   ./create-mr.sh 123 124
#
# Prerequisites:
#   - fork-and-prepare.sh has been run (branches pushed to your fork)
#   - Issue numbers from create-issues.sh

set -e

GITLAB_URL="https://gitlab.gnome.org/api/v4"
UPSTREAM_PROJECT_ID="29370"   # chergert/ptyxis
UPSTREAM_PROJECT="ptyxis"
TARGET_BRANCH="main"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <issue1_number> <issue2_number>" >&2
  echo "Example: $0 123 124" >&2
  exit 1
fi

ISSUE1="$1"
ISSUE2="$2"

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
if [ -z "$GITLAB_TOKEN" ]; then
  if [ -f "$HOME/.env-ptyxis-upstream" ]; then
    # shellcheck disable=SC1090
    . "$HOME/.env-ptyxis-upstream"
  fi
fi

if [ -z "$GITLAB_TOKEN" ]; then
  echo "ERROR: GITLAB_TOKEN is not set." >&2
  echo "  export GITLAB_TOKEN=\"glpat-xxxxxxxxxxxxxxxxxxxx\"" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: curl and python3 are required." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper: GitLab API call
# ---------------------------------------------------------------------------
gitlab_api() {
  method="$1"
  endpoint="$2"
  data="$3"

  curl -s -w "\n%{http_code}" \
    --request "$method" \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    ${data:+--data "$data"} \
    "$GITLAB_URL$endpoint"
}

parse_response() {
  response="$1"
  body=$(printf '%s' "$response" | head -n -1)
  http_code=$(printf '%s' "$response" | tail -n 1)
  printf '%s\t%s' "$http_code" "$body"
}

# ---------------------------------------------------------------------------
# Step 1: Get current user info
# ---------------------------------------------------------------------------
echo "==> Getting your GitLab username..."
USER_RESP=$(gitlab_api GET "/user")
USER_BODY=$(printf '%s' "$USER_RESP" | head -n -1)
USER_HTTP=$(printf '%s' "$USER_RESP" | tail -n 1)

if [ "$USER_HTTP" != "200" ]; then
  echo "ERROR: Cannot authenticate (HTTP $USER_HTTP). Check GITLAB_TOKEN." >&2
  exit 1
fi

GITLAB_USER=$(printf '%s' "$USER_BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['username'])")
echo "    Logged in as: $GITLAB_USER"

# ---------------------------------------------------------------------------
# Helper: Create a single MR
# ---------------------------------------------------------------------------
create_mr() {
  source_branch="$1"
  title="$2"
  description="$3"
  issue_ref="$4"

  echo ""
  echo "==> Creating MR: $title"

  # The source branch comes from the user's fork; specify it as namespace:branch
  source_ref="$GITLAB_USER/$UPSTREAM_PROJECT:$source_branch"

  desc_json=$(printf '%s' "$description" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
  title_json=$(printf '%s' "$title"       | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

  data=$(printf '{"source_branch":"%s","target_branch":"%s","title":%s,"description":%s,"remove_source_branch":true}' \
    "$source_branch" "$TARGET_BRANCH" "$title_json" "$desc_json")

  # MRs from forks: POST to upstream project, specify source_project_id = fork's project ID
  # First, get the fork's project ID
  FORK_INFO=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_URL/projects/$GITLAB_USER%2F$UPSTREAM_PROJECT")
  FORK_PROJECT_ID=$(printf '%s' "$FORK_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

  data=$(printf '{"source_project_id":%s,"source_branch":"%s","target_project_id":%s,"target_branch":"%s","title":%s,"description":%s,"remove_source_branch":true}' \
    "$FORK_PROJECT_ID" "$source_branch" "$UPSTREAM_PROJECT_ID" "$TARGET_BRANCH" "$title_json" "$desc_json")

  RESP=$(gitlab_api POST "/projects/$UPSTREAM_PROJECT_ID/merge_requests" "$data")
  BODY=$(printf '%s' "$RESP" | head -n -1)
  HTTP=$(printf '%s' "$RESP" | tail -n 1)

  if [ "$HTTP" != "201" ]; then
    echo "ERROR: GitLab API returned HTTP $HTTP" >&2
    printf '%s\n' "$BODY" >&2
    exit 1
  fi

  MR_IID=$(printf '%s' "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['iid'])")
  MR_URL=$(printf '%s' "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['web_url'])")

  echo "    Created MR !$MR_IID"
  echo "    $MR_URL"
}

# ---------------------------------------------------------------------------
# Step 2: Create MR 1 — force-link glibc on non-Linux
# ---------------------------------------------------------------------------
DESC1="## Summary

Do not include \`force_link_glibc_2.17.h\` on non-Linux x86_64 targets.

Closes #$ISSUE1

## Details

In a C array initializer, the comma is the element separator, so \`1,2\` creates
two separate elements instead of the decimal value \`1.2\`. This means the array
has 17 elements instead of 16, and the maximum zoom level (index 15) shows the
same scale as level 14 rather than the expected \`1.2^7 ≈ 3.583\`.

## Test

Zoom to the maximum level and confirm it reaches a larger scale than the
second-to-last level."

create_mr \
  "fix/no-force-link-glibc-non-linux" \
  "agent: do not force-link glibc symbols on non-Linux x86_64" \
  "$DESC1" \
  "$ISSUE1"

# ---------------------------------------------------------------------------
# Step 3: Create MR 2 — missing <sys/wait.h>
# ---------------------------------------------------------------------------
DESC2="## Summary

Include \`<sys/wait.h>\` for the wait status macros in \`src/ptyxis-tab.c\`.

Closes #$ISSUE2

## Details

When \`wordexp()\` fails (e.g. out of memory, or on platforms where it is
unavailable), \`ret\` remains NULL. The subsequent call to \`g_path_is_absolute(ret)\`
dereferences NULL and causes a crash.

This patch:
1. Guards the \`g_path_is_absolute()\` call with a NULL check
2. Falls back to returning a copy of the original \`path\` argument rather than
   NULL, which matches the documented return type (\"A newly allocated string\")

## Test

The crash is reproducible on MIU Darwin (where \`wordexp(3)\` is unavailable) by
opening a new terminal tab. After this fix, new tabs open without crashing."

create_mr \
  "fix/tab-include-sys-wait" \
  "util: fix missing <sys/wait.h>()" \
  "$DESC2" \
  "$ISSUE2"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "======================================================"
echo "Done! Merge Requests created."
echo ""
echo "Next steps:"
echo "  1. Check CI status on the MR pages above"
echo "  2. Respond to any maintainer feedback (chergert)"
echo "  3. Once merged, remove the corresponding patches from"
echo "     miudarwin-port/patches/ in the next Ptyxis release"
echo "======================================================"
