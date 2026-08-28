---
name: repro
description: Reproduce a bug or demonstrate a feature by driving the app in a browser, then render the evidence to a local folder. Use when nothing has been captured yet and the app has to be driven to see the thing — a subject you can see in a browser. Posts nothing; delivery to an issue or PR is a separate ask.
---

# Reproduce it, then show it

*"Fixed the dropdown, checked it"* is a claim; a screenshot is evidence. This skill is the part before
the evidence exists: decide what would prove the point, drive the app until the thing is on screen,
capture it, look at it, and write a folder somebody can read.

**Never claim a bug is reproduced until you have seen it in a running browser.** Everything below
serves that.

Capture is `playwright-cli`'s job, delivery is `easy-cast`'s; this skill decides *what* to capture and
*whether it is true*. Neighbours are named, never pathed — the path differs per machine, the name does
not.

## Scope, stated plainly

| | |
| --- | --- |
| Subjects | a **bug** to reproduce, or a **feature** to demonstrate |
| Precondition | the app already runs — this skill starts your dev server, it does not scaffold one |
| Sink | a local folder. **Nothing is posted.** |
| Not yet | before/after for a fix, posting to an issue or PR, non-browser subjects, building a minimal reproduction page |

If the subject is a fix, a stack trace, a CLI, or anything you would rather paste as text — say so and
stop. A gif of a log is worse than a code fence.

---

## P0 — Preflight

Fail fast, before anything is started:

```bash
playwright-cli --version || npx --no-install playwright-cli --version   # required
easy-cast --version                                                     # optional — see below
ffmpeg -version                                                         # only if the subject needs video
```

**`easy-cast` renders the folder and has no substitute here.** If the binary does not answer, **stop
and say so** — ask for `npm i -g easy-cast`, or hand over the run directory as it stands. Do **not**
reach for `github-media-attach`: its job is uploading, and this run posts nothing. Probe the
**binary**, not whether a skill is installed.

**The test account is settled here, not later.** §2 of the `easy-cast` skill is the primary defence: a
fictional account, fixture data, a fresh in-memory session, a clean URL. A demo against production
data is a **hard stop** — re-record it. You do not yet know this folder will never be posted.

### The profile

Six fields, read from `$(git rev-parse --git-common-dir)/info/repro-profile.json` — untracked, local,
nobody's permission needed, and correct inside a linked worktree where `.git` is a file:

```json
{
  "version": 1,
  "baseUrl": "http://localhost:5173",
  "start":   { "command": "pnpm dev", "cwd": "." },
  "ready":   { "url": "http://localhost:5173/", "failure": ["EADDRINUSE", "Failed to compile"] },
  "stop":    { "command": "" }
}
```

**Missing?** Ask **one** `AskUserQuestion`: how is this app started. Rank candidates from
`package.json` scripts, `pom.xml` plugins, a `Makefile`, `docker-compose.yml` — and **execute nothing**
while asking, because starting a candidate to find out can rebuild `node_modules`, bind a port or
touch a database. Write the answer; never ask again.

**Arrived with a clone?** It is a file of shell commands somebody else wrote: confirm it once per
machine — show `start.command`, get a yes, record the profile's hash beside it. Confirming at
authoring time covered the author, not you.

`ready.failure[]` earns its place: without it a wait loop hangs forever on a broken build.

---

## P1 — Say what would prove it

One line, written down before anything runs:

> **The bug is X, triggered by Y, observable as Z.**

`Z` is the exact failure signal you will look for, and it is also what the artifact's label will say.
For a feature: **what a viewer must see, and at which route** — a demo with no named route has nowhere
to point the browser.

Then decide the medium, applying §1 of the `easy-cast` skill:

| What it is | Capture |
| --- | --- |
| Layout, styling, a static screen, an empty or error state | **one screenshot** |
| A flow, an interaction, an animation, anything with timing | **one short video** |
| Nothing to look at | nothing — say it in prose and stop |

A video costs a reviewer a minute, a screenshot a second. When both work, the screenshot wins.

---

## P3 — Run it and watch

Start `start.command` in the background and **poll for real readiness** — never `sleep`:

- success: `ready.url` answers;
- failure: any `ready.failure[]` marker appears in the output — **break the loop and report**.

A listening port is not readiness. A page that renders a blank spinner because the frontend never
compiled looks exactly like a real bug, and reporting it as one is the expensive mistake.

Then drive the browser with `playwright-cli` and look for `Z`.

