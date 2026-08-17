# The upload endpoint

`uploads.github.com/user-attachments/assets` is **undocumented**. It is what GitHub's own web UI
calls when you drag a file into a comment box. What follows was measured against live repositories
on 2026-08-16; rows marked *not measured* are honest gaps, not omissions.

## The request

```
POST https://uploads.github.com/user-attachments/assets
     ?repository_id=<numeric id>&name=<file name>&size=<byte length>
Authorization: Bearer <token>
Content-Type: <the media type, which must match the file extension>

<the raw bytes>
```

**Single phase.** There is no policy call, no pre-signed second host, no multipart form. One POST
carrying the bytes, metadata in the query string, the declared type in a header.

| Part | Detail |
| --- | --- |
| `repository_id` | **required.** The numeric `id` from `repos/{owner}/{repo}`, *not* `node_id`. Omitting it answers 404 — the same answer as no access, so a missing id looks exactly like a permissions problem |
| `name` | the file name as it will be recorded. URL-encode it |
| `size` | the byte length. Send the real one |
| `Content-Type` | a **header**, not a query parameter. A request with no declared type was refused with `400 Invalid Content-Type` during exploratory work (seen, never captured in the log) |
| body | the raw bytes, not base64, not multipart |

### Content types

The type must match the extension, or the endpoint refuses with 422 naming both facts.

| Extension | `Content-Type` |
| --- | --- |
| `.png` | `image/png` |
| `.jpg`, `.jpeg` | `image/jpeg` |
| `.gif` | `image/gif` |
| `.webp` | `image/webp` |
| `.svg` | `image/svg+xml` |
| `.mp4` | `video/mp4` |
| `.mov` | `video/quicktime` |
| `.webm` | `video/webm` |

`.png` and `.gif` are **measured** — both accepted with a 201. The rest come from GitHub's
documentation of what its web UI accepts; each success would have cost another undeletable
attachment to verify, so they were left as documentation rather than fact.

Do not derive the type with `file --mime-type`. The endpoint checks the type *against the
extension*, so a lookup table keyed by extension is the thing that matches its rule.

### The token

| Source | Use it | Note |
| --- | --- | --- |
| `$GH_TOKEN` | yes | read it first if set |
| `gh auth token` | yes | run it as `env -u GITHUB_TOKEN gh auth token` — `gh` prints `$GITHUB_TOKEN` verbatim when that variable is set, which silently swaps the identity out from under you |
| `$GITHUB_TOKEN` | **no** | in Actions this is an installation token. Its behaviour against this endpoint has never been observed, and the endpoint is irreversible. Use one of the documented fallbacks below in CI |

The token needs **push access** to the repository. Read access is not enough: a repository that can
be read but not pushed to answered 404, identically to one that does not exist.

Keep the token out of `argv` — anything in a command line is visible in `ps` to every user on the
machine:

```bash
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - …
```

## The responses

| Status | Body | Meaning | Measured? |
| --- | --- | --- | --- |
| **201** | `{"url":"https://github.com/user-attachments/assets/<uuid>"}` | done | yes — a real `.png` and a real `.gif` |
| **404** | `{"message":"Not Found"}` | **no access, or no such repository, or `repository_id` missing** | yes — all three causes produce a byte-identical response |
| **422** | `errors[]` with `field` in `content_type`, `name`, `size` | the type or the name was refused | yes — both recorded cases carried **two** complaints at once |
| **400** | `Invalid Content-Type` | no type declared | seen before recording began; never captured |
| **403** | — | possibly abuse detection or a rate limit | **no** — a small probe matrix cannot trigger them |
| anything else | — | unclassified | — |

### The 404 is disjunctive, and must stay that way

Three unrelated causes produce the same bytes. Reporting one of them as *the* cause is a guess
dressed as a diagnosis. Say all three, in the order they are cheap to check:

1. is `repository_id` present, and is it the numeric `id` rather than `node_id`?
2. does the repository exist and is it visible to this token — `gh api repos/OWNER/NAME --jq .id`?
3. does the token have **push** access — `gh api repos/OWNER/NAME --jq .permissions`?

### A 422 can carry two reasons at once

Both recorded rejections did:

```json
{"errors":[
  {"field":"content_type","code":"invalid",
   "message":"content_type is not included in the list of allowed content types"},
  {"field":"name","code":"invalid",
   "message":"name has a file extension that does not match the content type"}
]}
```

