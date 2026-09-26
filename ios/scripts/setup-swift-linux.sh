#!/usr/bin/env bash
# Puts the pinned Swift release on PATH for the Linux core tests, without root,
# the way setup-node puts Node on a runner:
# - Downloaded once from swift.org into the runner's tool cache, which a
#   self-hosted runner keeps between jobs.
# - Then checked with a one-file build. A runner missing Swift's system
#   packages gets the one command that fixes it, instead of a failure deep in
#   `swift test`.
#
# Used by .github/workflows/ios-core.yml when the runner has no Docker.
# Needs SWIFT_VERSION (e.g. 6.4), RUNNER_TOOL_CACHE, RUNNER_TEMP and GITHUB_PATH.
set -euo pipefail

version="${SWIFT_VERSION:?set SWIFT_VERSION, e.g. 6.4}"
cache="${RUNNER_TOOL_CACHE:?}/swift/$version"
# What swift.org lists for Ubuntu, with build-essential standing in for the
# gcc-version-specific libgcc and libstdc++ packages.
packages="build-essential gnupg2 libcurl4-openssl-dev libedit2 libncurses-dev libpython3-dev libsqlite3-0 libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev"

# shellcheck source=/dev/null
. /etc/os-release
case "$(uname -m)" in
  x86_64) arch="" ;;
  aarch64 | arm64) arch="-aarch64" ;;
  *) echo "::error::swift.org has no Linux build of Swift for $(uname -m)."; exit 1 ;;
esac
# The matching build first, then the nearest older one.
case "${ID:-}-${VERSION_ID:-}" in
  ubuntu-26.04) platforms="ubuntu26.04 ubuntu24.04" ;;
  ubuntu-24.04) platforms="ubuntu24.04" ;;
  ubuntu-22.04) platforms="ubuntu22.04" ;;
  debian-12) platforms="debian12" ;;
  *) echo "::error::No Swift $version build is set up here for ${PRETTY_NAME:-this system}."; exit 1 ;;
esac

toolchain=""
for platform in $platforms; do
  dir="$cache/$platform$arch"
  if [ -e "$dir/.complete" ]; then
    toolchain="$dir"
    break
  fi
  # ubuntu24.04 -> https://download.swift.org/swift-6.4-release/ubuntu2404/swift-6.4-RELEASE/swift-6.4-RELEASE-ubuntu24.04.tar.gz
  url="https://download.swift.org/swift-$version-release/${platform//./}$arch/swift-$version-RELEASE/swift-$version-RELEASE-$platform$arch.tar.gz"
  download="$(mktemp -d "$RUNNER_TEMP/swift-download.XXXXXX")"
  echo "Downloading $url"
  if curl --fail --location --silent --show-error --proto '=https' --output "$download/swift.tar.gz" "$url"; then
    # Unpacked next to its final place and renamed only once complete, so a job
    # cancelled halfway never leaves a toolchain that looks usable.
    rm -rf "$dir" "$dir.partial"
    mkdir -p "$dir.partial"
    tar -xzf "$download/swift.tar.gz" -C "$dir.partial" --strip-components=1
    touch "$dir.partial/.complete"
    mv "$dir.partial" "$dir"
    rm -rf "$download"
    toolchain="$dir"
    break
  fi
  rm -rf "$download"
done
if [ -z "$toolchain" ]; then
  echo "::error::Could not download Swift $version for ${PRETTY_NAME:-this system} from swift.org."
  exit 1
fi

bin="$toolchain/usr/bin"
probe="$(mktemp -d "$RUNNER_TEMP/swift-probe.XXXXXX")"
printf 'import Foundation\nprint(Date.distantPast < Date())\n' > "$probe/main.swift"
if ! { "$bin/swiftc" "$probe/main.swift" -o "$probe/main" && "$probe/main" && "$bin/swift" package --version; } > "$probe/log" 2>&1; then
  cat "$probe/log"
  echo "::error::Swift $version is unpacked in $toolchain but cannot build here: this runner lacks Swift's system packages."
  echo "::error::Install them once, as root: sudo apt-get install -y $packages"
  exit 1
fi
rm -rf "$probe"
echo "$bin" >> "$GITHUB_PATH"
"$bin/swift" --version
