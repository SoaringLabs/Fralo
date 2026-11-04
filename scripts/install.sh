#!/bin/bash
# Install the official Fralo release without starting the app.
set -euo pipefail

fail() {
    printf 'fralo-install: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: install.sh [--version VERSION]

Install Fralo to ~/Applications from the latest stable GitHub release,
or pin a release (for example, --version 0.2.0). Apple silicon and macOS 14+
are required. An existing ~/Applications/Fralo.app is left in place.
On success, stdout contains only the full path to the bundled fralo CLI.
EOF
}

version=
case $# in
    0) ;;
    1) case $1 in -h|--help) usage; exit 0 ;; *) fail 'Use --help for usage.' ;; esac ;;
    2) [[ $1 == --version && -n $2 ]] || fail 'Expected --version VERSION.'
       version=${2#v} ;;
    *) fail 'Use --help for usage.' ;;
esac
if [[ $# == 2 && ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail 'Expected a stable release version such as 0.2.0.'
fi

[[ $(/usr/bin/uname -s) == Darwin && $(/usr/bin/uname -m) == arm64 ]] ||
    fail 'Use a native Apple silicon macOS terminal.'
os_version=$(/usr/bin/sw_vers -productVersion)
(( ${os_version%%.*} >= 14 )) || fail 'macOS 14 or later is required.'
[[ ${HOME:-} == /* && $HOME != / && -d $HOME && $HOME != *$'\n'* ]] ||
    fail 'HOME must be an existing absolute user directory.'

install_dir="${HOME%/}/Applications"
app="$install_dir/Fralo.app"
check_destination() {
    if [[ -e $app || -L $app ]]; then
        fail "Already exists: $app. Use Fralo's updater or move this copy before reinstalling."
    fi
}
check_destination

# Use only official HTTPS endpoints and ignore settings in ~/.curlrc.
fetch() {
    /usr/bin/curl -q --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 300 --retry 2 "$@"
}

if [[ -z $version ]]; then
    tag=$(fetch https://api.github.com/repos/SoaringLabs/Fralo/releases/latest |
        /usr/bin/plutil -extract tag_name raw -expect string -o - -- -) ||
        fail 'Could not resolve the latest release. Retry or pass --version VERSION.'
    [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Unexpected release tag: $tag"
    version=${tag#v}
fi

tmp=
staging=
mounted=false
cleanup() {
    if [[ $mounted == true ]]; then
        if ! /usr/bin/hdiutil detach "$tmp/mount" >&2; then
            printf 'fralo-install: Could not detach %s. Its files have been left in place.\n' "$tmp/mount" >&2
            tmp=
        fi
    fi
    [[ -z $staging ]] || /bin/rm -rf -- "$staging"
    [[ -z $tmp ]] || /bin/rm -rf -- "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tmp=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fralo-install.XXXXXXXX")
/bin/mkdir "$tmp/mount"
asset="Fralo-$version-arm64.dmg"
release="https://github.com/SoaringLabs/Fralo/releases/download/v$version"
dmg="$tmp/$asset"

printf 'Downloading Fralo %s…\n' "$version" >&2
fetch -o "$tmp/SHA256SUMS.txt" "$release/SHA256SUMS.txt"
expected=$(/usr/bin/awk -v file="$asset" '
    $2 == file && NF == 2 && length($1) == 64 && $1 ~ /^[[:xdigit:]]+$/ {
        digest = tolower($1); count++
    }
    END { if (count != 1) exit 1; print digest }
' "$tmp/SHA256SUMS.txt") || fail "No unique SHA-256 checksum for $asset."
fetch -o "$dmg" "$release/$asset"
actual=$(/usr/bin/shasum -a 256 "$dmg")
[[ ${actual%% *} == "$expected" ]] || fail "SHA-256 mismatch for $asset."

/usr/sbin/spctl --assess --type open --context context:primary-signature "$dmg" ||
    fail 'Gatekeeper rejected the disk image.'
/usr/bin/hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$tmp/mount" "$dmg" >&2 ||
    fail 'Could not mount the disk image.'
mounted=true
source_app="$tmp/mount/Fralo.app"
[[ -d $source_app && ! -L $source_app && -x $source_app/Contents/MacOS/fralo ]] ||
    fail 'The disk image does not contain Fralo.app with its CLI.'

# Pin the Developer ID team and bundle identity, without pinning a leaf certificate.
requirement='anchor apple generic and identifier "app.fralo.desktop" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "45JA4GW37W"'
/usr/bin/codesign --verify --strict -R "=$requirement" "$source_app" ||
    fail 'The app does not match the expected Fralo signature.'
/usr/sbin/spctl --assess --type execute "$source_app" || fail 'Gatekeeper rejected Fralo.app.'
app_version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -expect string -o - \
    "$source_app/Contents/Info.plist")
[[ $app_version == "$version" ]] || fail "Expected Fralo $version, found $app_version."

# Stage beside the destination to preserve framework symlinks and publish by rename.
/bin/mkdir -p "$install_dir"
staging=$(/usr/bin/mktemp -d "$install_dir/.fralo-install.XXXXXXXX")
/usr/bin/ditto "$source_app" "$staging/Fralo.app"
/usr/bin/codesign --verify --deep --strict "$staging/Fralo.app" ||
    fail 'The copied app failed signature verification.'
/usr/bin/hdiutil detach -quiet "$tmp/mount" >&2 || fail 'Could not detach the disk image.'
mounted=false

check_destination
/bin/mv -n "$staging/Fralo.app" "$install_dir/"
[[ ! -e $staging/Fralo.app ]] || fail "Already exists: $app."

printf '%s\n' "$app/Contents/MacOS/fralo"
