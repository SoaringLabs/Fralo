#!/bin/sh
# Keep the commands in one block so a partial response cannot start installation.
{
    installer=$(/usr/bin/curl -qfsSL --proto '=https' --proto-redir '=https' \
        https://raw.githubusercontent.com/SoaringLabs/Fralo/main/scripts/install.sh) || exit "$?"
    if [ -z "$installer" ]; then
        printf 'fralo-install: The installer download is empty.\n' >&2
        exit 1
    fi
    exec /bin/bash -c "$installer" fralo-install "$@"
}
