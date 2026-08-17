---
name: github-media-attach
description: Put a screenshot or a video into a GitHub issue, pull request, or comment using only gh, curl and ffmpeg. Covers capturing the screen or a browser, converting to mp4, annotating, uploading to GitHub's attachment endpoint, and placing the markdown — for a new issue, a new PR, an existing body, or a comment. Use when a change or a bug is visible to the eye and describes poorly in prose, and no dedicated attachment CLI is installed.
---

# Media on a GitHub issue, PR or comment

Prose cannot show a layout. "Fixed the dropdown, checked it" is a claim; a screenshot is evidence.
This skill is the whole path from "nothing captured yet" to "the image is rendered in the thread",
using tools that are already on most machines: `gh`, `curl`, `ffmpeg`.

It does not matter whether the thing is a bug, a feature or a fix, or whether it lands in an issue, a
pull request or a comment. Those differ only in the **last step**, and only in which `gh` command
places the same markdown. Everything before that is identical.

**If `easy-cast` is installed, use it instead** — §11. This skill is the manual path.

---

## 0. The pipeline

```
decide → capture → annotate → convert → LOOK AT IT → upload → place the markdown
  §1        §2        §4         §3         §5          §6          §7
```

Two of those steps are the ones agents skip, and both are expensive:

- **§5, looking at the finished file.** Nothing downstream can check it for you.
- **§1, deciding not to attach anything.** Most changes need no attachment at all.

### An uploaded attachment cannot be deleted — ever

Not by deleting the comment, not by editing it, not by closing the issue, not by any API call.
GitHub exposes no delete for user attachments. The bytes stay, and anyone who can read a comment
quoting the asset can still fetch them.

So the order of defences is fixed, and the last row is the one that does not exist:

| Line | Mechanism | Strength |
| --- | --- | --- |
| 1 | capture on fictional data, in a clean session | removes the problem instead of covering it |
| 2 | paint over the region before uploading | covers a region of a frame that does not move |
| 3 | look at the finished file | catches what 1 and 2 missed |
| — | delete it afterwards | **does not exist** |

Read [references/safety.md](references/safety.md) before the first capture on any app that is logged
in, holds real data, or belongs to a public repository.

---

## 1. Whether to attach at all

| What the change is | Attach | Why |
| --- | --- | --- |
| Layout, styling, a static screen, an empty or error state | one screenshot | a still shows all of it |
| A flow, an interaction, an animation, anything with timing | one short video | a still cannot show a transition |
| A difference that only reads as a difference | two screenshots, before then after, same viewport | the reviewer cannot compare against memory |
| A visual bug being reported | screenshot; video only if a sequence is needed to make it appear | prose repro steps for a layout bug are rarely reproducible |
| Backend, refactor, config, dependency bump, docs, test-only | **nothing** | there is nothing to look at |

**A video costs a reviewer a minute of attention; a screenshot costs a second.** When both would
work, the screenshot wins. Default to a screenshot.

One artifact per point. Three screenshots of the same page at slightly different scroll positions is
noise, and it teaches reviewers to skip your attachments.

Attaching nothing is the right answer for most pull requests. Say what you did in prose and stop.

---

## 2. Capture

Pick by what you actually have. One command tells you:

```bash
for t in ffmpeg magick convert grim slurp wf-recorder maim scrot import screencapture; do
  printf '%-14s %s\n' "$t" "$(command -v $t || echo -)"
done; echo "session: ${XDG_SESSION_TYPE:-?}"
```

| You have | Screenshot | Video |
| --- | --- | --- |
| A browser automation tool (Playwright, chrome-devtools MCP, Puppeteer) | **prefer it** — fixed viewport, no desktop chrome, no other windows | same |
| Wayland (`XDG_SESSION_TYPE=wayland`) | `grim shot.png`, region: `grim -g "$(slurp)" shot.png` | `wf-recorder -f cap.mp4` (Ctrl-C to stop) |
| X11 | `import -window root shot.png`, or `maim`/`scrot` | `ffmpeg -f x11grab -framerate 30 -video_size 1280x800 -i :0.0 cap.mp4` |
| macOS | `screencapture -x shot.png` | `screencapture -v cap.mov` |
| A terminal session, not a GUI | — | `asciinema rec`, then `agg` to gif, then §3 |

**Capture the app, not the desktop.** A full-screen grab brings in your other windows, your
notifications, your file names and your wallpaper — all of which are permanent once uploaded.

Viewport width **1000–1280**. GitHub's inline player and image column are narrow; a 1920-wide capture
is downscaled until its text is unreadable.

