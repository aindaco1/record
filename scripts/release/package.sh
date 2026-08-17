#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/dmg-layout.sh"
artifacts_root="$repo_root/.build/release-artifacts"
app_path="${RECORD_APP_PATH:-$artifacts_root/Record.app}"
zip_path="$artifacts_root/Record.zip"
dmg_path="$artifacts_root/Record.dmg"

if [[ ! -d "$app_path" ]]; then
    echo "missing app bundle; run scripts/release/build-app.sh first" >&2
    exit 1
fi

rm -f "$zip_path" "$dmg_path"
staging_path="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/record-dmg-staging.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$staging_path"
}
trap cleanup EXIT

ditto --norsrc --noextattr "$app_path" "$staging_path/$RECORD_DMG_APP_NAME"
/bin/ln -s "$RECORD_DMG_APPLICATIONS_LINK_TARGET" \
    "$staging_path/$RECORD_DMG_APPLICATIONS_LINK_NAME"
validate_record_dmg_layout "$staging_path"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr -c -k --keepParent \
    "$app_path" "$zip_path"
/usr/bin/hdiutil create -quiet -volname Record -srcfolder "$staging_path" \
    -ov -format UDZO "$dmg_path"
/usr/bin/hdiutil verify "$dmg_path"
cleanup
trap - EXIT

cd "$artifacts_root"
install -m 0644 "$repo_root/Package.resolved" Package.resolved
RECORD_APP_PATH="$app_path" "$repo_root/scripts/release/write-build-metadata.sh"
"$repo_root/scripts/release/checksum-artifacts.sh"

echo "$artifacts_root"
