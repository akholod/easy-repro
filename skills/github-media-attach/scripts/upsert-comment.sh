#!/usr/bin/env bash
#
# Post a comment on a GitHub issue or pull request — or update the one this
# workflow posted last time, instead of adding another.
#
# Identification is a hidden HTML marker in the body. It stops the COMMENT
# multiplying across re-runs. It does nothing about the UPLOAD: re-uploading the
# same file still makes a second permanent asset, so reuse the URL you already
# have. See ../references/attach.md.
#
# Usage:
#   upsert-comment.sh --number N --body-file FILE [options]
#
# Options:
#   --repo owner/name   target repository (default: inferred by `gh repo view`)
#   --number N          issue or pull request number (a PR is an issue here)
#   --key KEY           marker key, stable per purpose (default: media)
#   --body-file FILE    markdown body; '-' reads stdin
#   --force-new         always post a new comment; never update
#   --dry-run           print what would happen and the resolved body; change nothing
#   -h, --help          this text
#
# Prints the comment's html_url on success.
#
# Exit codes:
#   0  posted or updated
#   1  the GitHub call failed
#   2  the invocation or the environment is wrong; nothing was attempted
#
set -euo pipefail

REPO=""
NUMBER=""
KEY="media"
BODY_FILE=""
FORCE_NEW=0
DRY_RUN=0

die() { printf '%s\n' "$*" >&2; exit 2; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

while [ $# -gt 0 ]; do
  case $1 in
    --repo)       REPO=${2:-}; shift 2 || die "--repo needs a value" ;;
    --number)     NUMBER=${2:-}; shift 2 || die "--number needs a value" ;;
    --key)        KEY=${2:-}; shift 2 || die "--key needs a value" ;;
    --body-file)  BODY_FILE=${2:-}; shift 2 || die "--body-file needs a value" ;;
    --force-new)  FORCE_NEW=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown option: $1" ;;
  esac
done

command -v gh >/dev/null || die "gh is required"
command -v jq >/dev/null || die "jq is required"
[ -n "$NUMBER" ] || die "--number is required"
[ -n "$BODY_FILE" ] || die "--body-file is required"
case $KEY in *[!a-zA-Z0-9._-]*) die "--key must be [a-zA-Z0-9._-]; got: $KEY" ;; esac

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) \
    || die "could not infer the repository. Pass --repo owner/name"
fi

MARKER="<!-- github-media-attach:$KEY -->"

if [ "$BODY_FILE" = "-" ]; then
  BODY=$(cat)
else
  [ -f "$BODY_FILE" ] || die "not a file: $BODY_FILE"
  BODY=$(cat "$BODY_FILE")
fi
[ -n "$BODY" ] || die "the body is empty"

PAYLOAD=$(printf '%s\n\n%s\n' "$MARKER" "$BODY" | jq -Rs '{body:.}')

CID=""
if [ "$FORCE_NEW" -eq 0 ]; then
  # Ordinary comments live under issues/ even for a pull request; pulls/{n}/comments
  # is for inline review comments only.
  #
  # More than one comment can carry the marker — a race, or history from before
  # this was used — and `--jq` is applied to each page separately, so no filter can
  # pick a single winner across pages. Stream every matching id and take the first
  # afterwards, from a variable rather than through a pipe so `head` closing early
  # cannot SIGPIPE gh under `set -o pipefail`.
  IDS=$(gh api --paginate "repos/$REPO/issues/$NUMBER/comments" \
        --jq ".[] | select(.body != null and (.body | contains(\"$MARKER\"))) | .id" \
        2>/dev/null) || die "could not list comments on $REPO#$NUMBER"
  CID=$(printf '%s\n' "$IDS" | head -n1)
fi

if [ "$DRY_RUN" -eq 1 ]; then
  if [ -n "$CID" ]; then
    printf 'would PATCH repos/%s/issues/comments/%s\n' "$REPO" "$CID"
  else
    printf 'would POST repos/%s/issues/%s/comments\n' "$REPO" "$NUMBER"
  fi
  printf -- '--- body ---\n%s\n\n%s\n' "$MARKER" "$BODY"
  exit 0
fi

if [ -n "$CID" ]; then
  printf '%s' "$PAYLOAD" |
    gh api --method PATCH "repos/$REPO/issues/comments/$CID" --input - --jq .html_url
else
  printf '%s' "$PAYLOAD" |
    gh api --method POST "repos/$REPO/issues/$NUMBER/comments" --input - --jq .html_url
fi
