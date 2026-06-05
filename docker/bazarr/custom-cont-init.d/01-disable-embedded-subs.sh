#!/usr/bin/with-contenv bash
# shellcheck shell=bash
#
# Disable embedded subtitles usage in Bazarr.
#
# When use_embedded_subs is true, Bazarr considers a media file
# "covered" if it has ANY embedded subtitles, even if they're in the
# wrong language (e.g. only Japanese subs for a Spanish user).
#
# Setting it to false forces Bazarr to always search external
# subtitle providers regardless of embedded subs.
#
# linuxserver.io runs scripts from /custom-cont-init.d/ at startup
# before the main application starts. This runs on every container
# start, so it survives Bazarr config changes via the UI.

CONFIG_FILE="/config/config/config.yaml"

if [ -f "$CONFIG_FILE" ]; then
    if grep -q "use_embedded_subs:" "$CONFIG_FILE"; then
        sed -i 's/use_embedded_subs:.*/use_embedded_subs: false/' "$CONFIG_FILE"
    else
        echo "use_embedded_subs: false" >> "$CONFIG_FILE"
    fi
fi
