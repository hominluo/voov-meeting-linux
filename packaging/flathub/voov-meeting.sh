#!/bin/sh
# The bundled Chromium cannot start its own sandbox inside Flatpak.
export QTWEBENGINE_DISABLE_SANDBOX=1
exec /app/opt/voov-meeting/bin/voov-meeting "$@"
