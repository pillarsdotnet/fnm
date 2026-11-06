#!/bin/sh
# Copyright (c) 2026 Robert August Vincent II <pillarsdotnet@gmail.com>
# Co-author: Claude Code.
#
# Build the two upstream tarballs for the fnm Debian source package from an
# upstream git clone, and regenerate debian/copyright's vendored-crate
# section to match:
#
#   ../fnm_<ver>.orig.tar.xz         upstream at the release tag
#   ../fnm_<ver>.orig-vendor.tar.xz  every crate in Cargo.lock
#
# Launchpad's builders have no network, so the crates travel with the source.
# Crates that only build on Windows, macOS or WebAssembly are reduced to their
# Cargo.toml and an empty lib.rs: cargo still needs their manifests to resolve
# Cargo.lock, but nothing on Linux compiles them.
#
# Unlike timesheet, fnm is third-party: the packaging tree holds no .git, so
# the upstream clone and release tag are arguments. Run from the packaging
# tree, with network access; prints the upstream version for debian/changelog.
#
# Needs patch(1) as well, to apply debian/patches before vendoring.
#
# Usage: debian/make-orig-tarballs.sh <upstream-clone> <tag>
#    eg: git clone https://github.com/Schniz/fnm.git /tmp/fnm-src
#        debian/make-orig-tarballs.sh /tmp/fnm-src v1.39.0
set -eu

tree=$(pwd)
clone=$(realpath "$1")
tag="$2"
ver="${tag#v}"

git -C "$clone" archive --format=tar --prefix="fnm-$ver/" "$tag" \
  | xz -9 -T0 > "../fnm_$ver.orig.tar.xz"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git -C "$clone" archive "$tag" | tar -x -C "$work"

# Vendor what the build will actually compile, not what upstream shipped:
# debian/patches moves Cargo.toml and Cargo.lock, and dh_auto_build runs
# cargo with --frozen, so a vendor set made from the unpatched lock would
# hold the wrong crate versions and fail the build.
if [ -f "$tree/debian/patches/series" ]; then
  while read -r patch_name; do
    case "$patch_name" in "" | \#*) continue ;; esac
    patch -d "$work" -p1 --quiet < "$tree/debian/patches/$patch_name"
  done < "$tree/debian/patches/series"
fi

(cd "$work" && cargo vendor --locked --quiet vendor > /dev/null)

python3 - "$work/vendor" "$tree/debian/copyright" <<'PY'
import collections, json, os, re, shutil, sys, tomllib

vendor, copyright_path = sys.argv[1], sys.argv[2]

# Stub the crates that only build for Windows, macOS or WebAssembly.
foreign = re.compile(r"^(windows.*|objc2.*|block2|dispatch2"
                     r"|wasi.*|wasm.*|wit-.*|js-sys|web-sys)$")
for name in sorted(os.listdir(vendor)):
    if not foreign.match(name):
        continue
    crate = os.path.join(vendor, name)
    with open(os.path.join(crate, ".cargo-checksum.json")) as f:
        package_sum = json.load(f)["package"]
    for entry in os.listdir(crate):
        if entry == "Cargo.toml":
            continue
        path = os.path.join(crate, entry)
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
    os.makedirs(os.path.join(crate, "src"))
    with open(os.path.join(crate, "src", "lib.rs"), "w") as f:
        f.write("// Stubbed for the Debian package: this crate only builds "
                "for non-Linux targets.\n")
    with open(os.path.join(crate, ".cargo-checksum.json"), "w") as f:
        json.dump({"files": {}, "package": package_sum}, f)

# Group the crates by license, for debian/copyright.
def dep5(expr):
    expr = expr.replace("/", " OR ")
    expr = expr.replace("Apache-2.0 WITH LLVM-exception", "Apache-2.0-with-LLVM-exception")
    expr = expr.replace("-or-later", "+")
    # "(A OR B) AND C" is written "A or B, and C" in DEP-5.
    expr = re.sub(r"\)\s+AND\s+", ", and ", expr)
    expr = re.sub(r"\s+AND\s+\(", ", and ", expr)
    expr = expr.replace("(", "").replace(")", "")
    expr = re.sub(r"\s+OR\s+", " or ", expr)
    expr = re.sub(r"\s+AND\s+", " and ", expr)
    # Sort a plain "or" list, so equivalent licenses share one paragraph.
    if " and " not in expr:
        expr = " or ".join(sorted(expr.split(" or ")))
    return expr

# Crates with a license-file instead of a license expression, named by hand;
# each needs a matching stand-alone License paragraph in debian/copyright.
LICENSE_FILE_CRATES = {"ring": "ring"}

groups = collections.defaultdict(list)
for name in sorted(os.listdir(vendor)):
    with open(os.path.join(vendor, name, "Cargo.toml"), "rb") as f:
        package = tomllib.load(f)["package"]
    lic = package.get("license") or LICENSE_FILE_CRATES.get(name, "UNKNOWN")
    groups[dep5(lic)].append(name)

# Replace the vendor/ paragraphs, keeping every other paragraph in place;
# the generated ones go before the first stand-alone License paragraph.
with open(copyright_path) as f:
    paragraphs = f.read().strip("\n").split("\n\n")
kept = [p for p in paragraphs if not p.startswith("Files: vendor/")]
at = next(i for i, p in enumerate(kept) if p.startswith("License:"))
generated = [
    "Files: " + "\n ".join(f"vendor/{c}/*" for c in crates)
    + "\nCopyright: the authors of each crate, as listed in its Cargo.toml"
    + f"\nLicense: {license}"
    for license, crates in sorted(groups.items())
]
with open(copyright_path, "w") as f:
    f.write("\n\n".join(kept[:at] + generated + kept[at:]) + "\n")
PY

tar --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime="$(git -C "$clone" log -1 --format=%cI "$tag")" -C "$work" -cf - vendor \
  | xz -9 -T0 > "../fnm_$ver.orig-vendor.tar.xz"

echo "$ver"
