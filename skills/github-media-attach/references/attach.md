# Placing the markdown

Once an asset URL exists, everything downstream is the same problem in four costumes. Keep the model
in mind and the special cases disappear:

```
asset URL  →  markdown fragment  →  a body  →  one placement command
```

The fragment does not care whether the change is a bug, a feature or a fix. The body does not care
whether it will become an issue, a PR description or a comment. **Only the last arrow differs.**

## The fragment

| Kind | Write | Why |
| --- | --- | --- |
| Image | `![what it shows](URL)` | standard markdown; the alt text is read aloud and shown when the render fails |
| Image, sized | `<img src="URL" width="600">` | GitHub honours `width` on `img`; markdown syntax has no size |
| Video | the bare URL **on its own line**, nothing around it | this is what GitHub's web UI writes for video, and it is what makes the player appear |

```markdown
The dropdown now stays open while the filter is being typed:

![filter dropdown staying open while typing](https://github.com/user-attachments/assets/0000…)
```

```markdown
Checkout flow, end to end:

https://github.com/user-attachments/assets/0000…
```

Wrapping a video URL in `![]()` is the usual way to get a broken-image icon. Leave it bare, on its
own line, with a blank line before and after.

Provenance, since it matters: the bare-URL form is what GitHub's own web UI produces when a video is
dropped into a comment box. It was **not** verified by the probe behind
[upload.md](upload.md) — verifying it would have cost a permanent video attachment. Treat it as
well-founded convention rather than measured fact, and if the player does not appear, read the posted
body back before concluding the upload was at fault.

Alt text is not optional decoration — write what the frame *shows*, not the file name.

### Several artifacts in one body

```markdown
| Before | After |
| --- | --- |
| <img src="URL_BEFORE" width="380"> | <img src="URL_AFTER" width="380"> |
```

```markdown
<details>
<summary>Three more states (empty, loading, error)</summary>

![empty state](URL1)
![loading state](URL2)
![error state](URL3)

</details>
```

The blank lines inside `<details>` are required, or the markdown inside is not parsed.

Collapse anything past the first artifact. One visible image and a fold beats five images that push
the description off the screen.

## Resolving the target

```bash
R=$(gh repo view --json nameWithOwner --jq .nameWithOwner)   # from the git remote of THIS directory
N=$(gh pr view --json number --jq .number)                   # the PR for the current branch, if any
```

`gh repo view` infers from the remote of the directory you are standing in. **If the repository it
names back is not the one you meant, the working directory is wrong** — do not paper over it with
`--repo`; an upload into the wrong repository is as permanent as any other.

`gh pr view` fails when the branch has no open PR. That is an answer, not an error to route around:
**never open a pull request or an issue just to have somewhere to put a screenshot.** Ask which
existing target to use, or attach nothing.

## The placement commands

Write the body to a file first. `--body-file` — never `--body "$(cat …)"`, which breaks on quotes,
backticks and newlines and puts the whole text in the process list.

| Where it goes | Command |
| --- | --- |
| New issue | `gh issue create --repo "$R" --title "…" --body-file body.md` |
| New PR | `gh pr create --repo "$R" --title "…" --body-file body.md` |
| Comment on an issue | `gh issue comment "$N" --repo "$R" --body-file body.md` |
| Comment on a PR | `gh pr comment "$N" --repo "$R" --body-file body.md` |
| Replace an issue body | `gh issue edit "$N" --repo "$R" --body-file body.md` |
| Replace a PR body | `gh pr edit "$N" --repo "$R" --body-file body.md` |
| Review summary on a PR | `gh pr review "$N" --repo "$R" --comment --body-file body.md` |

Read the file back from stdin when the body is generated rather than stored: every one of these
accepts `--body-file -`.

### The same, through the API

Useful when you need the id of what you just created, or a field `gh` does not expose:

```bash
# comment on an issue OR a pull request — a PR is an issue, this endpoint serves both
jq -Rs '{body:.}' <body.md | gh api --method POST "repos/$R/issues/$N/comments" --input - --jq .html_url

# update an existing comment
jq -Rs '{body:.}' <body.md | gh api --method PATCH "repos/$R/issues/comments/$CID" --input - --jq .html_url

# new issue
jq -Rs --arg t "Dropdown closes while typing" '{title:$t, body:.}' <body.md |
  gh api --method POST "repos/$R/issues" --input - --jq .html_url
```

`jq -Rs '{body:.}'` is the safe way to put arbitrary text into JSON — it handles quotes, newlines and
backslashes that string interpolation gets wrong.

### Inline review comment, on a specific line

The one case that is genuinely different: it needs a commit and a location.

```bash
SHA=$(gh pr view "$N" --repo "$R" --json headRefOid --jq .headRefOid)
jq -Rs --arg sha "$SHA" --arg path "src/components/Dropdown.tsx" \
  '{body:., commit_id:$sha, path:$path, line:142, side:"RIGHT"}' <body.md |
  gh api --method POST "repos/$R/pulls/$N/comments" --input - --jq .html_url
```

`line` refers to the line in the **diff** on the given `side` (`RIGHT` = the head version). Get it
wrong and the API answers 422 rather than misplacing the comment.

Note the asymmetry, because it catches people: ordinary conversation comments live at
`issues/{n}/comments` even for a PR; `pulls/{n}/comments` is only for inline review comments.

