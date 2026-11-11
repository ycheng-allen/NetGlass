#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NETGLASS_SIGN_IDENTITY:?Set NETGLASS_SIGN_IDENTITY to your Developer ID Application identity}"
: "${NETGLASS_TEAM_ID:?Set NETGLASS_TEAM_ID to your Apple team ID}"
: "${NETGLASS_APP_PROFILE:?Set NETGLASS_APP_PROFILE to the app provisioning profile path}"
: "${NETGLASS_FILTER_PROFILE:?Set NETGLASS_FILTER_PROFILE to the filter provisioning profile path}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
bash build.sh
extension_path="build/NetGlass.app/Contents/Library/SystemExtensions/com.allen.netglass.filter.systemextension"
mkdir -p "$extension_path/Contents/MacOS"
xcrun swiftc -O -module-name NetGlassFilter Extension/*.swift Shared/*.swift -target arm64-apple-macos15.0 -o "$extension_path/Contents/MacOS/NetGlassFilter"
python3 - <<'PY'
import plistlib, os
from pathlib import Path
team = os.environ['NETGLASS_TEAM_ID']
ext = Path('build/NetGlass.app/Contents/Library/SystemExtensions/com.allen.netglass.filter.systemextension/Contents')
info = dict(CFBundleIdentifier='com.allen.netglass.filter', CFBundleName='NetGlassFilter', CFBundleExecutable='NetGlassFilter', CFBundlePackageType='SYSX', CFBundleVersion='1.0.0', CFBundleShortVersionString='1.0', LSMinimumSystemVersion='15.0', NetworkExtension={'NEProviderClasses': {'com.apple.networkextension.filter-data': 'NetGlassFilter.FilterDataProvider'}, 'NEMachServiceName': team + '.com.allen.netglass.filter'})
(ext/'Info.plist').write_bytes(plistlib.dumps(info))
base = {'com.apple.developer.team-identifier': team, 'com.apple.security.application-groups': ['group.com.allen.netglass'], 'com.apple.developer.networking.networkextension': ['content-filter-provider-systemextension']}
for kind, identifier in [('app', 'com.allen.netglass'), ('filter', 'com.allen.netglass.filter')]:
    entitlements = dict(base, **{'com.apple.application-identifier': team + '.' + identifier})
    if kind == 'app': entitlements['com.apple.developer.system-extension.install'] = True
    else: entitlements['com.apple.security.app-sandbox'] = True
    Path('build/'+kind+'-entitlements.plist').write_bytes(plistlib.dumps(entitlements))
PY
cp "$NETGLASS_FILTER_PROFILE" "$extension_path/Contents/embedded.provisionprofile"
cp "$NETGLASS_APP_PROFILE" build/NetGlass.app/Contents/embedded.provisionprofile
codesign --force --options runtime --timestamp --entitlements build/filter-entitlements.plist --sign "$NETGLASS_SIGN_IDENTITY" "$extension_path"
codesign --force --options runtime --timestamp --entitlements build/app-entitlements.plist --sign "$NETGLASS_SIGN_IDENTITY" build/NetGlass.app
codesign --verify --deep --strict build/NetGlass.app
