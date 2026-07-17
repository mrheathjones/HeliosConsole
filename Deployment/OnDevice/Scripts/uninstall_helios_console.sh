#! /bin/bash

######################################################################
############## Begin Script Information Block ########################
######################################################################
# Name: uninstall_helios_console.sh
# Author: Heath Jones
# Date: 06-29-2026
# Modified: 07-10-2026
# Purpose: Cleanly remove Helios Console (and the HeliosMenuBar
#          companion) from a managed Mac: quit the apps, delete the
#          bundles, forget the pkg receipts, and clear the console
#          user's local preferences and Cleanup Keychain item.
#          Intended as a Jamf Pro script payload (run as root).
#          NOTE: the managed Configuration Profile is removed by Jamf
#          (unscope/remove the profile) — this script does not touch it.
# Version: 1.0 - Initial Script
# Version: 1.1 - Identifier rebrand: com.helios.console ->
#          com.herojoneslabs.helios.console. Cleans the NEW identifiers
#          AND the old com.helios.* ones, because Macs that upgraded
#          through the rename may still carry prefs plists, pkg
#          receipts, and a Keychain item under the old prefix.
# Version: 1.2 - Also remove the five auth/Jamf Keychain accounts
#          (authToken, refreshToken, userEmail, userName,
#          jamfCredentials), current + legacy spellings. Match Keychain
#          items by ACCOUNT (-a): the app stores them via SecItemAdd
#          with kSecAttrAccount only (no service), so a service (-s)
#          lookup never finds them.
#
######################################################################
############## End Script Information Block ##########################
######################################################################

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly MAIN_APP="/Applications/HeliosConsole.app"
readonly MENUBAR_APP="/Applications/HeliosMenuBar.app"
readonly MAIN_BUNDLE_ID="com.herojoneslabs.helios.console"
readonly MENUBAR_BUNDLE_ID="com.herojoneslabs.helios.console.menubar"
readonly PROTECT_KEYCHAIN_ACCOUNT="com.herojoneslabs.helios.console.protect.password"

# Auth/Jamf Keychain accounts written by the app's KeychainManager.
readonly AUTH_KEYCHAIN_ACCOUNTS=(
    "com.herojoneslabs.helios.console.authToken"
    "com.herojoneslabs.helios.console.refreshToken"
    "com.herojoneslabs.helios.console.userEmail"
    "com.herojoneslabs.helios.console.userName"
    "com.herojoneslabs.helios.console.jamfCredentials"
)

# LEGACY identifiers (pre-rebrand, com.helios.* prefix). Macs that
# upgraded through the 2026-07 identifier rebrand can still carry pkg
# receipts, per-user prefs plists (including the old IPC suite plist,
# which shares the old main bundle-ID domain), and the old Keychain
# item under these names — clean them too so an uninstall on an
# upgraded Mac leaves nothing behind.
readonly LEGACY_MAIN_BUNDLE_ID="com.helios.console"
readonly LEGACY_MENUBAR_BUNDLE_ID="com.helios.console.menubar"
readonly LEGACY_PROTECT_KEYCHAIN_ACCOUNT="com.helios.protect.password"
readonly LEGACY_AUTH_KEYCHAIN_ACCOUNTS=(
    "com.helios.authToken"
    "com.helios.refreshToken"
    "com.helios.userEmail"
    "com.helios.userName"
    "com.helios.jamfCredentials"
)

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
# 3. Forget pkg receipts (current + legacy pre-rebrand identifiers)
# ---------------------------------------------------------------------------
forget_receipt "${MAIN_BUNDLE_ID}"
forget_receipt "${MENUBAR_BUNDLE_ID}"
forget_receipt "${LEGACY_MAIN_BUNDLE_ID}"
forget_receipt "${LEGACY_MENUBAR_BUNDLE_ID}"

# ---------------------------------------------------------------------------
# 4. Clear the console user's local prefs + Cleanup Keychain item
#    (managed-profile values are removed by Jamf, not here)
# ---------------------------------------------------------------------------
if [[ -n "${consoleUser}" ]]; then
    consoleUID=$(/usr/bin/id -u "${consoleUser}" 2>/dev/null)

    info "Clearing local preferences for ${consoleUser}…"
    # Current identifiers first, then the legacy pre-rebrand domains —
    # upgraded Macs may have prefs under both prefixes. The main
    # bundle-ID domain doubles as the console<->menubar IPC suite, so
    # deleting it also clears the (old or new) suite plist.
    for prefsDomain in \
        "${MAIN_BUNDLE_ID}" \
        "${MENUBAR_BUNDLE_ID}" \
        "${LEGACY_MAIN_BUNDLE_ID}" \
        "${LEGACY_MENUBAR_BUNDLE_ID}"
    do
        /bin/launchctl asuser "${consoleUID}" /usr/bin/sudo -u "${consoleUser}" \
            /usr/bin/defaults delete "${prefsDomain}" >/dev/null 2>&1 || true

        # Stale UserDefaults plist (in case cfprefsd has flushed it to disk).
        userPlist="/Users/${consoleUser}/Library/Preferences/${prefsDomain}.plist"
        [[ -f "${userPlist}" ]] && /bin/rm -f "${userPlist}"
    done

    info "Removing Helios Keychain items (current + legacy, if present)…"
    # The app writes every item via SecItemAdd with kSecAttrAccount only
    # (no kSecAttrService), so match by account (-a) — a service (-s)
    # lookup never finds them.
    for keychainAccount in \
        "${PROTECT_KEYCHAIN_ACCOUNT}" \
        "${LEGACY_PROTECT_KEYCHAIN_ACCOUNT}" \
        "${AUTH_KEYCHAIN_ACCOUNTS[@]}" \
        "${LEGACY_AUTH_KEYCHAIN_ACCOUNTS[@]}"
    do
        /bin/launchctl asuser "${consoleUID}" /usr/bin/sudo -u "${consoleUser}" \
            /usr/bin/security delete-generic-password -a "${keychainAccount}" >/dev/null 2>&1 || true
    done
else
    info "No console user logged in — skipping per-user cleanup."
fi

info "Helios Console removed."
exit 0
