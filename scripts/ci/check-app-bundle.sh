#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-Record.app>" >&2
    exit 64
fi

app_path="$1"
if [[ ! -d "$app_path" || -L "$app_path" ]]; then
    echo "missing or unsafe app bundle: $app_path" >&2
    exit 1
fi

required_executable="$app_path/Contents/MacOS/record"
if [[ ! -x "$required_executable" || -L "$required_executable" ]]; then
    echo "missing or unsafe Record executable" >&2
    exit 1
fi

required_directory="$app_path/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$required_directory" || -L "$required_directory" ]]; then
    echo "missing or unsafe app directory: $required_directory" >&2
    exit 1
fi
model_downloader="$app_path/Contents/XPCServices/RecordModelDownloader.xpc"
model_downloader_executable="$model_downloader/Contents/MacOS/record-model-downloader"
model_downloader_info="$model_downloader/Contents/Info.plist"
if [[ ! -d "$model_downloader" || -L "$model_downloader" || \
      ! -x "$model_downloader_executable" || -L "$model_downloader_executable" || \
      ! -f "$model_downloader_info" || -L "$model_downloader_info" ]]; then
    echo "missing or unsafe Record model downloader XPC service" >&2
    exit 1
fi

required_files=(
    "$app_path/Contents/Info.plist"
    "$app_path/Contents/Resources/Record.icns"
    "$app_path/Contents/Resources/Shutter.mp3"
    "$app_path/Contents/Resources/record-macwhisper"
    "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
    "$app_path/Contents/Resources/Licenses/Record-MIT.txt"
    "$app_path/Contents/Resources/Licenses/Swift-Argument-Parser-Apache-2.0.txt"
    "$app_path/Contents/Resources/Licenses/FluidAudio-Apache-2.0.txt"
    "$app_path/Contents/Resources/Licenses/Sparkle.txt"
)
for required_file in "${required_files[@]}"; do
    if [[ ! -f "$required_file" || -L "$required_file" ]]; then
        echo "missing or unsafe app file: $required_file" >&2
        exit 1
    fi
done
if [[ ! -x "$app_path/Contents/Resources/record-macwhisper" ]]; then
    echo "Record MacWhisper helper is not executable" >&2
    exit 1
fi
shutter_hash="$(/usr/bin/shasum -a 256 "$app_path/Contents/Resources/Shutter.mp3" | /usr/bin/awk '{print $1}')"
if [[ "$shutter_hash" != "fd2839e68a7787f849843116d6d4dea5aeef8f4d82419278a573200948aa3d91" ]]; then
    echo "bundled shutter sound failed its documented SHA-256 check" >&2
    exit 1
fi

/usr/bin/plutil -lint "$app_path/Contents/Info.plist" >/dev/null
assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/bin/plutil -extract "$key" raw -o - "$app_path/Contents/Info.plist")"
    if [[ "$actual" != "$expected" ]]; then
        echo "expected $key=$expected, found: $actual" >&2
        exit 1
    fi
}

assert_plist_value CFBundleDisplayName Record
assert_plist_value CFBundleExecutable record
assert_plist_value CFBundleIconFile Record.icns
assert_plist_value CFBundleIdentifier com.aindaco.record
assert_plist_value CFBundlePackageType APPL
assert_plist_value NSPrincipalClass NSApplication
assert_plist_value NSUserNotificationAlertStyle alert
assert_plist_value SUFeedURL \
    https://github.com/aindaco1/record/releases/latest/download/appcast.xml
assert_plist_value SUPublicEDKey SmB+aHRo7wfeJAr21p/IlXiDylp6ObIt/uorKzAZfFU=

if /usr/bin/plutil -extract NSCameraUsageDescription raw -o - \
    "$app_path/Contents/Info.plist" >/dev/null 2>&1
then
    echo "Record must not declare unused camera access" >&2
    exit 1
fi

for key in \
    SUEnableAutomaticChecks \
    SUEnableDownloaderService \
    SUEnableInstallerLauncherService \
    SURequireSignedFeed \
    SUVerifyUpdateBeforeExtraction
do
    assert_plist_value "$key" true
done

for key in \
    SUAllowsAutomaticUpdates \
    SUAutomaticallyUpdate \
    SUEnableSystemProfiling
do
    assert_plist_value "$key" false
done
assert_plist_value LSUIElement true

assert_model_downloader_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/bin/plutil -extract "$key" raw -o - "$model_downloader_info")"
    if [[ "$actual" != "$expected" ]]; then
        echo "expected model downloader $key=$expected, found: $actual" >&2
        exit 1
    fi
}

assert_model_downloader_value CFBundleExecutable record-model-downloader
assert_model_downloader_value CFBundleIdentifier com.aindaco.record.model-downloader
assert_model_downloader_value CFBundlePackageType 'XPC!'
assert_model_downloader_value LSMinimumSystemVersion 15.0
assert_model_downloader_value XPCService.ServiceType Application
assert_model_downloader_value CFBundleShortVersionString \
    "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - \
        "$app_path/Contents/Info.plist")"
assert_model_downloader_value CFBundleVersion \
    "$(/usr/bin/plutil -extract CFBundleVersion raw -o - \
        "$app_path/Contents/Info.plist")"

architectures="$(/usr/bin/lipo -archs "$required_executable")"
if [[ "$architectures" != "arm64" ]]; then
    echo "expected an arm64-only app binary, found: $architectures" >&2
    exit 1
fi
model_downloader_architectures="$(/usr/bin/lipo -archs "$model_downloader_executable")"
if [[ "$model_downloader_architectures" != "arm64" ]]; then
    echo "expected an arm64-only model downloader, found: $model_downloader_architectures" >&2
    exit 1
fi
