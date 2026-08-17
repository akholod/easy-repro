# Annotating a frame

An annotation answers one question: *where do I look, and why does it matter?* Anything else on the
frame is decoration that costs the reviewer time.

Two hard rules before the recipes:

- **One point per frame.** Three callouts mean the frame is making three points; split it.
- **Say why, not what.** A caption that repeats the label already on screen ("Save button") is
  noise. "did nothing before this change" is the annotation.

## Where the coordinates come from

This is the part that stops agents, because none of the tools help with it.

### From a browser

If the capture is driven by browser automation, ask the page:

```js
const target = page.getByRole('button', { name: 'Save changes' });
await target.scrollIntoViewIfNeeded();          // an off-screen element has no box
const box = await target.boundingBox();          // { x, y, width, height }, or null
if (!box) throw new Error('element is not visible — nothing to annotate');
```

Three facts that break this if you do not know them:

| Fact | Consequence |
| --- | --- |
| Coordinates are viewport-relative | scroll after measuring and the box marks empty space |
| Coordinates are instantaneous | a late font, image or banner shifts the layout and invalidates them |
| The box is `null` for anything not visible | `${box.x}` becomes `undefined` and the overlay lands silently at 0,0 |

Re-measure after every scroll, navigation and state change. Measuring once at the top of a script
and drawing five boxes from it is the standard way this goes wrong.

### From the image itself

With no browser in the loop, read the dimensions and estimate — then check your work:

```bash
magick identify shot.png            # e.g. shot.png PNG 1280x800 …
# or: ffprobe -v error -show_entries stream=width,height -of csv=p=0 shot.png
```

Look at the screenshot, estimate the rectangle in pixels from the top-left corner, draw it, **then
read the annotated file and adjust**. Two iterations is normal; guessing once and uploading is not.
This loop is free — nothing is permanent until the upload.

A quick pixel ruler when the estimate keeps missing:

```bash
magick shot.png -fill none -stroke '#00ff0055' -strokewidth 1 \
  -draw "line 0,100 1280,100 line 0,200 1280,200 line 0,300 1280,300
         line 100,0 100,800 line 200,0 200,800 line 300,0 300,800" grid.png
```

Read `grid.png`, take the coordinates off it, and discard it.

## Images — ImageMagick

`magick` on ImageMagick 7, `convert` on 6. Two things to resolve once, at the top of any script:

```bash
IM=$(command -v magick || command -v convert) || { echo "no ImageMagick"; exit 1; }

# -annotate needs a font, and several builds ship with none registered — a
# Homebrew ImageMagick fails with `unable to read font ''` on every text
# operation until one is named explicitly. Resolve a path, do not rely on a default.
FONT=$(fc-match -f '%{file}' sans 2>/dev/null || true)
for f in /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
         /usr/share/fonts/truetype/noto/NotoSans-Regular.ttf \
         /System/Library/Fonts/Supplemental/Arial.ttf; do
  [ -n "$FONT" ] && break; [ -f "$f" ] && FONT=$f
done
[ -n "$FONT" ] || echo "no font found — text annotations will fail" >&2
```

`magick -list font` printing nothing is the symptom: it means no font is registered and every
`-annotate` will fail until `-font "$FONT"` is passed. Drawing — boxes, lines, polygons — needs no
font and works either way, which is why a script can look half-broken.

The `-font "$FONT"` in the recipes below is therefore not optional.

### Box and caption — the default

```bash
"$IM" shot.png \
  -stroke '#d73a49' -strokewidth 3 -fill none \
  -draw 'rectangle 120,240 480,300' \
  -stroke none -fill '#d73a49' -font "$FONT" -pointsize 20 \
  -annotate +120+330 'was stale before this change' \
  annotated.png
```

`rectangle x1,y1 x2,y2` takes two corners, **not** an origin and a size. `-annotate +x+y` places the
text baseline, so the text sits *above* that y — add ~25 px of clearance below the box.

`-stroke none` before the text matters: without it the caption is drawn with a 3 px outline in the
same colour and turns into a blob.

### Caption on a bar, so it is readable over any background

```bash
"$IM" shot.png \
  -fill '#24292fdd' -draw 'rectangle 0,0 1280,44' \
  -fill white -font "$FONT" -pointsize 22 \
  -annotate +16+30 'After: the row appears immediately' \
  annotated.png
```

### Arrow

```bash
"$IM" shot.png -stroke '#d73a49' -strokewidth 3 -fill '#d73a49' \
  -draw 'line 700,180 520,250' \
  -draw 'polygon 520,250 545,240 540,265' \
  -stroke none -font "$FONT" -pointsize 20 -annotate +705+175 'this count' \
  annotated.png
```

The polygon is the head; keep its three points within ~25 px of the line's end or it detaches.

### Dim everything but the subject

```bash
"$IM" shot.png \
  \( +clone -fill black -colorize 55% \) -compose over -composite \
  \( shot.png -crop 360x60+120+240 +repage \) -geometry +120+240 -composite \
  -stroke '#ffffff' -strokewidth 2 -fill none -draw 'rectangle 120,240 480,300' \
  annotated.png
```

