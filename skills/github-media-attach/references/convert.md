# Converting to something GitHub will play

The goal is one file that renders inline for every reviewer: **h264 video in an mp4 container, with
`yuv420p` pixels and the index at the front.** Anything else — `.webm`, `.mov`, `.mkv`, `.avi`, a
gif, a raw screen capture — gets converted first.

## Check before converting

```bash
ffprobe -v error -show_entries stream=codec_name,pix_fmt,width,height,r_frame_rate \
  -show_entries format=duration,size,format_name -of default=noprint_wrappers=1 in.mp4
```

If it already reports `codec_name=h264`, `pix_fmt=yuv420p` and `format_name` containing `mp4`, do
not re-encode it. A needless re-encode costs quality and time and gains nothing. (`wf-recorder`
output usually passes this check already.)

## The canonical conversion

```bash
ffmpeg -y -i in.webm \
  -vf "scale='min(1280,iw)':-2,fps=30" \
  -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p \
  -movflags +faststart -an out.mp4
```

| Flag | What it does | What happens without it |
| --- | --- | --- |
| `-c:v libx264` | h264, the codec every browser plays | vp9/av1 in an mp4 confuses some players |
| `-pix_fmt yuv420p` | the chroma layout browsers actually decode | plays in `ffplay`, shows a black box in the thread |
| `scale='min(1280,iw)':-2` | caps width at 1280, never upscales; `-2` keeps the height even | h264 rejects odd dimensions — the encode fails outright |
| `fps=30` | caps frame rate | a 60 fps capture is twice the bytes for no visible gain |
| `-movflags +faststart` | moves the index to the front of the file | the player waits for the whole download before the first frame |
| `-an` | drops audio | a silent track wastes bytes; a non-silent one is a leak you did not plan |
| `-preset veryfast` | encoder speed/size trade-off | `slower` is smaller but takes minutes on a long capture |
| `-crf 28` | quality dial: lower = bigger and sharper | 23 is near-transparent, 30 is soft; 28 suits screen capture |

`-y` overwrites without asking. Leave it out and `ffmpeg` blocks on a prompt that nothing will
answer.

## From specific sources

```bash
# .mov from macOS screencapture — often already h264, check first
ffmpeg -y -i cap.mov -c:v libx264 -crf 28 -pix_fmt yuv420p -movflags +faststart -an out.mp4

# animated gif → mp4 (much smaller, and it gets a player instead of a looping image)
ffmpeg -y -i demo.gif -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,fps=30" \
  -c:v libx264 -crf 28 -pix_fmt yuv420p -movflags +faststart out.mp4

# mp4 → gif, only when a gif is genuinely wanted (autoplay, no controls, no sound)
ffmpeg -y -i out.mp4 -vf "fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" demo.gif
```

A gif is almost always the wrong choice: it is several times the size of the same content as mp4, it
cannot be paused, and it has no scrub bar. Use mp4 unless the loop itself is the point.

## Trimming

Most recordings have dead air at both ends. Cut it — it is the cheapest size reduction and the
biggest improvement in watchability.

```bash
# from 00:02 for 9 seconds, no re-encode (fast, cuts only at keyframes)
ffmpeg -y -ss 00:00:02 -i in.mp4 -t 9 -c copy trimmed.mp4

# frame-accurate, re-encoding (use when -c copy lands the cut in the wrong place)
ffmpeg -y -ss 00:00:02 -i in.mp4 -t 9 \
  -c:v libx264 -crf 28 -pix_fmt yuv420p -movflags +faststart -an trimmed.mp4
```

`-ss` before `-i` seeks fast; after `-i` it is exact but slow. With `-c copy` the cut snaps to the
nearest keyframe, which on a screen capture can be a second or two away.

## Getting under a size limit

Check what you have:

```bash
ls -l out.mp4 ; ffprobe -v error -show_entries format=duration -of csv=p=0 out.mp4
```

In the order that costs the least quality:

| Step | Command fragment | Typical saving |
| --- | --- | --- |
| 1. Cut dead air | `-ss … -t …` | proportional — the biggest single win |
| 2. Drop the frame rate | `fps=15` in `-vf` | ~30 % |
| 3. Narrow the frame | `scale=1000:-2` | ~25 % from 1280 |
| 4. Raise `-crf` | `-crf 32` | ~30 %, visibly softer text |
| 5. Slower preset | `-preset slow` | ~10 %, no quality cost, minutes of CPU |

If it is still too big after all five, the recording is covering too much. Split it, or attach a
screenshot of the moment that matters instead.

Hard target, when one is needed (two-pass, `-b:v` in bits per second):

```bash
ffmpeg -y -i in.mp4 -c:v libx264 -b:v 900k -pass 1 -an -f mp4 /dev/null && \
ffmpeg -y -i in.mp4 -c:v libx264 -b:v 900k -pass 2 -pix_fmt yuv420p -movflags +faststart -an out.mp4
rm -f ffmpeg2pass-*.log*
```

## Limits

GitHub documents 10 MB for images and free-plan video, and 100 MB for paid-plan video. **Nobody here
has measured the endpoint's real ceiling**, and the caller's plan is unknown, so treat 10 MB as the
target: warning early is free, and discovering a limit by being refused after uploading 90 MB is not.

The refusal, if it comes, is a **422** — see [upload.md](upload.md). It means the file did not land,
so shrinking and re-uploading is safe.

## Screenshots

Usually nothing to do: PNG is what every capture tool writes and what GitHub renders.

```bash
# a 5 MB full-page PNG that does not need to be one
magick shot.png -resize 1280x shot-small.png       # ImageMagick 7; 'convert' on 6
magick shot.png -quality 82 shot.jpg               # a photo-like screenshot; keep PNG for text/UI

# strip metadata — capture tools can embed a window title, a user name, a machine name
magick shot.png -strip clean.png
```

Keep PNG for anything with text or sharp UI edges; JPEG ringing around glyphs looks like a rendering
bug in the app being demonstrated.

`-strip` is worth it as a habit: EXIF and PNG text chunks travel with the file, and the upload is
permanent.

## Extracting frames, for review

The review step in §5 of the skill needs this:

```bash
# contact sheet: 20 frames at 2 fps, one image
ffmpeg -i out.mp4 -vf "fps=2,scale=360:-1,tile=5x4" sheet.png

# one frame at a timestamp, full resolution
ffmpeg -ss 6.5 -i out.mp4 -frames:v 1 frame-6500ms.png

# every frame, for a short clip
mkdir -p frames && ffmpeg -i out.mp4 frames/f%04d.png
```

`fps=2` over a 5×4 grid covers ten seconds. Match the grid to the length — a sheet that drops the
tail of the video is a review that did not cover the tail of the video.

Clean up afterwards: `rm -rf frames sheet.png`. Frames of a real screen are the same data as the
video they came from.
