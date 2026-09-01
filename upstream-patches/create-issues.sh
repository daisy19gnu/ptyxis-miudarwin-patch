#!/bin/sh
# create-issues.sh — Create Ptyxis upstream bug issues on GNOME GitLab
#
# Usage:
#   export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
#   ./create-issues.sh
#
# Output:
#   Prints the created issue numbers (needed for create-mr.sh)

set -e

GITLAB_URL="https://gitlab.gnome.org/api/v4"
PROJECT_ID="29370"   # chergert/ptyxis

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
  echo "  or save it to ~/.env-ptyxis-upstream" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required but not found." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper: POST to GitLab API
# Returns the issue number on success, exits on failure.
# ---------------------------------------------------------------------------
create_issue() {
  title="$1"
  description="$2"

  response=$(curl -s -w "\n%{http_code}" \
    --request POST \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$(printf '{"title":%s,"description":%s}' \
        "$(printf '%s' "$title"       | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        "$(printf '%s' "$description" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")" \
    "$GITLAB_URL/projects/$PROJECT_ID/issues")

  body=$(printf '%s' "$response" | head -n -1)
  http_code=$(printf '%s' "$response" | tail -n 1)

  if [ "$http_code" != "201" ]; then
    echo "ERROR: GitLab API returned HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
  fi

  printf '%s' "$body" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['iid'])"
}

# ---------------------------------------------------------------------------
# Issue 1: glibc is force-linked on every x86_64 build
# ---------------------------------------------------------------------------
TITLE1="agent: force_link_glibc_2.17.h is included on non-Linux x86_64 targets"
DESC1='## Summary

`agent/meson.build` includes `x86_64/force_link_glibc_2.17.h` whenever the CPU
family is x86_64, without checking which operating system is being targeted.

## Details

```meson
if target_machine.cpu_family() == "x86_64"
  ptyxis_agent_c_args += ["-include", "x86_64/force_link_glibc_2.17.h"]
else
  libc_compat = false
```

The header pins glibc symbol versions. On an x86_64 system that does not use
glibc the agent therefore fails to build.

## Impact

Ptyxis cannot be built on non-glibc x86_64 platforms without a downstream
patch. Two ports carry the same fix independently:

- MIU Darwin
- MIU Darwin (a Darwin/XNU distribution with its own C library)

## Fix

```diff
-if target_machine.cpu_family() == "x86_64"
+if target_machine.cpu_family() == "x86_64" and host_machine.system() == "linux"
```

`host_machine` rather than `target_machine`: in meson, `target_machine` only
carries a meaning when the artefact being built is itself a compiler. For an
application the machine the code runs on is `host_machine`. The two are
identical for a native build, so this is a no-op there, but they genuinely
differ under cross compilation.

## Affected versions

Confirmed in 49.3 and 50.1.'

# ---------------------------------------------------------------------------
# Issue 2: missing <sys/wait.h>
# ---------------------------------------------------------------------------
TITLE2="tab: src/ptyxis-tab.c uses wait status macros without including <sys/wait.h>"
DESC2='## Summary

`src/ptyxis-tab.c` uses `WIFEXITED`, `WEXITSTATUS`, `WIFSIGNALED` and
`WTERMSIG` but never includes `<sys/wait.h>`.

## Details

POSIX places those macros in `<sys/wait.h>`. The file compiles on glibc only
because another header happens to pull it in. On systems whose headers follow
the POSIX placement more strictly, compilation fails.

## Impact

Ptyxis cannot be built without a downstream patch on such systems. Two ports
carry the same fix independently:

- MIU Darwin
- MIU Darwin (a Darwin/XNU distribution with its own C library)

Two ports hitting the same omission independently suggests the include is
genuinely missing rather than either system being unusual.

## Fix

```diff
 #include <cairo.h>
+#include <sys/wait.h>
```

The include is harmless where the macros already arrive by another route.

## Affected versions

Confirmed in 49.3 and 50.1.'

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Create the issues
# ---------------------------------------------------------------------------
echo "Creating Issue 1: $TITLE1"
ISSUE1=$(create_issue "$TITLE1" "$DESC1")
echo "  -> Created issue #$ISSUE1"
echo "     https://gitlab.gnome.org/chergert/ptyxis/-/issues/$ISSUE1"
echo ""

echo "Creating Issue 2: $TITLE2"
ISSUE2=$(create_issue "$TITLE2" "$DESC2")
echo "  -> Created issue #$ISSUE2"
echo "     https://gitlab.gnome.org/chergert/ptyxis/-/issues/$ISSUE2"
echo ""

echo "Done. Issue numbers for create-mr.sh:"
echo "  ./create-mr.sh $ISSUE1 $ISSUE2"