Darkens the whole frame, then pastes the region of interest back at full brightness. Stronger than a
box when the page is busy — and note `-crop WxH+X+Y` uses width/height/offset, unlike `-draw
rectangle`.

### Side-by-side before/after

```bash
"$IM" before.png -font "$FONT" -pointsize 24 -fill white -undercolor '#6e7781' -annotate +12+34 ' BEFORE ' b.png
"$IM" after.png  -font "$FONT" -pointsize 24 -fill white -undercolor '#1a7f37' -annotate +12+34 ' AFTER '  a.png
"$IM" b.png a.png +append before-after.png        # -append for stacked instead of side by side
```

One image beats two attachments: the reviewer sees the comparison instead of assembling it. Both
halves must be the same viewport, or the difference they see is the viewport.

### Redaction

```bash
# a filled box. Not a blur.
"$IM" shot.png -fill black -draw 'rectangle 300,120 640,160' redacted.png
```

**Never redact by blurring or pixelating.** Both are reconstructible in principle, both look like an
accident, and neither is worth the risk on something that cannot be deleted. A solid box is
unambiguous.

And redaction is the *second* line of defence. If real data is on the frame, the frame was captured
wrong — re-capture on fictional data. See [safety.md](safety.md).

## Video — ffmpeg filters

Check the build first; `drawtext` needs libfreetype and is missing from some minimal builds:

```bash
ffmpeg -hide_banner -filters | grep -E '^\s*\S+\s+(drawbox|drawtext)\b'
```

**Do the annotation in the same command that converts to mp4** ([convert.md](convert.md)). Two
passes means two encodes and two rounds of quality loss.

```bash
ffmpeg -y -i in.webm -vf "
  scale='min(1280,iw)':-2,
  drawbox=x=120:y=240:w=360:h=60:color=red@0.9:t=3:enable='between(t,2,5)',
  drawtext=text='was stale before this change':
    x=120:y=312:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=6:
    enable='between(t,2,5)'
" -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -movflags +faststart -an out.mp4
```

| Piece | Note |
| --- | --- |
| `drawbox` | `x,y,w,h` — origin and size, unlike ImageMagick's two corners. `t=3` is border thickness, `t=fill` fills it |
| `enable='between(t,2,5)'` | seconds. Without it the annotation is on for the whole video, including the frames it does not describe |
| `box=1:boxcolor=…` | a background plate behind the text; without it white text vanishes over a white page |
| `fontfile=` | add `fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf` if `drawtext` complains it cannot find a font |
| Escaping | `:` `'` `%` and `\` inside `text=` must be escaped (`\:`), which is why the examples avoid them. For anything complicated use `textfile=caption.txt` |

Persistent step labels through a longer clip:

```bash
drawtext=text='1. reproduce':x=16:y=16:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.6:enable='lt(t,4)',
drawtext=text='2. after the fix':x=16:y=16:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.6:enable='gte(t,4)'
```

Video redaction, with the limit stated:

```bash
drawbox=x=300:y=120:w=340:h=40:color=black:t=fill:enable='between(t,0,99)'
```

This covers a **fixed rectangle**. The moment the page scrolls, the content moves and the box does
not. On video a box is not redaction — it is a hint. Anything genuinely sensitive means re-capturing
on clean data.

## Browser overlays

When the capture is driven by a browser, the strongest annotations are drawn into the page before
capture: real text rendering, real layout, and they land in both screenshots and video with no
post-processing.

```js
await page.evaluate(({ x, y, w, h, text }) => {
  const d = document.createElement('div');
  d.id = '__annot';
  d.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483647';
  d.innerHTML = `
    <div style="position:absolute;left:${x - 4}px;top:${y - 4}px;
      width:${w + 8}px;height:${h + 8}px;border:2px solid #d73a49;border-radius:6px;
      box-shadow:0 0 0 9999px rgba(0,0,0,.18)"></div>
    <div style="position:absolute;left:${x + w / 2}px;top:${y + h + 10}px;
      transform:translateX(-50%);padding:5px 11px;background:#24292f;color:#fff;
      border-radius:6px;font:13px/1.4 system-ui;white-space:nowrap">${text}</div>`;
  document.body.appendChild(d);
}, { ...box, text: 'did nothing before this change' });

// … capture …
await page.evaluate(() => document.getElementById('__annot')?.remove());
```

`pointer-events:none` keeps the overlay from intercepting clicks, so it can stay up while the
scenario continues. The `box-shadow` spread dims everything except the marked element — drop it when
two things are marked at once, or the two dimmings stack to black.

Remember it is decoration, not a mask: it scrolls away with the content exactly like the page does.

## Restraint

| Symptom | Fix |
| --- | --- |
| Three callouts in one frame | the frame is making three points; split it |
| A caption restating a visible label | drop it — say why it matters |
| The annotation covering the thing it points at | move the caption, or dim instead of boxing |
| A colour legend | too many colours; one accent is enough |
| An arrow starting off-frame | reads as a rendering artifact; move the tail inside |

After annotating, **read the output file**. An annotation that lands on the wrong element is worse
than none — it tells the reviewer to look at the wrong thing, with your authority behind it.
