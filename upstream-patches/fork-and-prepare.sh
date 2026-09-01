#!/bin/sh
# fork-and-prepare.sh — Fork ptyxis on GNOME GitLab, apply patches, push
#
# Usage:
#   export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
#   ./fork-and-prepare.sh
#
# What this script does:
#   1. Forks chergert/ptyxis to your GitLab account (if not already forked)
#   2. Clones the fork locally into ./ptyxis-upstream-work/
#   3. Creates branches and applies each patch as a commit
#   4. Pushes branches to your fork

set -e

GITLAB_URL="https://gitlab.gnome.org/api/v4"
UPSTREAM_PROJECT_ID="29370"   # chergert/ptyxis
UPSTREAM_NAMESPACE="chergert"
UPSTREAM_PROJECT="ptyxis"
BASE_BRANCH="main"
WORK_DIR="ptyxis-upstream-work"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

for cmd in curl git python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is required but not found." >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Helper: GitLab API call
# ---------------------------------------------------------------------------
gitlab_api() {
  method="$1"
  endpoint="$2"
  data="$3"

  if [ -n "$data" ]; then
    curl -s \
      --request "$method" \
      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$data" \
      "$GITLAB_URL$endpoint"
  else
    curl -s \
      --request "$method" \
      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "$GITLAB_URL$endpoint"
  fi
}

# ---------------------------------------------------------------------------
# Step 1: Get current user info
# ---------------------------------------------------------------------------
echo "==> Getting your GitLab username..."
USER_INFO=$(gitlab_api GET "/user")
GITLAB_USER=$(printf '%s' "$USER_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin)['username'])")
echo "    Logged in as: $GITLAB_USER"

# ---------------------------------------------------------------------------
# Step 2: Fork the project (idempotent)
# ---------------------------------------------------------------------------
echo ""
echo "==> Checking for existing fork..."
FORK_INFO=$(gitlab_api GET "/projects/$GITLAB_USER%2F$UPSTREAM_PROJECT" 2>/dev/null || echo "null")
FORK_URL=$(printf '%s' "$FORK_INFO" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if isinstance(d, dict) and 'http_url_to_repo' in d:
    print(d['http_url_to_repo'])
" 2>/dev/null || echo "")

if [ -z "$FORK_URL" ]; then
  echo "    Creating fork..."
  FORK_RESULT=$(gitlab_api POST "/projects/$UPSTREAM_PROJECT_ID/fork" \
    "{\"namespace_path\":\"$GITLAB_USER\"}")
  FORK_URL=$(printf '%s' "$FORK_RESULT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('http_url_to_repo',''))
")
  if [ -z "$FORK_URL" ]; then
    echo "ERROR: Failed to create fork." >&2
    printf '%s\n' "$FORK_RESULT" >&2
    exit 1
  fi
  echo "    Fork created. Waiting for GitLab to set it up..."
  sleep 5
else
  echo "    Fork already exists: $FORK_URL"
fi

# Build SSH URL for pushing (avoids password prompt)
FORK_SSH_URL="git@gitlab.gnome.org:$GITLAB_USER/$UPSTREAM_PROJECT.git"
echo "    Fork URL: $FORK_URL"

# ---------------------------------------------------------------------------
# Step 3: Clone the fork
# ---------------------------------------------------------------------------
echo ""
echo "==> Cloning fork into ./$WORK_DIR/ ..."
if [ -d "$WORK_DIR" ]; then
  echo "    Directory exists, using it (will fetch latest)."
  cd "$WORK_DIR"
  git fetch origin
  git checkout "$BASE_BRANCH"
  git reset --hard "origin/$BASE_BRANCH"
  cd ..
else
  git clone "$FORK_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Add upstream remote if not present
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "https://gitlab.gnome.org/$UPSTREAM_NAMESPACE/$UPSTREAM_PROJECT.git"
fi

# Sync with upstream
echo "    Syncing with upstream $BASE_BRANCH..."
git fetch upstream
git checkout "$BASE_BRANCH"
git reset --hard "upstream/$BASE_BRANCH"
git push origin "$BASE_BRANCH" --force-with-lease 2>/dev/null || true

cd ..

# ---------------------------------------------------------------------------
# Step 4: Apply each patch as a branch
# ---------------------------------------------------------------------------
apply_patch_as_branch() {
  branch="$1"
  patchfile="$2"

  echo ""
  echo "==> Applying patch: $patchfile"
  echo "    Branch: $branch"

  cd "$WORK_DIR"

  # Delete branch if it already exists
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "    Branch already exists, recreating..."
    git checkout "$BASE_BRANCH"
    git branch -D "$branch"
  fi

  git checkout -b "$branch"
  git am "$SCRIPT_DIR/$patchfile"
  git push origin "$branch" --force-with-lease

  echo "    Pushed branch $branch to fork."
  cd ..
}

apply_patch_as_branch "fix/no-force-link-glibc-non-linux" "0001-agent-do-not-force-link-glibc-on-non-linux.patch"
apply_patch_as_branch "fix/tab-include-sys-wait"           "0002-tab-include-sys-wait-h-for-wait-macros.patch"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "======================================================"
echo "Done! Branches pushed to your fork:"
echo ""
echo "  fix/zoom-font-scales-typo"
echo "    https://gitlab.gnome.org/$GITLAB_USER/$UPSTREAM_PROJECT/-/tree/fix/zoom-font-scales-typo"
echo ""
echo "  fix/null-deref-path-expand"
echo "    https://gitlab.gnome.org/$GITLAB_USER/$UPSTREAM_PROJECT/-/tree/fix/null-deref-path-expand"
echo ""
echo "Next step:"
echo "  ./create-mr.sh <issue1_number> <issue2_number>"
echo "======================================================"