Pacing, chapters, headless servers, browser-recording skeletons, and what makes a recording
watchable rather than a two-second smear: [references/capture.md](references/capture.md).

---

## 3. Convert to mp4

Everything else — `.webm`, `.mov`, `.mkv`, `.gif`, a raw screen capture — becomes h264 mp4 before
upload. The canonical command:

```bash
ffmpeg -y -i in.webm \
  -vf "scale='min(1280,iw)':-2,fps=30" \
  -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p \
  -movflags +faststart -an out.mp4
```

Every flag is load-bearing:

| Flag | Why it is not optional |
| --- | --- |
| `-pix_fmt yuv420p` | without it many encoders produce yuv444, which several browsers refuse to play — a black box in the thread |
| `scale=…:-2` | h264 needs even dimensions; `-2` rounds to even instead of failing on an odd height |
| `-movflags +faststart` | moves the index to the front so the player starts before the whole file is fetched |
| `-an` | drops audio: usually silent anyway, and audio is one more thing that can leak |
| `-crf 28` | quality/size dial. Lower is bigger and sharper; 23–30 is the usable range for screen capture |

**Annotate in this same command** rather than in a second pass (§4) — every re-encode loses quality
and costs time.

Size: GitHub documents 10 MB for images and free-plan video, 100 MB for paid-plan video. The
endpoint's real ceiling has not been measured by anyone here — treat 10 MB as the target and a
rejection as the answer. Trimming, size targeting, gif conversion, and how to shrink a file that is
too big: [references/convert.md](references/convert.md).

---

## 4. Annotate, when the point is not obvious

An unannotated screenshot of a busy page makes the reviewer hunt for what changed. One box and one
caption fix that. Two boxes usually mean the frame is making two points and should be two frames.

Image, with ImageMagick (`magick` on v7, `convert` on v6):

```bash
FONT=$(fc-match -f '%{file}' sans)      # several builds have NO default font and
                                        # fail every -annotate without this
magick shot.png \
  -stroke '#d73a49' -strokewidth 3 -fill none -draw 'rectangle 120,240 480,300' \
  -stroke none -fill '#d73a49' -font "$FONT" -pointsize 20 \
  -annotate +120+330 'was stale before this change' \
  annotated.png
```

Video, folded into the conversion from §3:

```bash
ffmpeg -y -i in.webm -vf "
  scale='min(1280,iw)':-2,
  drawbox=x=120:y=240:w=360:h=60:color=red@0.9:t=3:enable='between(t,2,5)',
  drawtext=text='was stale before this change':x=120:y=310:fontsize=22:
    fontcolor=white:box=1:boxcolor=black@0.6:enable='between(t,2,5)'
" -c:v libx264 -pix_fmt yuv420p -movflags +faststart -an out.mp4
```

**Redaction is a filled box, never a blur.** A blur is reversible in principle and unconvincing in
practice; and on video a box only covers the region while the content underneath stays put — a
region that scrolls is not redacted at all. If something must be hidden from a moving frame,
re-capture on clean data instead.

Arrows, before/after labels, dimming everything but the subject, multi-element callouts, browser
overlays, redaction recipes: [references/annotate.md](references/annotate.md).

---

## 5. Look at the finished file. Every time.

**Before the upload, not after.** After it, nothing can be taken back.

| Artifact | How |
| --- | --- |
| Screenshot | read the PNG — you can see images. Do not reason about it from the script that produced it |
| Video | contact sheet first: `ffmpeg -i out.mp4 -vf "fps=2,scale=360:-1,tile=5x4" sheet.png`, then read `sheet.png` |

Checking the first and last frame is not a review. Exposure happens in the middle, at the moment the
page scrolled or a menu opened.

Looking for: tokens, JWTs, session ids, `?token=` / `?jwt=` / `?sig=` in any visible URL; email
addresses; real customer or employee names; internal hostnames; unrelated tickets; anything from
another tab or the desktop.

Rule of thumb: **anything you would not paste into the PR description as plain text does not belong
in a frame either** — the text can be edited afterwards, the frame cannot.

No `ffmpeg` to extract frames? Then the video cannot be reviewed, and an unreviewed video is not
uploaded. Attach a screenshot instead.

---

## 6. Upload

One POST. The endpoint is **undocumented** — this is what GitHub's own web UI calls, and what was
measured against a live repository:

```
POST https://uploads.github.com/user-attachments/assets
     ?repository_id=<numeric id>&name=<file name>&size=<byte length>
Authorization: Bearer <token>
Content-Type: <media type, which must match the file extension>

<the raw bytes>

→ 201 {"url":"https://github.com/user-attachments/assets/<uuid>"}
```

