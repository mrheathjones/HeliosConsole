#! /bin/bash

######################################################################
############## Begin Script Information Block ########################
######################################################################
# Name: uninstall_helios_console.sh
# Author: Heath Jones
# Date: 06-29-2026
# Modified: 06-29-2026
# Purpose: Cleanly remove Helios Console (and the HeliosMenuBar
#          companion) from a managed Mac: quit the apps, delete the
#          bundles, forget the pkg receipts, and clear the console
#          user's local preferences and Cleanup Keychain item.
#          Intended as a Jamf Pro script payload (run as root).
#          NOTE: the managed Configuration Profile is removed by Jamf
#          (unscope/remove the profile) — this script does not touch it.
# Version: 1.0 - Initial Script
#
######################################################################
############## End Script Information Block ##########################
######################################################################

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly MAIN_APP="/Applications/HeliosConsole.app"
readonly MENUBAR_APP="/Applications/HeliosMenuBar.app"
readonly MAIN_BUNDLE_ID="com.helios.console"
readonly MENUBAR_BUNDLE_ID="com.helios.console.menubar"
readonly PROTECT_KEYCHAIN_ACCOUNT="com.helios.protect.password"

info() { printf '==> %s\n' "$*"; }

# Resolve the currently logged-in console user (empty at the login window).
consoleUser=$(/usr/bin/stat -f%Su /dev/console 2>/dev/null)
[[ "${consoleUser}" == "root" ]] && consoleUser=""

quit_app() {
    local bundleID="$1"
    /usr/bin/pkill -f "${bundleID}" 2>/dev/null || true
}

remove_app() {
    local appPath="$1"
    if [[ -d "${appPath}" ]]; then
        info "Removing ${appPath}"
        /bin/rm -rf "${appPath}"
    fi
}

forget_receipt() {
    local pkgID="$1"
    if /usr/sbin/pkgutil --pkgs | /usr/bin/grep -qx "${pkgID}"; then
        info "Forgetting pkg receipt ${pkgID}"
        /usr/sbin/pkgutil --forget "${pkgID}" >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# 1. Quit running instances
# ---------------------------------------------------------------------------
info "Quitting Helios Console processes…"
quit_app "${MAIN_BUNDLE_ID}"
quit_app "${MENUBAR_BUNDLE_ID}"

# ---------------------------------------------------------------------------
# 2. Remove the app bundles
# ---------------------------------------------------------------------------
remove_app "${MAIN_APP}"
remove_app "${MENUBAR_APP}"

# ---------------------------------------------------------------------------
# 3. Forget pkg receipts
# ---------------------------------------------------------------------------
forget_receipt "${MAIN_BUNDLE_ID}"
forget_receipt "${MENUBAR_BUNDLE_ID}"

# ---------------------------------------------------------------------------
# 4. Clear the console user's local prefs + Cleanup Keychain item
#    (managed-profile values are removed by Jamf, not here)
# ---------------------------------------------------------------------------
if [[ -n "${consoleUser}" ]]; then
    consoleUID=$(/usr/bin/id -u "${consoleUser}" 2>/dev/null)
    info "Clearing local preferences for ${consoleUser}…"
    /bin/launchctl asuser "${consoleUID}" /usr/bin/sudo -u "${consoleUser}" \
        /usr/bin/defaults delete "${MAIN_BUNDLE_ID}" >/dev/null 2>&1 || true

    info "Removing Cleanup Keychain item (if present)…"
    /bin/launchctl asuser "${consoleUID}" /usr/bin/sudo -u "${consoleUser}" \
        /usr/bin/security delete-generic-password -s "${PROTECT_KEYCHAIN_ACCOUNT}" >/dev/null 2>&1 || true

    # Stale UserDefaults plist (in case cfprefsd has flushed it to disk).
    userPlist="/Users/${consoleUser}/Library/Preferences/${MAIN_BUNDLE_ID}.plist"
    [[ -f "${userPlist}" ]] && /bin/rm -f "${userPlist}"
else
    info "No console user logged in — skipping per-user cleanup."
fi

info "Helios Console removed."
exit 0
