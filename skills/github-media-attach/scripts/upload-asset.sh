#!/usr/bin/env bash
#
# Upload a file to GitHub's user-attachments endpoint and print the asset URL.
#
# The endpoint is undocumented. See ../references/upload.md for what has been
# measured and what has not. THE UPLOAD CANNOT BE UNDONE: there is no delete for
# user attachments, so a duplicate run costs a permanent duplicate asset.
#
# Usage:
#   upload-asset.sh [options] <file> [file...]
#
# Options:
#   --repo owner/name     target repository (default: inferred by `gh repo view`)
#   --repository-id N     skip the id lookup and use N
#   --content-type TYPE   override the type for ALL files (default: by extension)
#   --json                one JSON object per file instead of one URL per line
#   --dry-run             print the request that would be sent; send nothing
#   -h, --help            this text
#
# Environment:
#   GH_TOKEN              used if set; otherwise `env -u GITHUB_TOKEN gh auth token`
#   GH_UPLOAD_ORIGIN      override the endpoint origin (for testing)
#
# Exit codes:
#   0  every file uploaded
#   1  a failure whose state is KNOWN — nothing landed. Fix and re-run
#   2  the invocation or the environment is wrong; nothing was attempted
#   5  the state is UNKNOWN. DO NOT RE-RUN: the bytes may have landed
#
set -euo pipefail

ORIGIN=${GH_UPLOAD_ORIGIN:-https://uploads.github.com}
REPO=""
REPO_ID=""
FORCED_TYPE=""
AS_JSON=0
DRY_RUN=0
FILES=()

die() { printf '%s\n' "$*" >&2; exit 2; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

while [ $# -gt 0 ]; do
  case $1 in
    --repo)           REPO=${2:-}; shift 2 || die "--repo needs a value" ;;
    --repository-id)  REPO_ID=${2:-}; shift 2 || die "--repository-id needs a value" ;;
    --content-type)   FORCED_TYPE=${2:-}; shift 2 || die "--content-type needs a value" ;;
    --json)           AS_JSON=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*)               die "unknown option: $1" ;;
    *)                FILES+=("$1"); shift ;;
  esac
done

[ ${#FILES[@]} -gt 0 ] || die "no files given. See --help"
command -v curl >/dev/null || die "curl is required"
command -v jq   >/dev/null || die "jq is required"

# The type must match the extension: the endpoint checks the pair and rejects a
# mismatch with 422. That is why this is a table keyed by extension and not
# `file --mime-type`.
content_type_for() {
  case $(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]') in
    png)        echo image/png ;;
    jpg|jpeg)   echo image/jpeg ;;
    gif)        echo image/gif ;;
    webp)       echo image/webp ;;
    svg)        echo image/svg+xml ;;
    mp4)        echo video/mp4 ;;
    mov)        echo video/quicktime ;;
    webm)       echo video/webm ;;
    *)          echo "" ;;
  esac
}

token() {
  if [ -n "${GH_TOKEN:-}" ]; then
    printf '%s' "$GH_TOKEN"
    return
  fi
  command -v gh >/dev/null || die "no GH_TOKEN and no gh on PATH"
  # `gh auth token` prints $GITHUB_TOKEN verbatim when that variable is set,
  # which silently swaps the identity. Strip it for this call.
  env -u GITHUB_TOKEN gh auth token 2>/dev/null || die "no credential: set GH_TOKEN or run 'gh auth login'"
}

if [ -z "$REPO_ID" ]; then
  command -v gh >/dev/null || die "--repository-id is required when gh is not on PATH"
  if [ -z "$REPO" ]; then
    REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) \
      || die "could not infer the repository. Pass --repo owner/name"
  fi
  # The numeric id, not node_id. Omitting it answers 404 — the same answer as
  # "no access", so a missing id looks exactly like a permissions problem.
  REPO_ID=$(gh api "repos/$REPO" --jq .id 2>/dev/null) \
    || die "could not read repos/$REPO. Check the name and that the token can see it"
fi