By hand:

```bash
REPO=owner/name
FILE=out.mp4
TOKEN=$(env -u GITHUB_TOKEN gh auth token)          # or "$GH_TOKEN"
ID=$(gh api "repos/$REPO" --jq .id)                 # numeric id, NOT node_id
SIZE=$(wc -c <"$FILE")
NAME=$(jq -rn --arg v "$(basename "$FILE")" '$v|@uri')

printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - \
  -X POST -H "Content-Type: video/mp4" --data-binary @"$FILE" \
  "https://uploads.github.com/user-attachments/assets?repository_id=$ID&name=$NAME&size=$SIZE"
```

Or use the script shipped next to this file, which does the id lookup, the content-type table and
the response classification for you:

```bash
scripts/upload-asset.sh --repo owner/name out.mp4        # prints the asset URL
scripts/upload-asset.sh --repo owner/name --dry-run out.mp4
```

Four things that decide whether this works:

| Requirement | If you get it wrong |
| --- | --- |
| `repository_id` is the **numeric** `id` from `repos/{owner}/{repo}` | omitting it answers **404**, same as no access |
| `Content-Type` is a header, not a query parameter, and must match the extension | **422** naming both the type and the name |
| The token needs **push access** to that repository | **404** — read access is not enough |
| The token is a user token (`gh auth token` or `GH_TOKEN`) | `GITHUB_TOKEN` from Actions is an installation token whose behaviour here has never been observed |

`gh auth token` prints `$GITHUB_TOKEN` when that variable is set, which silently swaps the identity —
hence `env -u GITHUB_TOKEN` above.

Response semantics, the disjunctive 404, the double-complaint 422, and what to do for each:
[references/upload.md](references/upload.md).

---

## 7. Place the markdown

This is the only step that differs between an issue, a PR and a comment — and it differs only in
which `gh` command runs. **The asset URL and the markdown fragment are identical in every case.**

### The fragment

| Kind | Write |
| --- | --- |
| Image | `![what it shows](https://github.com/user-attachments/assets/<uuid>)` |
| Image, sized | `<img src="https://github.com/user-attachments/assets/<uuid>" width="600">` |
| Video | the bare URL **on its own line**, with no markdown syntax around it |

The bare-URL form is what GitHub's web UI writes for video, and it is what makes the player render.
Wrapping a video URL in `![]()` is the common way to end up with a broken image icon.

Always give an image alt text that says what it shows. It is what a screen reader reads, and what
appears when the render fails.

### The target

```bash
BODY=body.md     # your prose plus the fragment

gh issue create  --repo "$R" --title "…" --body-file "$BODY"      # new issue
gh pr create     --repo "$R" --title "…" --body-file "$BODY"      # new PR description
gh issue comment "$N" --repo "$R" --body-file "$BODY"             # comment on an issue
gh pr comment    "$N" --repo "$R" --body-file "$BODY"             # comment on a PR
gh issue edit    "$N" --repo "$R" --body-file "$BODY"             # rewrite an issue body
gh pr edit       "$N" --repo "$R" --body-file "$BODY"             # rewrite a PR body
```

`--body-file` — not `--body "$(cat …)"`. A body passed as an argument breaks on quotes, backticks and
newlines, and lands in the process list.

Editing a body **replaces it whole**. Read it first, append your section, write it back — or post a
comment instead, which is additive and usually the better choice.

Inline review comments on a specific line, review bodies, reactions, threading, and worked examples
for a bug report, a feature demo and a fix: [references/attach.md](references/attach.md).

---

## 8. Do not post the same thing twice

An agent that re-runs its own workflow will attach the same screenshot again — and each repeat is
another permanent asset plus another comment nobody asked for.

Put a marker in the comment, look for it before posting, and update instead of adding:

```bash
MARKER="<!-- github-media-attach:ui-check -->"

# two comments can carry the same marker, and --jq runs per page — pick the first after
IDS=$(gh api --paginate "repos/$R/issues/$N/comments" \
      --jq ".[] | select(.body != null and (.body|contains(\"$MARKER\"))) | .id")
ID=$(printf '%s\n' "$IDS" | head -n1)

if [ -n "$ID" ]; then
  jq -Rs --arg m "$MARKER" '{body:($m+"\n"+.)}' <body.md |
    gh api --method PATCH "repos/$R/issues/comments/$ID" --input -
else
  jq -Rs --arg m "$MARKER" '{body:($m+"\n"+.)}' <body.md |
    gh api --method POST "repos/$R/issues/$N/comments" --input -
fi
```

