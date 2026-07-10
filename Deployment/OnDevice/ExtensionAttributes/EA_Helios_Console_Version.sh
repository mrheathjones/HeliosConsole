#! /bin/bash

######################################################################
############## Begin Script Information Block ########################
######################################################################
# Name: EA_Helios_Console_Version.sh
# Author: Heath Jones
# Date: 06-29-2026
# Modified: 06-29-2026
# Purpose: Extension Attribute — report the installed Helios Console
#          version (CFBundleShortVersionString) into the computer's
#          inventory record, for smart-group targeting and update
#          enforcement. Emits empty when the app is not installed.
# Version: 1.0 - Initial Script
# Data Type: String
#
######################################################################
############## End Script Information Block ##########################
######################################################################

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly APP_PATH="/Applications/HeliosConsole.app"
readonly INFO_PLIST="${APP_PATH}/Contents/Info.plist"
readonly PLIST_BUDDY="/usr/libexec/PlistBuddy"

# Emit an empty result when the app is not installed — that is a valid
# state (the smart group simply won't match), not an error.
emit_empty() {
    echo "<result></result>"
    exit 0
}

if [[ ! -d "${APP_PATH}" || ! -f "${INFO_PLIST}" ]]
then
    emit_empty
fi

version=$("${PLIST_BUDDY}" -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>/dev/null)

if [[ -z "${version}" ]]
then
    emit_empty
fi

echo "<result>${version}</result>"