That was `.png` sent as `application/octet-stream`, and `.log` sent as `text/plain`. Report every
message in `errors[]`, not the first one — the first alone is usually the less useful half.

A 422 means the bytes did **not** land. Fixing the type or the name and re-sending is safe.

## What to do with each outcome

| Outcome | Bytes landed? | Do |
| --- | --- | --- |
| 201 | yes | read `.url`. Record it — re-uploading the same file makes a second permanent asset |
| 404 | no | check the three causes above. Re-sending unchanged fails identically |
| 422 | no | fix the extension/type pair, then re-send |
| 400 | no | declare a `Content-Type` |
| 403 | **unknown** | stop and report. Do not loop |
| other status | **unknown** | **do not repeat** |
| connection dropped after the body was sent | **unknown** | **do not repeat** |
| connection refused before the body was sent | no | safe to retry |

**Never wrap this call in a generic retry-with-backoff.** A retry is safe only where the table says
the bytes did not land. Anything unknown must be reported to a person, because a repeat can create a
second asset that nobody — including GitHub support — can delete.

## Verifying an upload

The `201` and the URL in its body **are** the confirmation. There is nothing else to check, and the
obvious extra check is actively harmful:

`https://github.com/user-attachments/assets/<uuid>` answers **404 to a direct fetch, permanently.**
Before it is quoted, after it is quoted, in private repositories and public ones alike. It is an
identifier, not a link.

What serves the image is a rewrite performed at **render** time. `body_html` for the comment
contains an `<img>` whose `src` is:

```
https://private-user-images.githubusercontent.com/<uploader user id>/<id>-<uuid>.<ext>?jwt=<signed>
```

with `X-Amz-Expires=300`, regenerated on every render.

An agent that "verifies" by fetching the asset URL gets a 404, concludes the upload failed, and
uploads again — permanently, once per iteration, forever. **A 404 on the asset URL is never evidence
of failure.**

### Who can actually read the file

The signed URL path is scoped by the **uploading user**, not by any repository. During testing, an
asset uploaded against a *private* repository and quoted in a *public* issue was fetched **with no
credentials at all**, returning 200.

| Situation | Effect |
| --- | --- |
| Quoted only in a private repository | only people who can read that comment can obtain a signed link |
| Quoted in a public repository | public, whatever repository it was uploaded against |
| The URL is copied somewhere more public | as public as its new home. Nothing can pull it back |
| Uploaded but quoted nowhere | the repository controls nothing; exposure is decided wherever it eventually gets pasted |

So exposure follows **who can read the comment**, not which repository the bytes were uploaded
against. Never tell anyone an attachment is "a private link".

## Documented fallbacks

The endpoint above is undocumented and can change without notice. When it must not be relied on — in
CI, under an installation token, or after an unexplained failure — two supported paths exist:

### Commit the file to the repository

```bash
git switch -c media/pr-42-evidence
mkdir -p .github/media && cp out.mp4 .github/media/
git add .github/media/out.mp4 && git commit -m "add PR 42 evidence" && git push -u origin HEAD
# reference it as (branch-pinned, or use the commit SHA so it survives a rebase):
#   https://raw.githubusercontent.com/OWNER/REPO/COMMIT_SHA/.github/media/out.mp4
```

| Pro | Con |
| --- | --- |
| Fully documented, works with `GITHUB_TOKEN` | the binary is in the repository's history, forever |
| **Removable** — unlike an attachment | inherits the repository's visibility exactly |
| Stable URL when pinned to a SHA | `raw.githubusercontent.com` video does not get an inline player; it downloads |

### Attach to a release

```bash
gh release create media-2026-08-16 --title "Evidence" --notes "PR 42" out.mp4
gh release upload media-2026-08-16 out.png
```

Documented, deletable, and it keeps binaries out of git history — but releases are a public-facing
surface in a public repository, and a release created for a screenshot is clutter.

Both fallbacks render as links rather than inline players. That is the trade: supported and
reversible, against inline and permanent.

## Provenance

The measurements above come from a live probe run on 2026-08-16 against a private and a public
repository. Not established, and deliberately listed rather than guessed:

- abuse detection and rate limiting;
- installation tokens (`ghs_`);
- a classic PAT without the `repo` scope;
- a 400 with no declared type, captured properly;
- video content types and the real size ceiling — each success costs a permanent artifact;
- a connection dropped after the body has been sent.