Or: `scripts/upsert-comment.sh --repo "$R" --number "$N" --key ui-check --body-file body.md`.

The marker is invisible in the rendered comment. Note what it protects and what it does not: the
comment stops multiplying, but **a second upload of the same file is still a second permanent
asset** — reuse the URL you already have rather than re-uploading. Keep it somewhere (§ the ledger
note in [references/attach.md](references/attach.md)) if the workflow may run twice.

If two comments end up carrying the same marker, the **oldest** is the one updated and the rest stay
visible with stale content. That is a deliberate choice — rewriting all of them would be worse — but
it means a stale duplicate has to be deleted by hand.

The issue-comments endpoint serves pull requests too — a PR is an issue. There is no separate
`pulls/{n}/comments` for ordinary comments; that path is for inline review comments only.

---

## 9. The asset URL answers 404 forever — do not "verify" it

A freshly uploaded `https://github.com/user-attachments/assets/<uuid>` returns **404 to a direct
fetch, permanently** — before it is quoted, after it is quoted, in private repositories and public
ones alike. It is an identifier, not a link.

What actually serves the image is a rewrite performed when GitHub **renders** the comment: the HTML
carries a short-lived signed `private-user-images.githubusercontent.com` URL, regenerated on every
render.

This matters because the obvious verification step is destructive:

| After a successful upload | Do | Do not |
| --- | --- | --- |
| Confirming the upload worked | the `201` and the `url` in the body are the confirmation | `GET` the asset URL |
| Confirming it renders | open the comment URL | open the asset URL on its own |
| Seeing 404 on the asset URL | treat it as expected, and say so | re-upload — that is a second permanent asset, and the next 404 will look the same |

**A 404 on the asset URL is never evidence that anything failed.**

One consequence worth knowing before you decide what to capture: the signed URL is scoped to the
**uploading user**, not to the repository, and it was fetched with **no credentials at all** during
testing — for an asset uploaded against a private repository and quoted in a public issue. Access
follows **who can read the comment**, not which repository the file was uploaded against. Uploading
against a private repo protects nothing once the URL is quoted somewhere public.

---

## 10. When it fails

| Status | Means | Do |
| --- | --- | --- |
| **201** | done | read `.url` from the body |
| **404** | **no access, or no such repository, or `repository_id` missing** — indistinguishable | check the id, then check push access. Do not report one of the three as the cause |
| **422** | the content type or the file name was refused, and the body may carry **both** complaints at once | fix the extension/type pair and re-upload; the file did not land |
| **403** | possibly abuse detection or a rate limit; unmeasured | stop. Report it. Do not loop |
| anything else | unclassified — the server may or may not have taken the bytes | **do not repeat.** A repeat can create a second undeletable asset |
| connection dropped after sending | state unknown | same: do not repeat |

The rule that costs the most when broken: **never wrap the upload in a generic retry-with-backoff.**
A retry is safe only when you know the bytes did not land — a 422 or a connection refused before the
body was sent. Anything unknown must be reported, not retried.

Full response semantics, what has been measured and what has not: [references/upload.md](references/upload.md).

---

## 11. If `easy-cast` is installed, use it instead

```bash
command -v easy-cast && easy-cast --help
```

It does everything from §6 to §9 with things this skill cannot give you by hand: a write-ahead
journal so a re-run reuses assets instead of re-uploading them, a digest→URL ledger carried in the
comment so another machine reuses them too, a `--dry-run` plan bound to the run by a token, an
identity check between the uploading token and the commenting session, and a `(exitCode, reason)`
pair with a `nextAction` for every outcome.

This skill is the fallback. §1 through §5 — decide, capture, annotate, convert, look at it — apply
either way, because no tool can do those for you.

---

## References

| File | Read it when |
| --- | --- |
| [references/capture.md](references/capture.md) | capturing anything, especially video or a browser |
| [references/convert.md](references/convert.md) | the file is not mp4, or is too big |
| [references/annotate.md](references/annotate.md) | the frame needs a box, an arrow, a label, or a redaction |
| [references/upload.md](references/upload.md) | the upload failed, or you are writing error handling around it |
| [references/attach.md](references/attach.md) | placing markdown anywhere other than a plain comment |
| [references/safety.md](references/safety.md) | the app is logged in, the data may be real, or the repository is public |

Scripts live in `scripts/` next to this file — `upload-asset.sh` and `upsert-comment.sh`, both with
`--dry-run` and `--help`. They are a convenience; every command they run is written out above, so
this skill works without them.
