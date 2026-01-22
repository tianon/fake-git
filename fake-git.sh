#!/usr/bin/env bash
set -Eeuo pipefail

# https://github.com/golang/go/issues/50603

# ideally, *just* enough of a fake Git command to convince go(1) that we are building from a specific tag / version number 🙃
# (this allows running a standard command like `go version -m ./path/to/go/binary` to scrape the version number, which makes it easier for scanning tools to pick up and match against, even if you've excluded ".git" during build via ".dockerignore" or similar)

# NOTE: for this to work, there *must* be a .git directory (which can even be empty) at the root of the repository -- without that, Go won't bother shelling out to "git"

: "${FAKEGIT_GO_SEMVER:?should be set to a Go-compatible semantic version number like v1.2.3}"
: "${FAKEGIT_GO_REVISION:=$FAKEGIT_GO_SEMVER}" # can be set to a different value to change the "vcs.revision" value
: "${FAKEGIT_GO_TIMESTAMP:=0}" # unix timestamp, notably ends up embedded in "vcs.time"
: "${FAKEGIT_GO_MODIFIED=}" # ends up in "vcs.modified" (which is boolean, so this should be empty or non-empty)

# TODO add explicit debugging flag?
#printf 'DEBUG: %s\n' "$*" >> "/proc/$PPID/fd/2"

args="$*"

# handle https://github.com/golang/go/commit/29f3f72dbd67c25033df944c8ced91e0efd46851 / "--end-of-options"
# we aren't actually doing a "real" thing and mostly just look at the shape of our input anyways, so stripping that added flag entirely should be ~fine
args="${args// --end-of-options / }"

case "$args" in
	# our own flag to pre-verify all the inputs, proper "git" override, etc.
	# use via "git --fake" after installing the script into PATH and setting the above variables
	'--fake' | '--help')
		# validate that FAKEGIT_GO_SEMVER actually matches Go's interpretation
		# https://pkg.go.dev/golang.org/x/mod/semver
		# > vMAJOR[.MINOR[.PATCH[-PRERELEASE][+BUILD]]]
		# > - square brackets indicate optional parts of the syntax
		# > - MAJOR, MINOR, and PATCH are decimal integers without extra leading zeros
		# > - PRERELEASE and BUILD are each a series of non-empty dot-separated identifiers using only alphanumeric characters and hyphens
		# > - all-numeric PRERELEASE identifiers must not have leading zeros
		# https://github.com/golang/mod/blob/v0.27.0/semver/semver.go#L178-L231
		intRegex='0|[1-9][0-9]*'
		identifierRegex='[0-9A-Za-z-]+' # TODO if one of these is purely numeric, it needs to not have leading zeros ("intRegex" above, but binding for anything that's numeric-only)
		preReleaseRegex="($identifierRegex)([.]($identifierRegex))*"
		# buildRegex='[0-9A-Za-z-]+([.][0-9A-Za-z-]+)*' # (we can't accept +BUILD because Go rejects the semver if we do)
		# we also cannot let ".MINOR.PATCH" be optional or Go *also* rejects the semver
		semverRegex="($intRegex)[.]($intRegex)[.]($intRegex)(-($preReleaseRegex))?"
		if ! grep <<<"$FAKEGIT_GO_SEMVER" -qE "^v($semverRegex)$"; then
			printf >&2 'error: invalid (Go) semver: %q\n  ("vMAJOR[.MINOR[.PATCH[-PRERELEASE][+BUILD]]]" but not +BUILD)\n' "$FAKEGIT_GO_SEMVER"
			exit 1
		fi

		printf 'semver: %q\n' "$FAKEGIT_GO_SEMVER"
		printf 'revision: %q\n' "$FAKEGIT_GO_REVISION"
		date="$(date --utc --date "@$FAKEGIT_GO_TIMESTAMP" '+%Y-%m-%dT%H:%M:%SZ')"
		printf 'timestamp: %d (%s)\n' "$FAKEGIT_GO_TIMESTAMP" "$date"
		printf 'modified: %q\n' "$FAKEGIT_GO_MODIFIED"
		exit 0
		;;

	# https://github.com/golang/go/blob/608acff8479640b00c85371d91280b64f5ec9594/src/cmd/go/internal/vcs/vcs.go#L333
	'status --porcelain')
		if [ -n "$FAKEGIT_GO_MODIFIED" ]; then
			printf '%s\n' "$FAKEGIT_GO_MODIFIED"
		fi
		exit 0
		;;

	# https://github.com/golang/go/blob/608acff8479640b00c85371d91280b64f5ec9594/src/cmd/go/internal/vcs/vcs.go#L344
	'-c log.showsignature=false log -1 --format=%H:%ct')
		printf '%s:%s\n' "$FAKEGIT_GO_REVISION" "$FAKEGIT_GO_TIMESTAMP"
		exit 0
		;;

	# Go 1.25+
	# https://github.com/golang/go/commit/76f63ee890170f4884f4d213e8150d39d6758ad3
	# https://github.com/golang/go/blob/9d0829963ccab19093c37f21cfc35d019addc78a/src/cmd/go/internal/modfetch/codehost/git.go#L391
	# for https://github.com/golang/go/blob/9d0829963ccab19093c37f21cfc35d019addc78a/src/cmd/go/internal/modfetch/codehost/git.go#L397-L414
	'config extensions.objectformat')
		exit 0
		;;

	# https://github.com/golang/go/blob/608acff8479640b00c85371d91280b64f5ec9594/src/cmd/go/internal/modfetch/codehost/git.go#L153
	# via https://github.com/golang/go/blob/608acff8479640b00c85371d91280b64f5ec9594/src/cmd/go/internal/modfetch/codehost/git.go#L400-L414
	'tag -l')
		printf '%s\n' "$FAKEGIT_GO_SEMVER" "$FAKEGIT_GO_REVISION"
		exit 0
		;;

	# https://github.com/golang/go/blob/608acff8479640b00c85371d91280b64f5ec9594/src/cmd/go/internal/modfetch/codehost/git.go#L605C138-L605C138
	# this has "*" because we treat $FAKEGIT_GO_SEMVER *and* $FAKEGIT_GO_REVISION as tags (see "tag -l" above), so it does a lookup for both and we need to be consistent that $FAKEGIT_GO_SEMVER is the "canonical" tag for our revision (because "$FAKEGIT_GO_REVISION" is our "commit hash" too)
	'-c log.showsignature=false log --no-decorate -n1 --format=format:%H %ct %D refs/tags/'*' --')
		printf '%s %d HEAD, tag: %s\n' "$FAKEGIT_GO_REVISION" "$FAKEGIT_GO_TIMESTAMP" "$FAKEGIT_GO_SEMVER"
		exit 0
		;;

	# https://github.com/golang/go/blob/608acff8479640b00c85371d91280b64f5ec9594/src/cmd/go/internal/modfetch/codehost/git.go#L695
	'cat-file blob '"$FAKEGIT_GO_REVISION"':'*)
		file="${3#$FAKEGIT_GO_REVISION:}"
		cat "$file"
		exit 0
		;;
esac

wip="$(
	printf 'ERROR: UNIMPLEMENTED "git" command invoked:\n'
	printf '  $*: %s\n' "$args"
	printf '  $@:'
	printf ' %q' "$@"
	printf '\n'
)"
cat <<<"$wip" >> /dev/stderr || :
cat <<<"$wip" >> "/proc/$PPID/fd/2" || :
kill -9 "$PPID" || :
exit 99
