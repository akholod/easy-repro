# The profile

How this repo is started, written down once so the second run asks nothing.

Read from `$(git rev-parse --git-common-dir)/info/repro-profile.json` — untracked, local, nobody's
permission needed, and correct inside a linked worktree, where `.git` is a file rather than a
directory and `.git/info` would not resolve.

```json
{
  "version": 1,
  "baseUrl": "http://localhost:5173",
  "start":   { "command": "pnpm dev", "cwd": "." },
  "ready":   { "url": "http://localhost:5173/", "failure": ["EADDRINUSE", "Failed to compile"] },
  "stop":    { "command": "" }
}
```

| Field | Why it is there |
| --- | --- |
| `baseUrl` | where the app answers. The route to demonstrate comes from the request, not from here — a feature demo of `{baseUrl}/settings/billing` names its own path |
| `start.command`, `start.cwd` | one command, run in one place |
| `ready.url` | polled until it answers. **Never `sleep`** |
| `ready.failure[]` | the highest-value field in the file — see below |
| `stop.command` | may be empty; empty means killing the background task is the defined behaviour |

## `ready.failure[]` earns its place

Without failure markers a wait loop hangs until it times out, and the timeout tells you nothing about
why. With them it exits on the first line that proves the build is not coming.

It also catches the case a port check cannot: **a listening port is not readiness.** A dev server that
binds 5173, prints `ready in 210 ms`, and then fails to compile looks exactly like a healthy server
serving a blank page — and a blank page looks exactly like a real bug. Reporting that as a
reproduction is the expensive mistake this field prevents.

Good markers are the strings the toolchain prints when it gives up: `EADDRINUSE`,
`Failed to compile`, `BUILD FAILURE`, `Dependency ERROR`, `ERR_PNPM`, `Cannot find module`.

## Writing one

**Missing?** Ask **one** `AskUserQuestion`: how is this app started. Rank candidates from
`package.json` scripts, `pom.xml` plugins, a `Makefile`, `docker-compose.yml`, a `Procfile` — and
**execute nothing** while asking. Starting a candidate to find out can rebuild `node_modules`, bind a
port or touch a database, and the point of asking is to avoid exactly that. Write the answer; never
ask again.

**Arrived with a clone?** Then it is a file of shell commands somebody else wrote, and it will be run
on your machine. Confirm it once per machine: show `start.command`, get a yes, record the profile's
hash beside it. Confirmation at authoring time covered the author, not you.

## Not in v1

`setup` (preparing a fresh worktree), `delegate` (one command that supersedes start/ready/stop),
`docs[]` (repo-relative pointers to trap notes), `scaffold`, `capture.kind` and `sourceRoots` belong
to later increments. The six fields above are what a bug or a feature demo needs on an app that
already runs.