worst=0
note_exit() { [ "$1" -gt "$worst" ] && worst=$1 || true; }

for FILE in "${FILES[@]}"; do
  [ -f "$FILE" ] || die "not a file: $FILE"
  NAME=$(basename -- "$FILE")
  SIZE=$(wc -c <"$FILE" | tr -d ' ')
  TYPE=${FORCED_TYPE:-$(content_type_for "$NAME")}
  if [ -z "$TYPE" ]; then
    printf '%s: no content type known for this extension. Pass --content-type\n' "$NAME" >&2
    note_exit 1; continue
  fi
  ENC_NAME=$(jq -rn --arg v "$NAME" '$v|@uri')
  URL="$ORIGIN/user-attachments/assets?repository_id=$REPO_ID&name=$ENC_NAME&size=$SIZE"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'POST %s\n  Authorization: Bearer <token>\n  Content-Type: %s\n  <%s bytes from %s>\n' \
      "$URL" "$TYPE" "$SIZE" "$FILE"
    continue
  fi

  BODY=$(mktemp); trap 'rm -f "$BODY"' EXIT
  # The token goes through a curl config on stdin, not through argv: anything on
  # a command line is visible in `ps` to every user on the machine.
  set +e
  CODE=$(printf 'header = "Authorization: Bearer %s"\n' "$(token)" | curl -sS -K - \
    -X POST -H "Content-Type: $TYPE" --data-binary @"$FILE" \
    -o "$BODY" -w '%{http_code}' "$URL" 2>/dev/null)
  CURL_RC=$?
  set -e

  if [ $CURL_RC -ne 0 ]; then
    # 7 = could not connect, i.e. nothing was sent. Anything else may have sent
    # the body already, and a repeat could create a second permanent asset.
    if [ $CURL_RC -eq 7 ]; then
      printf '%s: could not connect (curl %s). Nothing was sent; safe to retry.\n' "$NAME" "$CURL_RC" >&2
      note_exit 1
    else
      printf '%s: transport failed after the request started (curl %s). STATE UNKNOWN — do not re-run.\n' \
        "$NAME" "$CURL_RC" >&2
      note_exit 5
    fi
    continue
  fi

  case $CODE in
    201)
      ASSET=$(jq -r '.url // empty' <"$BODY")
      if [ -z "$ASSET" ]; then
        printf '%s: 201 with no url in the body. STATE UNKNOWN — do not re-run.\n' "$NAME" >&2
        note_exit 5; continue
      fi
      if [ "$AS_JSON" -eq 1 ]; then
        jq -cn --arg f "$FILE" --arg u "$ASSET" --arg t "$TYPE" \
          '{file:$f, url:$u, contentType:$t, status:201}'
      else
        printf '%s\n' "$ASSET"
      fi
      ;;
    404)
      printf '%s: 404. Indistinguishable between three causes — check all of them:\n' "$NAME" >&2
      printf '  1. repository_id (%s) must be the numeric id, not node_id\n' "$REPO_ID" >&2
      printf '  2. the repository must exist and be visible to this token\n' >&2
      printf '  3. the token needs PUSH access, not just read\n' >&2
      note_exit 1 ;;
    422)
      printf '%s: 422 — the type or the name was refused. Every message:\n' "$NAME" >&2
      jq -r '.errors[]? | "  \(.field // "?"): \(.message // .code // "?")"' <"$BODY" >&2 \
        || sed 's/^/  /' <"$BODY" >&2
      printf '  Nothing landed; fix the extension/type pair and re-run.\n' >&2
      note_exit 1 ;;
    400)
      printf '%s: 400 — the request was malformed (usually a missing Content-Type). Nothing landed.\n' "$NAME" >&2
      note_exit 1 ;;
    *)
      printf '%s: HTTP %s, unclassified. STATE UNKNOWN — do not re-run; a repeat can create a\n' "$NAME" "$CODE" >&2
      printf '  second permanent asset. Report this, with the status, to a person.\n' >&2
      note_exit 5 ;;
  esac
  rm -f "$BODY"; trap - EXIT
done

exit $worst
