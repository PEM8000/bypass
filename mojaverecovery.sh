#!/bin/sh

# source
# https://gist.githubusercontent.com/jonathantneal/f20e6f3e03d5637f983f8543df70cef5/raw/dd623515bacb1d918f48e87d8cc6c0800e5e4c21/recovery.sh

# Set the macOS installer path as a variable
MACOS_INSTALLER="/Applications/$(ls /Applications | grep "Install macOS")"
MOUNT_POINT="$MACOS_INSTALLER/Contents/SharedSupport"
echo "macOS installer is \"$MACOS_INSTALLER\""

# Set the target disk as a variable
TARGET=$(diskutil info "$(bless --info --getBoot)" | awk -F':' '/Volume Name/ { print $2 }' | sed -e 's/^[[:space:]]*//')
echo "Target disk is \"$TARGET\""

# Set the target disk filesystem
FS_TYPE=$(diskutil info "$TARGET" | awk '$1 == "Type" { print $NF }')
echo "Target filesystem is \"${FS_TYPE}\""

# Download the APFS-compatible Recovery into /private/tmp (use 10.13.6, which also works with Mojave 10.14.x)
echo "Downloading macOSUpd10.13.6.RecoveryHDUpdate.pkg into /private/tmp"
curl http://swcdn.apple.com/content/downloads/42/58/091-94330/mm8vnigq4ulozt9iqhgcl9hp8m7iygsqbl/macOSUpd10.13.6.RecoveryHDUpdate.pkg --progress-bar -L -o /private/tmp/macOSUpd10.13.6.RecoveryHDUpdate.pkg
pkgutil --expand /private/tmp/macOSUpd10.13.6.RecoveryHDUpdate.pkg /private/tmp/recoveryupdate10.13.6

if [[ "${FS_TYPE}" == "apfs" ]]; then
	echo "Running ensureRecoveryBooter for APFS target volume: $TARGET"
	/private/tmp/recoveryupdate10.13.6/Scripts/Tools/dm ensureRecoveryBooter "$TARGET" -base "$MOUNT_POINT/BaseSystem.dmg" "$MOUNT_POINT/BaseSystem.chunklist" -diag "$MOUNT_POINT/AppleDiagnostics.dmg" "$MOUNT_POINT/AppleDiagnostics.chunklist" -diagmachineblacklist 0 -installbootfromtarget 0 -slurpappleboot 0 -delappleboot 0 -addkernelcoredump 0
else
	echo "Running ensureRecoveryPartition for Non-APFS target volume: $TARGET"
	/private/tmp/recoveryupdate10.13.6/Scripts/Tools/dm ensureRecoveryPartition "$TARGET" "$MOUNT_POINT/BaseSystem.dmg" "$MOUNT_POINT/BaseSystem.chunklist" "$MOUNT_POINT/AppleDiagnostics.dmg" "$MOUNT_POINT/AppleDiagnostics.chunklist" 0 0 0
fi

echo "Finished creating Recovery HD"
