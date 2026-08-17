# Keeping data out of the frame

An uploaded attachment **cannot be deleted — ever.** Not by editing the comment, not by deleting it,
not by closing the issue, not by any API call. GitHub exposes no delete for user attachments. The
bytes stay, and anyone who can read a comment quoting the asset can still fetch them.

That single fact fixes the order of defences, and the last row is the one that does not exist:

| Line | Mechanism | Strength |
| --- | --- | --- |
| 1 | the scenario runs on a test account with fictional data | the only one that removes the problem instead of covering it |
| 2 | paint over a region before uploading | covers a region of a frame that does not move |
| 3 | look at the finished file before it leaves the machine | catches what 1 and 2 missed |
| — | delete it afterwards | **does not exist** |

## Line 1 — capture something that was never sensitive

Real data in frame is a defect in the *scenario*, fixed by re-capturing. It is not something to paint
over afterwards, because the paint is line 2 and line 2 leaks.

| Ingredient | What it means concretely |
| --- | --- |
| Test account | a fictional display name, email and avatar — an account made for demonstrating, not a real person's account with a nickname |
| Fictional records | fixtures written for the demo: realistic in shape, invented in content |
| Fresh browser session | in-memory profile — no autofill, no saved passwords, no other tabs, no bookmarks bar, no extensions |
| Clean entry URL | navigate to the plain URL before capture starts, never to a signed or token-carrying link |
| Closed devtools | no request log, no console, no storage inspector in frame |
| The app, not the desktop | capture the window or the page; a full-screen grab brings in notifications, file names and whatever is behind |
| A staging box holding a copy of production | **is production.** Treat it as such |

Storage state deserves its own line: loading a saved `state.json` to skip a login is exactly how a
real session and a real account end up in a demonstration. Log in as the test account inside the
scenario, or load storage state that belongs to the test account only.

## Line 2 — painting over, and where it stops working

| Artifact | Does it hold? | Why |
| --- | --- | --- |
| Screenshot, fixed viewport | yes | the region is measured and painted while the frame is still |
| Screenshot, full-page or scrolled | partly | measured once against a layout that moves underneath |
| Video | **no** | what is covered at second 1 is exposed at second 5, and the box does not follow |

Rules that come with it:

- **A solid box, never a blur or a pixelation.** Both are reconstructible in principle and neither
  looks deliberate. A black rectangle is unambiguous.
- The paint is baked into the file. It cannot be undone, and its presence cannot be verified by
  anything except looking at the result.
- A browser overlay is decoration, not a mask — it scrolls away with the content underneath it.
- There is no post-hoc blur step in this toolchain. A finished file containing something it should
  not is **re-captured, not retouched**.

Recipes: [annotate.md](annotate.md).

## Line 3 — look at the finished file

**Mandatory, every time, before the bytes leave the machine.** Nothing downstream can do this for
you, and no flag or token proves it happened.

### A screenshot

Read the PNG directly — you can see images. Do not reason about the file from the script that
produced it. The script describes what you meant to capture; the file is what you actually captured.

### A video

Frames, not a scrub. The exposure is normally in the middle, where the page scrolled.

```bash
# 1. contact sheet first — one image, read it in one go
ffmpeg -i out.mp4 -vf "fps=2,scale=360:-1,tile=5x4" sheet.png

# 2. any suspicious tile at full resolution, by timestamp
ffmpeg -ss 6.5 -i out.mp4 -frames:v 1 frame-6500ms.png

# 3. or every frame, for a short clip
mkdir -p frames && ffmpeg -i out.mp4 frames/f%04d.png
```

`fps=2` over a 5×4 grid covers ten seconds. Match the grid to the length — a sheet that drops the
tail of the video is a review that did not cover the tail of the video.

Clean up afterwards: `rm -rf frames sheet.png`. Frames of a real screen are the same data as the
video they came from.

**No `ffmpeg`?** Then the video cannot be reviewed, and an unreviewed video is not uploaded. Attach
a screenshot instead — it is reviewable with what you have, and it was probably the better choice
anyway.

### What to look for

| Look for | Typical hiding place |
| --- | --- |
| Tokens, JWTs, session ids, API keys | the URL bar, a copied link, a share dialog, a devtools panel |
| `?token=`, `?jwt=`, `?sig=`, `X-Amz-*` in a visible URL | signed asset links, download links, preview links |
| Email addresses | the account menu, a user list, a mailto link, an audit log |
| Real customer or employee names | seed data, an assignee dropdown, a comment thread, an avatar tooltip |
| Internal hostnames and ports | the URL bar, an error banner, a stack trace, a network panel |
| Unrelated tickets or customers | a sidebar list, a search history, an autocomplete dropdown |
| Anything from another tab or the desktop | a full-screen grab that was meant to be a window grab |
| Metadata | EXIF and PNG text chunks travel with the file — `magick in.png -strip out.png` |

Rule of thumb: **anything you would not paste into the pull request description as plain text does
not belong in a frame either.** The frame is more permanent than the text — the text can be edited.

Checking the first and last frame is not a review.

## Visibility is not a defence

The shape of the URL suggests a private link. It is not one.

The attachment URL never serves the image to anyone; GitHub substitutes a short-lived signed URL when
it **renders** the comment, and that signed URL needs no credentials. In testing, an asset uploaded
against a *private* repository and quoted in a *public* issue was fetched anonymously, returning 200.
The signed path is scoped to the **uploading user**, not to any repository.

So access follows **who can read the comment**, not which repository the file was uploaded against.
Two rules follow:

- Never describe an attachment as "a public link" or "a private link". Neither is guaranteed.
- Decide what goes in the frame as though a stranger could open it — the cheapest assumption is also
  the only irreversible one.

## A public repository is a decision, not a step

Uploading into a public repository publishes the frame to everyone, permanently, the moment the
comment renders. That is a decision for the person who owns the consequences.

Ask before doing it, and put the irreversibility **before** the question, not after:

> `acme/docs` is public, and an uploaded attachment can never be deleted — not by deleting the
> comment, not by any flag. The file is `checkout-flow.mp4`; it shows the checkout form with the test
> account's fictional card details on screen. Publish it there?
> — Publish · Do not publish · Attach to a private target instead

## If something leaked anyway

The asset is published and cannot be withdrawn. Do not spend time deleting comments — that changes
nothing about reachability, and it destroys the record of what happened.

| What was exposed | Action |
| --- | --- |
| A token, key or session id | **rotate the credential immediately.** It is compromised, and no amount of comment editing un-compromises it |
| Personal data of a real person | escalate to a human owner. This is a disclosure, not a bug in a script |
| An internal hostname or someone else's ticket id | report it, record it, and fix the scenario before the next capture |

In every case: say plainly what happened, and fix the scenario so the next capture cannot repeat it.
Silently re-capturing a clean version leaves the original exactly where it was.