**Inspect the real DOM before asserting.** A snapshot says what *exists*, not what a person would see
— `opacity: 0`, white-on-white and a z-index of −1 all read as "present". Dump the structure once,
build the check from what you saw, and prefer the element's own state or `offsetWidth > 0` over a bare
`hidden` attribute.

Ignore dev-server noise: a favicon 404 and a dev-mode warning belong to no bug. If nothing else
appears, say the console is clean.

### P4 — Narrow the trigger, then re-verify

The trigger is usually more precise than the report: one exact gesture, one property combination, a
timing window. Strip steps until only the ones that matter remain, **re-running after each removal**,
and keep a log of what you tried. *(Minimising the case itself — cutting the page down to a scaffold —
is not in scope here.)*

### P5 — Verdict

From what you saw, not from what the report said:

`reproduced` · `not reproduced` · `partially reproduced` · `works as designed (likely misuse)`

**"Not reproduced" is a real answer**, and a valuable one — give it with the iteration log and the
likely reason. Do not force a positive result. A feature demo has no verdict; it either shows the
thing or it is not finished.

---

## P6 — Capture

Record on the sanitised session from P0. A recording made for a person is paced for a human eye, which
is a different job from a test — take the timings from the `easy-cast` skill's recording reference
rather than guessing them.

Two things are yours here. Record the scenario as **one script** through `run-code`: a process per
step puts dead air of unpredictable length between every action. And do not trust a mask on video — it
holds on a still, but what is covered in frame 1 is exposed in frame 5 after a scroll, and there is no
post-hoc blur in this toolchain. If the finished file has something in it, re-record.

---

## P7 — Look at the file. Write it down.

**Open every finished file and look at it.** Read a PNG directly; for video, extract frames and read
them. First and last frame is not a review — exposure happens in the middle, when the page scrolled or
a menu opened. What to look for is §4 of the `easy-cast` skill: anything you would not paste as plain
text.

Then write `<run-dir>/notes.md`. This file is the gate — it is checkable, and nothing else here is:

```
account:     the fictional account used, or "none — the app is not logged in"
data:        fixtures | synthetic | NOT SANITISED — do not publish
iterations:
  - dropped the second click — still reproduces
  - narrowed to a cold load — reproduces only there
reviewed:
  - media/after.png — the menu overlaps the header, cropping "Save"
  - media/flow.mp4 — frames at 0s / 4s / 8s — the spinner never resolves
```

All four sections are required, and each `reviewed:` bullet **starts with the path exactly as the spec
writes it** — a bare `after.png` would let one line stand for two files in two directories.
`iterations:` must be non-empty before a `not reproduced` verdict.

Writing a line requires having opened the file, which is the point. `check.mjs run <run-dir>` verifies
the correspondence mechanically — run it before handing anything over.

---

## P8 — Author the spec

`spec.json` is a `ReportSpec` — the format `easy-cast` reads. Hand over a **spec, not a list of file
paths**: the label is the mechanical proof somebody opened the file, and a bare path skips it.

```json
{ "version": 1, "title": "reproduced: menu overlaps the header on a cold load",
  "sections": [{ "heading": "What happens", "text": "The bug is X, triggered by Y, observable as Z.",
    "artifacts": [{ "path": "media/after.png",
                    "label": "the menu covers Save — the button is unreachable" }] }] }
```

A label says **what the frame shows and why it matters** — not the file name. `Z` from P1 is usually
already the right sentence. Prose that is not an image belongs in a section's `text`, never in a
screenshot of text.

If `compose` refuses the spec's `version`, the CLI is newer than this skill: re-read the skill. Never
edit the version number to make a refusal go away.

---

## P10 — Render the folder

```bash
easy-cast render --spec <run-dir>/spec.json --out-dir <run-dir>/out
```

You get `report.md`, the artifacts copied beside it under `assets/`, plus `spec.json` and
`manifest.json`. Read `report.md` before handing it over — the last free moment, and free because the
folder is deletable.

**Nothing was uploaded and nothing can be.** Say so; do not imply a link exists.

> Posting this to an issue or PR is a **separate, explicit ask**, and it is not reversible: an
> uploaded attachment can never be deleted — not by deleting the comment, not by any flag. The local
> review does not carry over.

---

## P12 — Put it back

Stop the server with `stop.command`; where one exists, **use it** rather than killing the background
task, which can leave a forked process holding the port. An empty `stop.command` means killing the
task is the defined behaviour.

Then confirm `git status --porcelain` shows nothing you added — run artifacts live outside the repo
for exactly this reason. Keep the run directory: it is the evidence, and it is deletable.
