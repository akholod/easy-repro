# easy-repro

Two agent skills for **visual evidence** in software work:

- **`repro`** — drive the app in a browser until the feature or the bug is on screen, capture a
  screenshot or a short video, look at it, and render a report folder you can hand to a reviewer.
- **`github-media-attach`** — put an existing screenshot or video into a GitHub issue, PR or
  comment, with nothing but `gh`, `curl` and `ffmpeg`.

They do not chain, on purpose: `repro` **posts nothing**. Producing evidence and publishing it are
different decisions, and the second one is irreversible (see [Uploads are irreversible](#uploads-are-irreversible)).

## Quick start

### 1. Install

As a Claude Code plugin (both skills):

```bash
/plugin marketplace add akholod/easy-repro
/plugin install easy-repro@easy-repro
```

As plain skills, on any harness — the channel that can install just one of them:

```bash
npx skills add akholod/easy-repro            # both skills, this project
npx skills add akholod/easy-repro -s repro   # repro only
npx skills add akholod/easy-repro -a '*'     # every installed agent
```

`skills` installs to whichever agents it finds — Claude Code, Codex, OpenCode, pi, Cursor and
others. Or copy a directory under `skills/` into your agent's skills folder by hand; each skill is
plain markdown (plus two shell scripts for `github-media-attach`).

> `skills add -s <name>` picks a **skill**. `claude plugin install -s <scope>` picks a **scope**
> (`user`, `project`, `local`). Same letter, different meaning; `-s repro` on the plugin command is
> an invalid scope, not a filter.

### 2. What `repro` needs on the machine

A browser it can drive, and nothing else. The first one found wins:

| Driver | Notes |
| --- | --- |
| [`playwright-cli`](https://www.npmjs.com/package/@playwright/cli) | preferred: in-memory sessions, one-script recording, screencast chapters |
| Playwright installed in the project | a plain script through `npx playwright` |
| `agent-browser`, a Playwright or DevTools MCP, any other driver | works; the skill adapts the recording skeleton |

`ffmpeg` is used only to review video frame by frame; without it, the skill takes a screenshot
instead. No upload tool is involved: the report is plain markdown the agent writes itself.

### 3. Run it

`repro` is invoked explicitly — it never triggers on its own, so an unrelated "reproduce" in a
prompt does not start a browser session.

| Harness | Invocation |
| --- | --- |
| Claude Code, plugin | `/easy-repro:repro <what to show>` |
| Claude Code, skills channel | `/repro <what to show>` |
| pi | `/skill:repro <what to show>` |
| OpenCode | `/skills` → pick `repro`, then type the subject after the `@repro` mention |
| Codex | `$repro <what to show>` |

Say what should be on screen and where: *"demo the new bulk-export on the orders admin page — select three
rows, export, show the toast"*, or *"the dropdown overlaps the header on a cold load of the settings page"*.
A feature demo needs a route; a bug needs the failure signal you expect to see.

The first run in a repo asks **one** question — how the app starts — and writes the answer to
`.git/info/repro-profile.json` so it never asks again
([why that file has the fields it has](skills/repro/references/profile.md)).

### 4. What you get

A run directory, outside the repo, that you can read, share or delete:

```
<run-dir>/
  notes.md          what account and data were used, what was tried, what each file shows
  spec.json         the report spec: sections, artifacts and the label each one earns
  media/            the screenshot or video, already reviewed frame by frame
  out/
    report.md       the rendered report
    assets/         the artifacts it references, so the folder survives being zipped
```

Nothing is uploaded. If the report should go on an issue or PR, that is a separate ask — to
`github-media-attach`.

## How `repro` works, in one screen

```
P0  Preflight      a browser driver · the test account · the app's start profile
P1  Prove what     "The bug is X, triggered by Y, observable as Z"  /  for a feature: what a viewer must see, at which route
                   then pick the medium: one screenshot, or one short video — never both
P3  Run and watch  start the app, poll for real readiness (a listening port is not readiness),
                   drive the browser, inspect the real DOM before asserting
P4  Narrow         drop steps until only the ones that matter remain, re-running after each
P5  Verdict        reproduced · not reproduced · partially · works as designed  (bugs only)
P6  Capture        on a sanitised session, paced for a human eye, as one script
P7  Look           open every file; write notes.md — the one checkable gate in the run
P8  Spec           spec.json: a label says what the frame shows and why it matters
P10 Render         out/report.md written from the spec, artifacts copied to out/assets/
P12 Put it back    stop the server, confirm git status is clean
```

Two rules carry most of the weight. **Never claim a bug is reproduced until it has been seen in a
running browser** — a diff, an issue comment or a listening port is not evidence. And **open every
finished file before handing it over**: exposure happens mid-video, when a page scrolled or a menu
opened, so the first and last frame are not a review. `node check.mjs run <run-dir>` verifies
mechanically that `notes.md` has a `reviewed:` line for every artifact the spec names.

### What `repro` does not do

- A **fix**, or a before/after comparison. For a reproduce → fix → prove loop, see
  [prove-then-fix](https://github.com/akholod/prove-then-fix); it records its own before/after video.
- Anything you cannot see in a browser: a CLI crash, a stack trace, a log. Those paste better as
  text, and the skill says so and stops.
- Scaffolding a minimal page. The app has to run already.
- Posting. See below.

## `github-media-attach`

For when a screenshot or video already exists and someone has decided it goes on GitHub. It is the
part of the job no tool can do for you — deciding whether to attach anything at all, capturing
something watchable, looking at the file before it becomes permanent — plus the mechanics that are
easy to get wrong:

- GitHub only plays **h264 mp4 with `yuv420p`**; everything else renders as a black box.
- The upload endpoint is undocumented, needs a numeric `repository_id`, and answers the same 404
  for three unrelated causes.
- The asset URL answers **404 forever**, so checking it the obvious way makes an agent conclude the
  upload failed and upload again — once per iteration, permanently.

The pipeline is decide → capture → annotate → convert → review → upload → place, with every
command written out in `references/`, so the two scripts are a convenience rather than a
dependency. When the [`easy-cast`](https://github.com/akholod/easy-cast) CLI happens to be installed, the skill hands the upload to it; it is never required.

## Uploads are irreversible

GitHub exposes no delete for user attachments. Deleting the comment does not remove the asset,
editing it does not, closing the issue does not. The bytes stay, and anyone who can read a comment
quoting the asset can still fetch them.

**A private repository does not protect the file.** The attachment URL never serves bytes to
anyone; GitHub substitutes a short-lived signed URL when it renders the comment, and that signed URL
was fetched with no credentials at all during testing — for an asset uploaded against a private
repository and quoted in a public issue. Access follows who can read the comment.

So both skills' rules about sanitised data and looking at the finished file before uploading are
not ceremony. They are the only defences that exist. The endpoint behaviour in
[`references/upload.md`](skills/github-media-attach/references/upload.md) was measured by
`easy-cast`'s stage-0 probe on 2026-08-16 against a live private and a live public repository;
what was not measured is listed as such rather than guessed.

## Repository layout

| | |
| --- | --- |
| `skills/repro/SKILL.md` | drive the app, reproduce the bug or demo the feature, look at the result, render it to a folder |
| `skills/repro/references/profile.md` | the six-field start profile, and why `ready.failure[]` is the field that earns its place |
| `skills/repro/references/capture.md` | which medium, a sanitised session, pacing a recording for a person, reviewing the finished file |
| `skills/repro/references/report.md` | the spec, the fixed shape of `out/report.md`, the finished run directory |
| `skills/github-media-attach/SKILL.md` | the delivery pipeline |
| `skills/github-media-attach/references/` | `capture.md`, `convert.md`, `annotate.md`, `upload.md`, `attach.md`, `safety.md` |
| `skills/github-media-attach/scripts/` | `upload-asset.sh` (one file → one asset URL), `upsert-comment.sh` (post or update the workflow's comment) |
| `.claude-plugin/` | plugin and marketplace manifests; the repo is its own marketplace |
| `check.mjs` | `node check.mjs` lints the repo (size budgets, the precondition phrase in each description, manifest agreement); `node check.mjs run <run-dir>` checks a run reviewed what it hands over |
| `evals/triggers.jsonl` | 15 trigger prompts; pass bar 100% on the unambiguous rows |

## Licence

MIT. See [LICENSE](LICENSE).
