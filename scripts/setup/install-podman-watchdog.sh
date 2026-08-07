#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
current_uid="$(id -u)"
current_user="$(id -un)"
user_home="$(/usr/bin/dscl . -read "/Users/$current_user" NFSHomeDirectory \
    | /usr/bin/awk '{ print $2 }')"
support_dir="$user_home/Library/Application Support/RecordDevelopment"
logs_dir="$user_home/Library/Logs/RecordDevelopment"
launch_agents_dir="$user_home/Library/LaunchAgents"
watchdog_path="$support_dir/podman-watchdog.sh"
launch_agent_path="$launch_agents_dir/com.aindaco.record.podman-machine.plist"
launch_agent_label="com.aindaco.record.podman-machine"
temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR%/}/record-podman.XXXXXX")"
temporary_plist="$temporary_dir/$launch_agent_label.plist"

cleanup() {
    /bin/rm -rf "$temporary_dir"
}
trap cleanup EXIT

/bin/mkdir -p "$support_dir" "$logs_dir" "$launch_agents_dir"
/usr/bin/install -m 700 "$script_dir/podman-watchdog.sh" "$watchdog_path"

/usr/bin/plutil -create xml1 "$temporary_plist"
/usr/bin/plutil -insert Label -string "$launch_agent_label" "$temporary_plist"
/usr/bin/plutil -insert ProgramArguments -json "[\"$watchdog_path\"]" \
    "$temporary_plist"
/usr/bin/plutil -insert RunAtLoad -bool true "$temporary_plist"
/usr/bin/plutil -insert StartInterval -integer 300 "$temporary_plist"
/usr/bin/plutil -insert ThrottleInterval -integer 30 "$temporary_plist"
/usr/bin/plutil -insert AbandonProcessGroup -bool true "$temporary_plist"
/usr/bin/plutil -insert ProcessType -string Background "$temporary_plist"
/usr/bin/plutil -insert StandardOutPath -string \
    "$logs_dir/podman-watchdog.log" "$temporary_plist"
/usr/bin/plutil -insert StandardErrorPath -string \
    "$logs_dir/podman-watchdog.log" "$temporary_plist"
/usr/bin/install -m 600 "$temporary_plist" "$launch_agent_path"

/bin/launchctl bootout "gui/$current_uid" "$launch_agent_path" \
    >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$current_uid" "$launch_agent_path"
/bin/launchctl kickstart -k "gui/$current_uid/$launch_agent_label"

echo "installed $launch_agent_label"
