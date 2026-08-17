# easy-cast-skill

An agent skill for putting a screenshot or a video into a GitHub issue, pull request or comment —
using only `gh`, `curl` and `ffmpeg`.

```bash
npx skills add akholod/easy-cast-skill
```

It ships one skill, **`github-media-attach`**.

## Why

An agent that changes the front end can only report in prose: *"done, checked it."* A reviewer gets a
claim, not proof. The path from "nothing captured" to "the image is rendered in the thread" is
short, but every step of it has a trap:

- capture is easy to get wrong (the whole desktop instead of one window; test-speed pacing that
  produces an unwatchable smear);
- GitHub only plays h264 mp4 with `yuv420p` — everything else is a black box in the thread;
- the upload endpoint is **undocumented**, needs a numeric `repository_id`, and answers the same 404
  for three unrelated causes;
- the asset URL answers **404 forever**, so the obvious way to verify an upload makes an agent
  conclude it failed and upload again — permanently, once per iteration;
- and **an uploaded attachment can never be deleted**, by anyone, by any means.

The skill is that path with the traps marked.

## What is in it

| | |
| --- | --- |
| `SKILL.md` | the whole pipeline: decide → capture → annotate → convert → review → upload → place |
| `references/capture.md` | screenshots and video on Wayland, X11, macOS, headless, and from a browser |
| `references/convert.md` | to h264 mp4; trimming, size targeting, contact sheets |
| `references/annotate.md` | boxes, arrows, labels and redaction — ImageMagick, ffmpeg filters, browser overlays |
| `references/upload.md` | the endpoint, measured; every response and what to do with it; documented fallbacks |
| `references/attach.md` | the markdown fragment and every placement: new issue, new PR, body, comment, inline review |
| `references/safety.md` | what must never reach a frame, and what to do when something did |
| `scripts/upload-asset.sh` | one file → one asset URL, with the id lookup, the type table and the response classification |
| `scripts/upsert-comment.sh` | post a comment, or update the one this workflow posted last time |

The skill works without the scripts: every command they run is written out in the documentation.

It is deliberately indifferent to what the change *is*. A bug report, a feature demo and a fix
verification differ in one line — which `gh` command places the body.

## Install

```bash
npx skills add akholod/easy-cast-skill              # this project
npx skills add akholod/easy-cast-skill -g           # all projects
npx skills add akholod/easy-cast-skill -a claude-code -a codex -y
```

`skills` installs to whichever agents it finds — Claude Code, Codex, OpenCode, Cursor and others.
Or copy `skills/github-media-attach/` into your agent's skills directory by hand; it is plain
markdown and two shell scripts.

**Runtime dependencies**, none of them installed by this package: `gh` (authenticated), `jq`, `curl`
for the upload; `ffmpeg` for video; ImageMagick for image annotation; a capture tool appropriate to
your session. `SKILL.md` opens with a one-liner that reports which of them you have.

## Uploads are irreversible

GitHub exposes no delete for user attachments. Deleting the comment does not remove the asset,
editing it does not, closing the issue does not. The bytes stay, and anyone who can read a comment
quoting the asset can still fetch them.

One consequence is worth stating on the front page, because the shape of the URL suggests the
opposite: **a private repository does not protect the file.** The attachment URL never serves bytes
to anyone; GitHub substitutes a short-lived signed URL when it *renders* the comment, and that signed
URL was fetched with no credentials at all during testing — for an asset uploaded against a private
repository and quoted in a public issue. Access follows **who can read the comment**.

So the skill's rules about sanitised data and looking at the finished file before uploading are not
ceremony. They are the only defences that exist.

## Relationship to `easy-cast`

[`easy-cast`](https://github.com/akholod/easy-cast) is a CLI that does the upload half properly: a
write-ahead journal so a re-run reuses assets instead of re-uploading them, a digest→URL ledger
carried inside the comment so another machine reuses them too, a `--dry-run` plan bound to the run by
a token, an identity check between the uploading token and the commenting session, and an
`(exitCode, reason)` pair with a `nextAction` for every outcome.

**This skill is the fallback for when it is not installed** — and the reference for the half no tool
can do for you: deciding whether to attach anything at all, capturing something watchable, and
looking at the file before it becomes permanent.

The endpoint behaviour documented here was measured by `easy-cast`'s stage-0 probe on 2026-08-16
against a live private and a live public repository. What was *not* measured is listed as such in
`references/upload.md` rather than guessed.

## Licence

MIT. See [LICENSE](LICENSE).
