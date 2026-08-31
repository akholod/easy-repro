# easy-repro

Skills for visual evidence in software work: produce it by driving the app (**`repro`**), or
deliver what you already have to GitHub without a CLI (**`github-media-attach`**).

```bash
# Claude Code
/plugin marketplace add akholod/easy-repro
/plugin install easy-repro@easy-repro

# any other harness
npx skills add akholod/easy-repro            # this project
npx skills add akholod/easy-repro -a '*'     # every installed agent
npx skills add akholod/easy-repro -s repro   # one skill only
```

`skills` installs to whichever agents it finds — Claude Code, Codex, OpenCode, Cursor and others.
Or copy a directory under `skills/` into your agent's skills folder by hand; each skill is plain
markdown (plus, for `github-media-attach`, two shell scripts).

## Why

An agent that changes the front end can only report in prose: *"done, checked it."* A reviewer gets
a claim, not proof. Two separate problems sit between that claim and actual evidence.

**Producing it.** Something has to drive the app, hit the case, and decide what's worth capturing
in the first place. That's `repro`.

**Delivering it.** Once a screenshot or video exists, getting it into a GitHub issue, PR or comment
has its own traps:

- capture is easy to get wrong (the whole desktop instead of one window; test-speed pacing that
  produces an unwatchable smear);
- GitHub only plays h264 mp4 with `yuv420p` — everything else is a black box in the thread;
- the upload endpoint is **undocumented**, needs a numeric `repository_id`, and answers the same 404
  for three unrelated causes;
- the asset URL answers **404 forever**, so the obvious way to verify an upload makes an agent
  conclude it failed and upload again — permanently, once per iteration;
- and **an uploaded attachment can never be deleted**, by anyone, by any means.

That's `github-media-attach`. `repro` is the layer above it: it drives the app until the thing is on
screen, captures it, and renders the result to a **local folder** through the `easy-cast` CLI.

The two do not chain today, and that is deliberate rather than unfinished. **`repro` posts nothing** —
if `easy-cast` is absent it stops and says so, rather than reaching for an uploader to do a job that
was never about uploading. Reach for `github-media-attach` directly when there is already a file on
disk and somebody has decided it should go on an issue.

## What is in it

| | |
| --- | --- |
| `skills/repro/SKILL.md` | drive the app, reproduce the bug or demo the feature, look at the result, render it to a folder |
| `skills/repro/references/profile.md` | the six-field profile: how this repo starts, and why `ready.failure[]` is the field that earns its place |
| `skills/github-media-attach/SKILL.md` | the delivery pipeline: decide → capture → annotate → convert → review → upload → place |
| `skills/github-media-attach/references/capture.md` | screenshots and video on Wayland, X11, macOS, headless, and from a browser |
| `skills/github-media-attach/references/convert.md` | to h264 mp4; trimming, size targeting, contact sheets |
| `skills/github-media-attach/references/annotate.md` | boxes, arrows, labels and redaction — ImageMagick, ffmpeg filters, browser overlays |
| `skills/github-media-attach/references/upload.md` | the endpoint, measured; every response and what to do with it; documented fallbacks |
| `skills/github-media-attach/references/attach.md` | the markdown fragment and every placement: new issue, new PR, body, comment, inline review |
| `skills/github-media-attach/references/safety.md` | what must never reach a frame, and what to do when something did |
| `skills/github-media-attach/scripts/upload-asset.sh` | one file → one asset URL, with the id lookup, the type table and the response classification |
| `skills/github-media-attach/scripts/upsert-comment.sh` | post a comment, or update the one this workflow posted last time |
| `commands/repro.md` | the `/repro` entry point for Claude Code |
| `.claude-plugin/plugin.json`, `marketplace.json` | the plugin manifests; the repo is its own marketplace |
| `check.mjs` | the checks below, in both modes |
| `evals/triggers.jsonl` | the trigger eval set: 15 prompts, pass bar 100% on the unambiguous rows |

`github-media-attach` works without the scripts: every command they run is written out in the
documentation.

### What `check.mjs` is for

Two things the documents claim about themselves, and one a run claims about itself.

```bash
node check.mjs                 # lint the repo
node check.mjs run <run-dir>   # check that a run reviewed what it is about to hand over
```

Lint holds each `SKILL.md` to its size budget, keeps the precondition phrase in every description
(three skills in one topic neighbourhood are separated by nothing else), and checks that the two
manifests agree on the version and cover every skill directory.

Run mode is the interesting one. The obligation that somebody *looked* at each frame sits in the gap
between producing evidence and delivering it, and no CLI can check it — so `repro` writes what it
saw into `notes.md`, and this checks the correspondence: every artifact the spec names must have its
own bullet under `reviewed:`, keyed by the path exactly as the spec writes it. A run that recorded
`data: NOT SANITISED` is refused outright.

### Where the skills differ

The *delivery* half is indifferent to what the change is: a bug report, a feature demo and a fix
verification place the same markdown, and differ only in which `gh` command puts it there.

The *producing* half is not. `repro` covers a **bug** and a **feature**, and they are different
shapes of work — a bug needs a hypothesis, iteration until the failure signal appears, and a verdict;
a feature demo needs none of that and is eight steps instead of thirteen. A **fix** (before/after in
one comparison) is not in `repro` yet.

One precondition worth stating on the front page: **`repro` handles a subject you can see in a
browser.** A crash in a CLI, a stack trace, anything you would rather paste as text — that is not
this skill, and it fails fast rather than improvising.

## Relationship to `easy-cast`

[`easy-cast`](https://github.com/akholod/easy-cast) is a CLI that does the upload half properly: a
write-ahead journal so a re-run reuses assets instead of re-uploading them, a digest→URL ledger
carried inside the comment so another machine reuses them too, a `--dry-run` plan bound to the run
by a token, an identity check between the uploading token and the commenting session, and an
`(exitCode, reason)` pair with a `nextAction` for every outcome.

- `repro` probes for it (`easy-cast --version`) at preflight, and `easy-cast render` is what writes
  the folder. Absent → `repro` **stops and asks for it**; it does not substitute an uploader, because
  the run posts nothing. Producing the evidence — driving the app, deciding what to capture, looking
  at the result — is unchanged either way; there is simply no folder to hand over without the CLI.
- `github-media-attach` makes the same check for **its own** job (§11 of its `SKILL.md`): with the
  CLI present, use it; without, do the upload by hand. That is a fallback for *delivering to GitHub*,
  and it is not one for `repro` — see above. It is also the reference for the half no tool can do
  for you: deciding whether to attach anything at all, capturing something watchable, and looking at
  the file before it becomes permanent.

## Uploads are irreversible

GitHub exposes no delete for user attachments. Deleting the comment does not remove the asset,
editing it does not, closing the issue does not. The bytes stay, and anyone who can read a comment
quoting the asset can still fetch them.

One consequence is worth stating on the front page, because the shape of the URL suggests the
opposite: **a private repository does not protect the file.** The attachment URL never serves bytes
to anyone; GitHub substitutes a short-lived signed URL when it *renders* the comment, and that signed
URL was fetched with no credentials at all during testing — for an asset uploaded against a private
repository and quoted in a public issue. Access follows **who can read the comment**.

So both skills' rules about sanitised data and looking at the finished file before uploading are not
ceremony. They are the only defences that exist.

The endpoint behaviour documented in `references/upload.md` was measured by `easy-cast`'s stage-0
probe on 2026-08-16 against a live private and a live public repository. What was *not* measured is
listed as such there rather than guessed.

## Licence

MIT. See [LICENSE](LICENSE).
