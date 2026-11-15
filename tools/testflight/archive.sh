#!/bin/zsh
# Duo Flicky TestFlight build: archive + export, run inside the Mac GUI
# session (via LaunchAgent) so codesign can reach the login keychain.
set -x
cd ~/muse-build/duo-flicky || exit 1
mkdir -p ~/muse-build/duo-tf/export
rm -f ~/muse-build/duo-tf/status.txt

AUTH=(-allowProvisioningUpdates
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_NBH484P5G6.p8"
  -authenticationKeyID NBH484P5G6
  -authenticationKeyIssuerID 94f4f5a7-ccba-45ef-b191-497842793d88)

xcodebuild -project DuoFlicky.xcodeproj -scheme DuoFlicky -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath ~/muse-build/duo-tf/DuoFlicky.xcarchive \
  PROVISIONING_PROFILE_SPECIFIER= \
  "${AUTH[@]}" archive
echo "ARCHIVE_EXIT=$?"
# Export is a separate step (build_export.sh): automatic export fails
# on this team with a cloud-signing permission error, so the IPA is
# exported with manual signing using the App Store profiles created
# by asc_profiles.rb.
echo done > ~/muse-build/duo-tf/status.txt
