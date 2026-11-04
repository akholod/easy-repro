# Capturing for a person

What `repro` records is watched by a reviewer, once, probably at 1x, and it may later be published
where it can never be withdrawn. Four things follow: pick the cheapest medium that shows the point,
record on data that was never sensitive, pace the recording for an eye rather than a test runner,
and look at the finished file before anyone else does.

## 1. Which medium

| What the subject is | Capture | Why |
| --- | --- | --- |
| Layout, styling, a static screen, an empty or error state | **one screenshot** | a still shows all of it |
| A flow, an interaction, an animation, anything with timing | **one short video** | a still cannot show a transition |
| A difference that only reads as a difference | two screenshots, same viewport, same scroll | the reviewer compares; nobody compares against memory |
| Nothing to look at: a log, a stack trace, a CLI | nothing | say it in prose and stop; a gif of a log is worse than a code fence |

A video costs a reviewer a minute; a screenshot costs a second. When both would work, the screenshot
wins. One artifact per point — three screenshots of the same page from different scroll positions
is noise, not thoroughness.

## 2. A sanitised session

Sanitised data is the only defence that removes the problem instead of covering it. A mask holds on
a still and leaks on video; a review catches what the first two missed; deleting an upload later does
not exist. Production data in frame is a defect in the scenario, fixed by re-recording.

| Where real data gets into a clean frame | Fix |
| --- | --- |
| The logged-in account: display name, avatar, email in the account menu | a test account with a fictional name, created for demonstrating |
| Seed data copied from production into staging | fixtures written for the demo; a staging box carrying a copy of prod **is** production |
| The browser profile: autofill, saved passwords, other tabs, bookmarks | a fresh in-memory session, never your own profile (`playwright-cli` sessions are in-memory unless `--persistent`) |
| Saved storage state used to skip a login | log in as the test account inside the scenario, or load state that belongs to the test account only |
| The URL bar: signed links, `?token=`, `?jwt=`, internal hostnames | navigate to a clean URL before recording starts |
| DevTools panels, a request log, notification toasts, desktop chrome | close them; record the page, not the desktop |

Settle the account at preflight, not at capture: you do not yet know this folder will never be
posted.

## 3. Pacing a recording

A script written for speed produces two seconds of unreadable smear. The rhythm below is the
difference between a test recording and one a person can follow:

| Moment | Do | Why |
| --- | --- | --- |
| Start | wait ~700 ms after the first paint | the opening frame becomes the poster; a half-rendered page makes a useless thumbnail |
| Typing | character by character, ~60 ms delay (`pressSequentially(text, { delay: 60 })`) | setting a value in one tick reads as a glitch, not as typing |
| After a click | wait 800–1200 ms | the action and its result must not land in the same perceived instant |
| The reveal | hold ~1500 ms on the frame the recording exists for | the one frame that has to be readable |
| End | one beat after the last action, then stop | a cut mid-animation reads as broken |

Viewport **1000–1280 px wide**, height following the content; GitHub's inline player downscales
anything wider until the text is unreadable. Length in **seconds** — fifteen is a lot. If the
scenario does not fit, it covers more than one point: split it, or screenshot the part that matters.

Record the whole scenario as **one script**. A process per step (one CLI call per click) puts dead
air of unpredictable length between actions, and the result is unwatchable. Do not narrate with
`console.log`; it goes nowhere a viewer can see.

Skeleton — the exact API depends on the driver, the shape does not:

```js
// playwright-cli: run-code --filename=demo.js   ·   plain Playwright: the same body in a script
async page => {
  await page.screencast.start({ path: 'demo.webm', size: { width: 1280, height: 800 } });

  await page.goto('http://localhost:5173/app');
  await page.waitForTimeout(700);                       // let the first frame settle

  await page.getByRole('textbox', { name: 'Title' })
    .pressSequentially('Quarterly report', { delay: 60 });
  await page.waitForTimeout(900);

  await page.getByRole('button', { name: 'Save changes' }).click();
  await page.waitForTimeout(1200);                      // let the result be seen

  await page.getByText('Quarterly report').waitFor();
  await page.waitForTimeout(1500);                      // hold on the point
  await page.screencast.stop();
}
```

With plain Playwright instead of `playwright-cli`, record through the context
(`browser.newContext({ recordVideo: { dir, size } })`) and the video lands in `dir` when the
context closes. Browser recorders write `.webm`; that is fine for a local folder. Converting to
h264 mp4 is only needed when the file goes to GitHub, and that is `github-media-attach`'s job.

## 4. Looking at the finished file

Mandatory, every time. The script describes what you meant to capture; the file is what you
captured.

**A screenshot:** read the PNG directly.

**A video:** frames, not a scrub. Exposure is normally in the middle, where the page scrolled or a
menu opened, so the first and last frame are not a review.

```bash
ffmpeg -i demo.webm -vf "fps=2,scale=360:-1,tile=5x4" sheet.png     # one contact sheet: ten seconds at a glance
ffmpeg -ss 6.5 -i demo.webm -frames:v 1 frame-6500ms.png            # any suspicious tile at full size
```

Match the grid to the length; a sheet that drops the tail of the video is a review that did not
cover the tail. Delete the sheet and frames afterwards — they are the same data as the video. No
`ffmpeg`? Then the video cannot be reviewed: take a screenshot instead, which was probably the better
choice anyway.

What you are looking for:

| Look for | Typical hiding place |
| --- | --- |
| Tokens, JWTs, session ids, API keys | the URL bar, a copied link, a share dialog, a devtools panel |
| `?token=`, `?jwt=`, `?sig=` in a visible URL | signed asset links, download links, preview links |
| Email addresses, real customer or employee names | the account menu, a user list, seed data, an assignee dropdown, an avatar tooltip |
| Internal hostnames and ports | the URL bar, an error banner, a stack trace |
| Unrelated tickets, customers, tabs | a sidebar, a search history, an autocomplete dropdown |

Rule of thumb: anything you would not paste into a pull request description as plain text does not
belong in a frame either. If the file has something in it, re-record on cleaner data; there is no
post-hoc blur in this toolchain.
