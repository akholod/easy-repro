# The spec and the report

Two files close a run: `spec.json`, which says what each artifact shows, and `out/report.md`, which
is what a person reads. The spec exists so that the label — the sentence proving somebody opened the
file — is written once and checked mechanically against `notes.md`; the report is rendered from it.

## `spec.json`

```json
{
  "version": 1,
  "title": "reproduced: menu overlaps the header on a cold load",
  "sections": [
    {
      "heading": "What happens",
      "text": "The bug is X, triggered by Y, observable as Z.",
      "artifacts": [
        { "path": "media/after.png", "label": "the menu covers Save — the button is unreachable" }
      ]
    },
    {
      "heading": "How to see it",
      "text": "Cold load of /settings as the test account; a warm load does not show it."
    }
  ]
}
```

- `title` starts with the verdict for a bug (`reproduced:`, `not reproduced:`, `partially
  reproduced:`, `works as designed:`) and with `demo:` for a feature.
- `path` is relative to the run directory, written exactly as `notes.md` writes it under
  `reviewed:` — `check.mjs run` matches the two strings.
- `label` says what the frame shows and why it matters, never the file name. `Z` from P1 is usually
  already the right sentence.
- Prose that is not an image goes in a section's `text`, never in a screenshot of text.
- `version` stays `1`; it is what `check.mjs` reads.

## Rendering `out/report.md`

Write it yourself from the spec — no tool is needed, and the shape is fixed so every report reads
the same:

```markdown
# <title>

## <section.heading>

<section.text>

![<artifact.label>](assets/<basename>)
*<artifact.label>*

## <next section …>

---
Recorded <ISO date> · account: <from notes.md> · data: <from notes.md> · nothing was uploaded.
```

Rules that make the folder self-contained:

1. Copy every artifact the spec names into `out/assets/`, keeping the basename, and reference it by
   that relative path. The folder must survive being zipped and opened elsewhere.
2. A video is embedded the same way: `![label](assets/flow.webm)` works in GitHub-flavoured
   renderers; add a plain link on the next line (`[flow.webm](assets/flow.webm)`) for the ones
   that do not play it inline.
3. Every artifact gets its label as a caption line. A bare image with no sentence is exactly the
   "list of file paths" the spec exists to prevent.
4. The footer repeats `account:` and `data:` from `notes.md`. A reader deciding whether the folder
   can be shared should not have to open a second file.
5. Read `out/report.md` before handing it over — the last free moment, and free because the folder
   is deletable.

The finished run directory:

```
<run-dir>/
  notes.md        account, data, iterations, reviewed — the gate
  spec.json       what each artifact shows
  media/          the captures, as recorded
  out/
    report.md     the rendered report
    assets/       the artifacts the report references
```

`node check.mjs run <run-dir>` (in this plugin's repository) verifies that every artifact in the
spec has its `reviewed:` line in `notes.md`, that the four `notes.md` sections exist, and that a
`not reproduced` verdict has an iteration log behind it. Run it before handing anything over; it is
the only part of the review that a machine can check.
