#!/bin/bash
# Install the official Fralo release without starting the app.
set -euo pipefail

fail() {
    printf 'fralo-install: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: install.sh [--version VERSION] [--bin-dir DIRECTORY] [--uninstall-cli]

Install Fralo to ~/Applications from the latest stable GitHub release,
or pin a release (for example, --version 0.2.0). Apple silicon and macOS 14+
are required. An existing official ~/Applications/Fralo.app is reused.

The fralo command is installed in /usr/local/bin (may request an administrator
password). --bin-dir selects another absolute directory already on PATH.
Shell profiles are never changed. --uninstall-cli removes only our launcher.
On installation success, stdout contains only the full bundled CLI path.
EOF
}

version=
bin_dir=/usr/local/bin
uninstall_cli=false
while (( $# )); do
    case $1 in
        -h|--help) usage; exit 0 ;;
        --version|--bin-dir)
            (( $# >= 2 )) && [[ -n $2 ]] || fail "Missing value for $1."
            case $1 in
                --version) version=${2#v} ;;
                --bin-dir) bin_dir=$2 ;;
            esac
            shift 2 ;;
        --uninstall-cli) uninstall_cli=true; shift ;;
        *) fail 'Use --help for usage.' ;;
    esac
done
if [[ -n $version && ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail 'Expected a stable release version such as 0.3.1.'
fi
[[ $uninstall_cli == false || -z $version ]] || fail '--uninstall-cli cannot be combined with --version.'
[[ $bin_dir == /* && $bin_dir != / && $bin_dir != *$'\n'* ]] ||
    fail '--bin-dir must be an absolute directory other than /.'
bin_dir=${bin_dir%/}

[[ $(/usr/bin/uname -s) == Darwin && $(/usr/bin/uname -m) == arm64 ]] ||
    fail 'Use a native Apple silicon macOS terminal.'
os_version=$(/usr/bin/sw_vers -productVersion)
(( ${os_version%%.*} >= 14 )) || fail 'macOS 14 or later is required.'
[[ ${HOME:-} == /* && $HOME != / && -d $HOME && $HOME != *$'\n'* ]] ||
    fail 'HOME must be an existing absolute user directory.'

install_dir="${HOME%/}/Applications"
app="$install_dir/Fralo.app"
launcher="$bin_dir/fralo"
cli="$app/Contents/MacOS/fralo"

# A real invocation of the bundled executable preserves Bundle.main resource lookup.
# A symlink can print --version but fail when rendering bundled backgrounds.
launcher_text() (
    # Keep ownership comparison stable for non-ASCII HOME paths across locales.
    export LC_ALL=C
    printf '#!/bin/bash\n# Fralo CLI launcher v1\ncli=%q\n' "$cli"
    cat <<'EOF'
if [[ ! -x $cli ]]; then
    printf 'fralo: App CLI not found: %s. Reinstall Fralo or rerun its installer.\n' "$cli" >&2
    exit 127
fi
exec "$cli" "$@"
EOF
)
ours() {
    [[ -f $launcher && ! -L $launcher ]] &&
        /usr/bin/cmp -s "$launcher" <(launcher_text)
}

# Only the small launcher operation can elevate; downloads and app validation do not.
needs_sudo=false
bin_command() {
    if [[ $needs_sudo == true ]]; then /usr/bin/sudo "$@"; else "$@"; fi
}
prepare_bin_access() {
    local parent=$bin_dir
    while [[ ! -e $parent ]]; do parent=${parent%/*}; parent=${parent:-/}; done
    [[ -d $parent ]] || fail "Not a directory: $parent"
    if [[ ! -w $parent ]]; then
        printf 'Installing/removing %s requires administrator access.\n' "$launcher" >&2
        /usr/bin/sudo -v || fail 'Administrator access was not granted; no command was installed or removed.'
        needs_sudo=true
    fi
}
if [[ $uninstall_cli == true ]]; then
    if [[ ! -e $launcher && ! -L $launcher ]]; then
        printf 'No Fralo launcher at %s.\n' "$launcher" >&2
        exit 0
    fi
    ours || fail "Refusing to remove a command not created by this installer: $launcher"
    prepare_bin_access
    bin_command /bin/rm -- "$launcher"
    printf 'Removed %s. Fralo.app and settings were kept.\n' "$launcher" >&2
    exit 0
fi

# A child shell cannot add PATH entries to the terminal that invoked curl | sh.
case :${PATH:-}: in
    *:"$bin_dir":*) ;;
    *) fail "$bin_dir is not on PATH. Add it to your shell PATH, open a new terminal, and rerun; or use --bin-dir with a directory already on PATH." ;;
esac
if [[ -e $launcher || -L $launcher ]]; then
    ours || fail "Refusing to overwrite an existing command: $launcher"
fi
found=$(command -v fralo || true)
[[ -z $found || $found == "$launcher" ]] ||
    fail "Another fralo command is already on PATH: $found. Resolve it before installing."
if ! ours; then prepare_bin_access; fi

# Pin the Developer ID team and bundle identity, without pinning a leaf certificate.
requirement='anchor apple generic and identifier "app.fralo.desktop" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "45JA4GW37W"'
verify_app() {
    local candidate=$1
    [[ -d $candidate && ! -L $candidate && -x $candidate/Contents/MacOS/fralo ]] ||
        fail "Not a Fralo app with its CLI: $candidate"
    /usr/bin/codesign --verify --strict -R "=$requirement" "$candidate" ||
        fail 'The app does not match the expected Fralo signature.'
    /usr/sbin/spctl --assess --type execute "$candidate" || fail 'Gatekeeper rejected Fralo.app.'
    app_version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -expect string -o - \
        "$candidate/Contents/Info.plist")
    [[ -z $version || $app_version == "$version" ]] ||
        fail "Expected Fralo $version, found $app_version. Use the app updater or move this copy before reinstalling."
}

# Use only official HTTPS endpoints and ignore settings in ~/.curlrc.
fetch() {
    /usr/bin/curl -q --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 300 --retry 2 "$@"
}

install_app() {
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

    verify_app "$source_app"

    # Stage beside the destination to preserve framework symlinks and publish by rename.
    /bin/mkdir -p "$install_dir"
    staging=$(/usr/bin/mktemp -d "$install_dir/.fralo-install.XXXXXXXX")
    /usr/bin/ditto "$source_app" "$staging/Fralo.app"
    /usr/bin/codesign --verify --deep --strict "$staging/Fralo.app" ||
        fail 'The copied app failed signature verification.'
    /usr/bin/hdiutil detach -quiet "$tmp/mount" >&2 || fail 'Could not detach the disk image.'
    mounted=false

    [[ ! -e $app && ! -L $app ]] || fail "Already exists: $app."
    /bin/mv -n "$staging/Fralo.app" "$install_dir/"
    [[ ! -e $staging/Fralo.app ]] || fail "Already exists: $app."
}

# Re-running the installer adds/repairs the command without replacing a user's app.
if [[ -e $app || -L $app ]]; then
    verify_app "$app"
    printf 'Using installed Fralo %s. Use the app updater for newer versions.\n' "$app_version" >&2
else
    install_app
fi

if ! ours; then
    # Stage on the destination filesystem, then link without replacing any existing
    # name. This also refuses files/symlinks created after the preflight check.
    publish_script=$(cat <<'EOF'
set -euo pipefail
bin_dir=$1
launcher=$2
/bin/mkdir -p "$bin_dir"
staged=$(/usr/bin/mktemp "$bin_dir/.fralo-cli.XXXXXXXX")
trap '/bin/rm -f -- "$staged"' EXIT
/bin/cat > "$staged"
/bin/chmod 755 "$staged"
/bin/link "$staged" "$launcher"
EOF
)
    launcher_text | bin_command /bin/bash -c "$publish_script" fralo-install "$bin_dir" "$launcher" ||
        fail "Could not install $launcher. Fralo.app was kept; fix the command destination and rerun."
fi
[[ $(command -v fralo) == "$launcher" ]] || fail 'The installed command is not the first fralo on PATH.'
"$launcher" --version >&2 || fail 'The installed fralo command could not start.'
printf 'Ready: fralo --help\n' >&2
printf '%s\n' "$cli"
