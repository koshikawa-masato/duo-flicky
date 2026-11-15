#!/bin/zsh
# Duo Flicky: manual-signing export of the existing archive, run inside
# the Mac GUI session so codesign can reach the login keychain.
set -x
rm -f ~/muse-build/duo-tf/status.txt

# Install the API-created App Store profiles where Xcode looks for them.
mkdir -p ~/Library/Developer/Xcode/UserData/"Provisioning Profiles"
mkdir -p ~/Library/MobileDevice/"Provisioning Profiles"
for p in ~/muse-build/duo-tf/profiles/*.mobileprovision; do
  uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' /dev/stdin <<< "$(security cms -D -i "$p" 2>/dev/null)" 2>/dev/null)
  [ -z "$uuid" ] && uuid=$(basename "$p" .mobileprovision)
  cp "$p" ~/Library/Developer/Xcode/UserData/"Provisioning Profiles"/"$uuid".mobileprovision
  cp "$p" ~/Library/MobileDevice/"Provisioning Profiles"/"$uuid".mobileprovision
  echo "installed profile $p as $uuid"
done

security find-identity -v -p codesigning

cat > ~/muse-build/duo-tf/ExportOptionsManual.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>8JN36X5T3B</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>provisioningProfiles</key>
  <dict>
    <key>jp.duoflicky.app</key>
    <string>Duo Flicky App Store</string>
    <key>jp.duoflicky.app.keyboard</key>
    <string>Duo Flicky Keyboard App Store</string>
  </dict>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath ~/muse-build/duo-tf/DuoFlicky.xcarchive \
  -exportPath ~/muse-build/duo-tf/export \
  -exportOptionsPlist ~/muse-build/duo-tf/ExportOptionsManual.plist
echo "EXPORT_EXIT=$?"
ls -la ~/muse-build/duo-tf/export/
echo done > ~/muse-build/duo-tf/status.txt
