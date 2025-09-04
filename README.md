# Fake Git (for Go)

Ever done `go build` inside a `Dockerfile` with `.git` appropriately in `.dockerignore`, and wished Go's `-buildvcs=true` in Go 1.24+ could still embed a useful version number?

Well, if you've got an alternate way to get what the version number should be (embedded in a file, in the code, an environment variable / `Dockerfile` build `ARG`, etc), this might be the project for you!

Install `fake-git.sh` as `git` in `PATH` before your real `git` binary (or instead of installing `git`), and set the following environment variables before invoking `go build -buildvcs=true` (or `=auto`):

- `FAKEGIT_GO_SEMVER`  
  the actual semantic version number you want embedded in the build metadata; must match [Go's `vMAJOR[.MINOR[.PATCH[-PRERELEASE][+BUILD]]]`](https://pkg.go.dev/golang.org/x/mod/semver), but importantly without `+BUILD` (as Go won't accept build numbers in Git tags)

- `FAKEGIT_GO_REVISION` (optional)  
  defaults to `FAKEGIT_GO_SEMVER`; controls `vcs.revision`

- `FAKEGIT_GO_TIMESTAMP` (optional)  
  defaults to `0`; controls `vcs.time` and must be a Unix timestamp (ie, seconds since `1970-01-01T00:00:00Z`)

- `FAKEGIT_GO_MODIFIED` (optional)  
  defaults to `""`; controls `vcs.modified`, set to non-empty to set to `true`

After setting those, you can use `git --fake` to verify that they're probably correct and will likely work (and that you've properly shadowed/provided `git` in `PATH`).

See [`Dockerfile.test` in this repository](Dockerfile.test) for a full working example (that also tests/verifies the result).

## Caveat

The most important caveat here is that this is all *really* hacky, and prone to breakage at any/every turn.  The Go project's implementation has been reasonably stable, but they could completely change how they implement this at any time and fully break this project (and I obviously cannot control that).
