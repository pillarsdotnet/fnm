<!--
Copyright (c) 2026 Robert August Vincent II <pillarsdotnet@gmail.com>
Co-author: Claude Code.
-->

# `fnm`, packaged for Ubuntu

[`fnm`](https://github.com/Schniz/fnm) is a fast Node.js version manager. No
Ubuntu or Debian archive carries it, so this repository packages it for the
[package registry](https://forgejo.bobbalisa.org/pillarsdotnet/-/packages) on
`forgejo.bobbalisa.org`, for `noble`, `resolute` and `stonking`.

Unlike the `helm` and `vale` packages, which repack an upstream release
binary, this one is a real source build: `debian/changelog` names the upstream
tag, `debian/make-orig-tarballs.sh` produces the source tarball and a vendor
tarball holding every crate in the lock, and the builders compile it with no
network. Each series therefore builds separately, because the binary links
that series' `libc` and `liblzma`.

Only `debian/` and `.forgejo/` are tracked. The rest of this directory is a
working copy of upstream's source at the packaged tag, which `.gitignore`
keeps out of git along with the tarballs and build artifacts.

## What the packaging changes

`debian/patches` moves the dependency set off the versions 1.39.0 released
with, which carried 25 advisories, one of them critical:

- `0002` refreshes `Cargo.lock` to the semver-compatible fixes, clearing 22 of
  them, `tar` and `ring` among them — the crates that unpack downloaded
  Node.js tarballs and verify the release server's certificate.
- `0001` takes `zip` 9 for the remaining three, which have no fix in the 2.x
  series upstream asks for, and adjusts the two call sites `zip` 9 made
  fallible.

Upstream's own test suite passes against the result, all 30 tests.

## Taking a new upstream release

Bump `debian/changelog` to the new upstream version, keeping the `~ppaN`
packaging revision, and push to `main`: the Registry workflow clones the tag,
rebuilds the tarballs and uploads one package per series. Rebuilding an
unchanged changelog is harmless — the registry answers `409` for a version it
already holds.

Re-read `debian/patches` against the new release first: a refreshed lock is
only as good as the release it was resolved for, and `quilt` will say if a
patch no longer applies.
