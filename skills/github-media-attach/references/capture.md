# Capturing a screenshot or a video

Capture is where most of the damage is done and most of the quality is lost. Two failures dominate:
capturing the whole desktop when the subject was one window, and recording at test speed so the
result is an unwatchable smear.

## Find out what you have first

```bash
for t in ffmpeg ffprobe magick convert grim slurp wf-recorder maim scrot import \
         gnome-screenshot spectacle screencapture xdotool xvfb-run asciinema agg; do
  printf '%-18s %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo -)"
done
echo "session: ${XDG_SESSION_TYPE:-unknown}  DISPLAY=${DISPLAY:-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
```

`XDG_SESSION_TYPE` decides the whole Linux branch. X11 tools (`import`, `maim`, `scrot`, `x11grab`)
either fail or capture a black rectangle under Wayland; Wayland tools (`grim`, `slurp`,
`wf-recorder`) do not exist under X11. Do not guess from the distribution.

## Prefer a browser tool over a screen grab

If the subject is a web page and any browser automation is available — Playwright, a
chrome-devtools MCP server, Puppeteer — use it. It is better on every axis that matters here:

| | Browser capture | Screen grab |
| --- | --- | --- |
| Frame contents | exactly the page | the page, plus your window chrome, plus whatever is behind it |
| Viewport | fixed and reproducible | whatever the window happens to be |
| Repeatability | identical between runs, so before/after actually compare | never identical |
| Leak surface | the page only | notifications, other windows, the taskbar, the wallpaper, file names |
| Headless server | works | needs `xvfb-run` |

A screen grab is for what a browser cannot show: a desktop app, a terminal, an OS-level dialog, a
native mobile emulator.

## Screenshots

### Wayland

```bash
grim shot.png                          # whole output
grim -g "$(slurp)" shot.png            # interactive region — needs a human to drag it
grim -o DP-1 shot.png                  # one named output; wlr-randr lists them
```

`slurp` blocks for a mouse drag, so it is unusable unattended. For an automated capture pick the
output or the geometry explicitly: `grim -g "0,0 1280x800" shot.png`.

### X11

```bash
import -window root shot.png                 # ImageMagick, whole screen
import -window "$(xdotool getactivewindow)" shot.png
maim -i "$(xdotool getactivewindow)" shot.png
scrot -u shot.png                            # focused window
```

### macOS

```bash
screencapture -x shot.png                    # -x: no shutter sound
screencapture -x -R 0,0,1280,800 shot.png    # region
screencapture -x -l "$WINDOWID" shot.png     # one window
```

### Headless Linux, no display at all

```bash
xvfb-run -s "-screen 0 1280x800x24" your-app-command
```

Then capture inside that display with the X11 tools, `DISPLAY` set by `xvfb-run`.

## Video

### Wayland

```bash
wf-recorder -f cap.mp4                       # Ctrl-C stops it
wf-recorder -g "0,0 1280x800" -f cap.mp4
wf-recorder -o DP-1 -f cap.mp4
```

`wf-recorder` writes h264 mp4 directly, so §3 of the skill is often a no-op for it — check with
`ffprobe cap.mp4` before re-encoding, because a needless re-encode only loses quality.

### X11

```bash
ffmpeg -f x11grab -framerate 30 -video_size 1280x800 -i :0.0+0,0 \
  -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -movflags +faststart cap.mp4
```

`-i :0.0+X,Y` sets the top-left corner of the captured rectangle. Getting `-video_size` wrong
produces a capture with a black band, not an error.

### macOS

```bash
screencapture -v cap.mov                     # Ctrl-C stops it
screencapture -v -V 10 cap.mov               # exactly 10 seconds, unattended
```

Produces `.mov`. Convert it — see [convert.md](convert.md).

### Stopping a recording unattended

An agent cannot press Ctrl-C. Either use a duration flag where one exists (`screencapture -V`), or
run the recorder in the background and signal it:

```bash
wf-recorder -f cap.mp4 & REC=$!
# … drive the app …
kill -INT $REC && wait $REC          # SIGINT, not SIGKILL: the file needs to be finalised
```

`kill -9` on a recorder leaves an unplayable file with no moov atom. Always `-INT` or `-TERM`, and
always `wait`.

### Terminal sessions

For a CLI change, a screen recording of a terminal is worse than the text. Attach the text. If the
point is genuinely temporal — a progress display, a TUI, an animation — record it properly:

```bash
asciinema rec demo.cast
agg demo.cast demo.gif
ffmpeg -i demo.gif -movflags +faststart -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" demo.mp4
```

## Recording for a reviewer, not for a test runner

A test recording is as fast as the browser allows. A reviewer recording is paced for an eye that has
to follow it, and that is a different job:

| Moment | Do | Why |
| --- | --- | --- |
| Start | wait ~700 ms after the first paint before doing anything | the opening frame becomes the poster; a half-rendered page makes a useless thumbnail |
| Typing | type character by character with a ~60 ms delay | setting a field's value in one tick reads as a rendering glitch, not as typing |
| After a click | wait 800–1200 ms | the action and its result must not land in the same perceived instant |
| The reveal | hold ~1500 ms on the frame the recording exists for | it is the one frame that has to be readable |
| End | one beat after the last action, then stop | a video that cuts mid-animation reads as broken |

Length: **seconds**. Fifteen is a lot. If the scenario does not fit, the recording is covering more
than one point — split it, or attach a screenshot of the part that matters.

Two things not to do:

- **Do not record as a sequence of separate CLI invocations.** One process per step inserts dead air
  of unpredictable length between actions, and the result is unwatchable. Drive the whole scenario
  from one script.
- **Do not narrate with `console.log`.** It goes nowhere the reviewer can see. Narration is an
  on-frame label — see [annotate.md](annotate.md).

### Browser recording skeleton

Exact API depends on your tool; the shape does not.

```js
// one script, one process, one recording
await startRecording({ path: 'demo.webm', size: { width: 1280, height: 800 } });

await page.goto('https://staging.example.test/app');
await page.waitForTimeout(700);                       // let the first frame settle

await page.getByRole('textbox', { name: 'Title' })
  .pressSequentially('Quarterly report', { delay: 60 });
await page.waitForTimeout(900);

await page.getByRole('button', { name: 'Save changes' }).click();
await page.waitForTimeout(1200);                      // let the result be seen

await page.getByText('Quarterly report').waitFor();
await page.waitForTimeout(1500);                      // hold on the point
await stopRecording();
```

Browser recorders usually write `.webm`; convert it — [convert.md](convert.md).

## Viewport and legibility

- **1000–1280 px wide.** GitHub renders attachments in a narrow column and downscales anything
  wider. At 1920 the text is unreadable at the size a reviewer sees.
- Height follows the content; 620–800 is normal.
- A mobile viewport is legitimate when the change *is* the mobile layout — but label it on the
  frame, or the reviewer reads the narrow capture as a bug.
- Length, not resolution, is what makes a video file big. A ten-second capture at 1000×620 is a few
  hundred kilobytes; a three-minute screen recording is a different object and should not exist.

## Before you move on

- Is the point visible in a single frame, held long enough to read?
- Would it make sense with no sound and no explanation? It will have neither.
- Is everything in frame fictional? If not, **stop and re-capture** — painting over it later is the
  weak defence, see [safety.md](safety.md).
- Is the whole desktop in frame when only one window was needed?