### Editing a body without destroying it

Every `edit` replaces the body **whole**. Read, append, write back:

```bash
gh pr view "$N" --repo "$R" --json body --jq .body > current.md
{ cat current.md; printf '\n\n---\n\n### Visual check\n\n'; cat fragment.md; } > new.md
gh pr edit "$N" --repo "$R" --body-file new.md
```

When the body belongs to someone else, prefer a comment. A comment is additive and cannot destroy
anything; an edit can, and the loss is silent.

## Not posting the same thing twice

An agent re-running its own workflow will attach the same evidence again, and each repeat costs both
a duplicate comment and — worse — another permanent asset.

### The comment marker

Put an invisible marker in the body, search for it, update instead of adding:

```bash
KEY=ui-check                                   # stable per purpose, not per run
MARKER="<!-- github-media-attach:$KEY -->"

# More than one comment can carry the marker, and --jq is applied per page, so no
# filter picks a single winner across pages. Stream the ids; take the first after.
IDS=$(gh api --paginate "repos/$R/issues/$N/comments" \
      --jq ".[] | select(.body != null and (.body|contains(\"$MARKER\"))) | .id")
CID=$(printf '%s\n' "$IDS" | head -n1)

if [ -n "$CID" ]; then
  jq -Rs --arg m "$MARKER" '{body:($m+"\n"+.)}' <body.md |
    gh api --method PATCH "repos/$R/issues/comments/$CID" --input - --jq .html_url
else
  jq -Rs --arg m "$MARKER" '{body:($m+"\n"+.)}' <body.md |
    gh api --method POST "repos/$R/issues/$N/comments" --input - --jq .html_url
fi
```

Or: `scripts/upsert-comment.sh --repo "$R" --number "$N" --key "$KEY" --body-file body.md`.

HTML comments do not render, so the marker is invisible to readers.

### The asset ledger — the part that actually saves money

The marker stops the *comment* multiplying. It does nothing about the *upload*: capturing the same
screen again produces different bytes, and uploading it again produces a second permanent asset.

Keep a digest→URL map so a repeat reuses what already exists:

```bash
LEDGER=.easy-cast/assets.tsv
mkdir -p "$(dirname "$LEDGER")"; touch "$LEDGER"

D=$(sha256sum out.mp4 | cut -d' ' -f1)
URL=$(awk -v d="$D" '$1==d{print $2; exit}' "$LEDGER")
if [ -z "$URL" ]; then
  URL=$(scripts/upload-asset.sh --repo "$R" out.mp4)
  printf '%s\t%s\n' "$D" "$URL" >> "$LEDGER"
fi
```

Two things to know about that file:

- It is bound to the directory you ran in. Another machine, CI, or a run from elsewhere has no
  ledger and will re-upload.
- **Do not commit it to a public repository.** An attachment URL is a capability — anyone who can
  read a comment quoting it can fetch the bytes. A ledger in a public repo publishes every asset it
  lists. `.gitignore` it, or keep it outside the tree.

If you need the reuse to survive across machines, carry the map inside the marked comment itself
(inside the HTML comment, where it does not render) and read it back before uploading. That is what
`easy-cast` does; doing it by hand is possible but fiddly, and worth it only for a workflow that
really does run from more than one place.

## Worked examples

The fragment is identical in all three. Only the last line changes.

### Reporting a visual bug

```bash
cat >body.md <<'MD'
### The dropdown closes while the filter is being typed

Typing into the filter closes the menu after the first keystroke, so only one character
is ever matched. Reproduced on `main` at 4f21c9e, Firefox 141 and Chrome 139.

![menu closing after the first keystroke](ASSET_URL)

Expected: the menu stays open until it loses focus.
MD
gh issue create --repo "$R" --title "Filter dropdown closes after the first keystroke" --body-file body.md
```

### Showing a feature in the PR description

```bash
cat >body.md <<'MD'
## What this adds

Inline filtering on the members table, debounced at 200 ms.

https://ASSET_URL_VIDEO

<details><summary>Empty and error states</summary>

![no members match the filter](ASSET_URL_EMPTY)
![the filter request failed](ASSET_URL_ERROR)

</details>
MD
gh pr create --repo "$R" --title "Inline filtering on the members table" --body-file body.md
```

### Proving a fix on the PR that made it

```bash
cat >body.md <<'MD'
### Fixed

The menu now stays open for the whole filter interaction:

| Before | After |
| --- | --- |
| <img src="ASSET_URL_BEFORE" width="380"> | <img src="ASSET_URL_AFTER" width="380"> |

Same viewport (1280×800), same seed data.
MD
gh pr comment "$N" --repo "$R" --body-file body.md
```

Note what makes the last one work: **same viewport, same data.** Two frames that also differ in a
timestamp, an avatar and a window size make the reviewer hunt for the change.

## After posting

- Report the **comment URL**, not the asset URL. The comment is where the picture exists.
- Do not fetch the asset URL to check your work — it answers 404 forever
  ([upload.md](upload.md)).
- If the image does not render in the comment, the cause is the fragment (a video wrapped in
  `![]()`, a missing blank line, a mangled URL), not the upload. Read the comment body back with
  `gh api "repos/$R/issues/comments/$CID" --jq .body` and look at what actually got posted.
