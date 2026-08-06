#!/bin/sh
set -eu

macwhisper_cli='/Applications/MacWhisper.app/Contents/MacOS/mw'
expected_team_id='8Q7TMPA46J'

if ! /usr/bin/codesign --verify --strict "$macwhisper_cli"; then
    echo 'MacWhisper CLI signature validation failed' >&2
    exit 126
fi
team_id=$(/usr/bin/codesign -dv --verbose=4 "$macwhisper_cli" 2>&1 \
    | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2}')
if [ "$team_id" != "$expected_team_id" ]; then
    echo "unexpected MacWhisper CLI signing team: $team_id" >&2
    exit 126
fi

# Bound a wedged CLI without constraining normal long-recording throughput.
# POSIX alarm timers survive exec; the signal disposition resets to default.
exec /usr/bin/perl -e 'alarm shift; exec {$ARGV[0]} @ARGV; die $!' \
    1800 "$macwhisper_cli" "$@"
