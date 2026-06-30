#!/bin/bash
#
# build-pkg.sh — build a HeliosConsole distribution .pkg for a release channel.
#
# Designed to run straight from CodeRunner (or by double-click) — configure it
# with the CONFIG block below instead of command-line flags. Everything else
# (app name, bundle id, built path, base version) is derived from the Xcode
# project via `xcodebuild -showBuildSettings -json`.
#
#   Version scheme (composed from the project's Version + Build):
#     1.0-d.x   Dev team machines   (CHANNEL="dev")
#     1.0-a.x   Alpha testers       (CHANNEL="alpha")
#     1.0-b.x   Beta group          (CHANNEL="beta")
#     1.0-u.x   UAT                 (CHANNEL="uat")
#     1.0       GA to all           (CHANNEL="ga")
#   where 1.0 = MARKETING_VERSION and x = CURRENT_PROJECT_VERSION (numeric build).
#   The channel version is injected into CFBundleShortVersionString (shown in the
#   app's About screen); CFBundleVersion stays the numeric build.
#
#   ONE-TIME SETUP: in Xcode set the HeliosConsole target's Build
#   (CURRENT_PROJECT_VERSION) to a plain integer (e.g. 1). It currently uses an
#   alphanumeric string ("a00201") which this channel scheme can't increment.

set -euo pipefail

# ======================= CONFIG — edit these ========================

# Release channel: dev | alpha | beta | uat | ga
CHANNEL="dev"

# Path to the .xcodeproj. Empty = auto-find the single .xcodeproj next to this
# script's parent folder.
PROJECT=""

# Scheme name. HeliosConsole has two schemes (HeliosConsole + HeliosMenuBar),
# so this MUST be set — auto-detection only works with a single scheme.
SCHEME="HeliosConsole"

# Output directory for the .pkg. Empty = "<project folder>/dist".
OUTPUT=""

# --- App signing ---------------------------------------------------
# Sign the APP with a Developer ID Application identity + hardened runtime.
# Empty = use the project's own signing settings (fine for dev-team machines).
# When set, build-pkg.sh signs Manual and OVERRIDES the project's team with the
# team embedded in the identity (so this works even though the .xcodeproj's
# DEVELOPMENT_TEAM is TEAMIDXXXXXX, for which this Mac has no cert).
APP_IDENTITY="Developer ID Application: Your Name (TEAMIDXXXXXX)"

# --- App notarization (NOT the pkg) --------------------------------
# true  = notarize + staple the .app itself (requires APP_IDENTITY).
# Only needed if the app may arrive via a quarantine channel (download/AirDrop).
# NOT required for plain Jamf policy installs.
NOTARIZE=false
NOTARY_PROFILE="Helios-Notary"     # notarytool keychain profile name

# --- Pkg signing ---------------------------------------------------
# true  = sign the .pkg with a Developer ID Installer identity.
SIGN_PKG=false
PKG_IDENTITY=""                     # empty = auto-detect "Developer ID Installer: …"

# --- Versioning ----------------------------------------------------
# true = after a successful build, bump CURRENT_PROJECT_VERSION in the project.
BUMP=true

# --- Mirror the finished pkg ---------------------------------------
# After a successful build, also copy the .pkg here (e.g. an iCloud folder for
# archiving / sharing). Empty = don't mirror.
MIRROR_DIST="/Users/heath/Library/Mobile Documents/com~apple~CloudDocs/_APPS_IM_BUILDING/Vibe/HELIOS/HeliosConsole/dist"

# ===================================================================

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die()     { printf 'error: %s\n' "$*" >&2; exit 1; }
info()    { printf '==> %s\n' "$*"; }
require() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

require xcodebuild
require jq
require pkgbuild
require productbuild

# xcodebuild must be backed by a full Xcode, not just Command Line Tools.
if ! xcodebuild -version >/dev/null 2>&1; then
    die "xcodebuild can't run (active developer dir: $(xcode-select -p 2>/dev/null)). Point the CLI at Xcode in Terminal:  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

# ---------------------------------------------------------------------------
# Channel → suffix letter
# ---------------------------------------------------------------------------
case "$CHANNEL" in
    dev)    CH="d" ;;
    alpha)  CH="a" ;;
    beta)   CH="b" ;;
    uat)    CH="u" ;;
    ga)     CH="ga" ;;
    *)      die "invalid CHANNEL: '$CHANNEL' (use dev|alpha|beta|uat|ga)" ;;
esac

# ---------------------------------------------------------------------------
# Resolve the project
# ---------------------------------------------------------------------------
if [[ -z "$PROJECT" ]]; then
    shopt -s nullglob
    candidates=( "$SCRIPT_DIR"/../*.xcodeproj )
    shopt -u nullglob
    [[ ${#candidates[@]} -eq 1 ]] || die "could not auto-find a single .xcodeproj in $SCRIPT_DIR/.. — set PROJECT in the config block"
    PROJECT="${candidates[0]}"
fi
[[ -d "$PROJECT" ]] || die "project not found: $PROJECT"
PROJECT="$(cd "$(dirname "$PROJECT")" && pwd)/$(basename "$PROJECT")"
PROJECT_ROOT="$(dirname "$PROJECT")"
[[ -n "$OUTPUT" ]] || OUTPUT="$PROJECT_ROOT/dist"

# ---------------------------------------------------------------------------
# Resolve the scheme
# ---------------------------------------------------------------------------
if [[ -z "$SCHEME" ]]; then
    schemes=()
    while IFS= read -r _scheme; do
        [[ -n "$_scheme" ]] && schemes+=("$_scheme")
    done < <(xcodebuild -list -json -project "$PROJECT" 2>/dev/null | jq -r '.project.schemes[]')
    [[ ${#schemes[@]} -gt 0 ]] || die "no schemes visible to xcodebuild — in Xcode: Product > Scheme > Manage Schemes… and tick 'Shared' for the app scheme (or set SCHEME in the config block)"
    if [[ ${#schemes[@]} -gt 1 ]]; then
        printf 'error: multiple schemes; set SCHEME in the config block to one of:\n' >&2
        printf '  - %s\n' "${schemes[@]}" >&2
        exit 1
    fi
    SCHEME="${schemes[0]}"
fi

# ---------------------------------------------------------------------------
# Validate signing/notarization config early
# ---------------------------------------------------------------------------
if [[ "$NOTARIZE" == "true" && -z "$APP_IDENTITY" ]]; then
    die "NOTARIZE=true requires APP_IDENTITY (Developer ID Application + hardened runtime)"
fi

# ---------------------------------------------------------------------------
# Derive metadata from the project (resolved build settings)
# ---------------------------------------------------------------------------
# Build OUTSIDE iCloud. Putting DerivedData inside an iCloud-synced folder makes
# codesign fail with "resource fork, Finder information, or similar detritus not
# allowed" (iCloud stamps xattrs on the build output), and needlessly syncs GBs
# of intermediates. Use a local, non-synced location instead.
DERIVED="$HOME/Library/Developer/HeliosConsole-build"
info "Reading build settings (scheme: $SCHEME)…"
SETTINGS="$(xcodebuild -showBuildSettings -json \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -derivedDataPath "$DERIVED" 2>/dev/null)"

read_setting() { jq -r --arg k "$1" '.[0].buildSettings[$k] // empty' <<<"$SETTINGS"; }

BASE_MARKETING="$(read_setting MARKETING_VERSION)"
BASE_BUILD="$(read_setting CURRENT_PROJECT_VERSION)"
BUNDLE_ID="$(read_setting PRODUCT_BUNDLE_IDENTIFIER)"
PRODUCT_NAME="$(read_setting PRODUCT_NAME)"
FULL_PRODUCT_NAME="$(read_setting FULL_PRODUCT_NAME)"
BUILT_PRODUCTS_DIR="$(read_setting BUILT_PRODUCTS_DIR)"

[[ -n "$BASE_MARKETING" ]] || die "MARKETING_VERSION is empty — set the target's Version in Xcode (e.g. 1.0)"
[[ -n "$BASE_BUILD" ]]     || die "CURRENT_PROJECT_VERSION is empty — set the target's Build in Xcode (e.g. 1)"
[[ "$BASE_BUILD" =~ ^[0-9]+$ ]] || die "CURRENT_PROJECT_VERSION must be a plain integer (got: $BASE_BUILD) — set the HeliosConsole target's Build to an integer (one-time)"
[[ -n "$FULL_PRODUCT_NAME" && -n "$BUILT_PRODUCTS_DIR" ]] || die "could not resolve product name/path from build settings"

# ---------------------------------------------------------------------------
# Compose the channel version
# ---------------------------------------------------------------------------
if [[ "$CH" == "ga" ]]; then
    FULL_VERSION="$BASE_MARKETING"
else
    FULL_VERSION="${BASE_MARKETING}-${CH}.${BASE_BUILD}"
fi

APP_PATH="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
PKG_PATH="$OUTPUT/${PRODUCT_NAME}-${FULL_VERSION}.pkg"

cat <<EOF
------------------------------------------------------------
  Project : $PROJECT
  Scheme  : $SCHEME
  App     : $FULL_PRODUCT_NAME ($BUNDLE_ID)
  Channel : $CHANNEL  →  version $FULL_VERSION  (build $BASE_BUILD)
  Output  : $PKG_PATH
  App sign: ${APP_IDENTITY:-<project default>}
  Notarize: $NOTARIZE    Pkg sign: $SIGN_PKG    Bump: $BUMP
------------------------------------------------------------
EOF

# ---------------------------------------------------------------------------
# Build (inject the channel version; CFBundleVersion stays numeric)
# ---------------------------------------------------------------------------
info "Building (Release, universal)…"
build_args=(
    build
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration Release
    -derivedDataPath "$DERIVED"
    -arch arm64 -arch x86_64
    -allowProvisioningUpdates
    ONLY_ACTIVE_ARCH=NO
    MARKETING_VERSION="$FULL_VERSION"
    CURRENT_PROJECT_VERSION="$BASE_BUILD"
)
if [[ -n "$APP_IDENTITY" ]]; then
    TEAM_ID="$(sed -n 's/.*(\([A-Z0-9]\{6,\}\)).*/\1/p' <<<"$APP_IDENTITY")"
    build_args+=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="$APP_IDENTITY"
        ENABLE_HARDENED_RUNTIME=YES
        OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"
    )
    [[ -n "$TEAM_ID" ]] && build_args+=( DEVELOPMENT_TEAM="$TEAM_ID" )
fi
xcodebuild "${build_args[@]}"

[[ -d "$APP_PATH" ]] || die "built app not found at: $APP_PATH"

BUILT_SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '?')"
BUILT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '?')"
info "Built bundle version: $BUILT_SHORT ($BUILT_BUILD)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Notarize the APP (optional) — staples the .app itself, NOT the pkg.
# ---------------------------------------------------------------------------
if [[ "$NOTARIZE" == "true" ]]; then
    info "Notarizing the app (profile: $NOTARY_PROFILE)…"
    APP_ZIP="$WORK/app-notarize.zip"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    info "Stapling the app…"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
fi

# ---------------------------------------------------------------------------
# Package: stage → component pkg → distribution pkg (avoids double-nesting)
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT"
STAGING="$WORK/staging"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"          # staging dir contains ONLY the .app
/usr/bin/xattr -cr "$STAGING" 2>/dev/null || true   # strip detritus so pkg/notarization don't choke

COMPONENT="$WORK/component.pkg"
info "Building component package…"
pkgbuild \
    --root "$STAGING" \
    --install-location /Applications \
    --identifier "$BUNDLE_ID" \
    --version "$FULL_VERSION" \
    "$COMPONENT"

# Resolve pkg signing identity
if [[ "$SIGN_PKG" == "true" && -z "$PKG_IDENTITY" ]]; then
    PKG_IDENTITY="$(security find-identity -v 2>/dev/null | sed -n 's/.*"\(Developer ID Installer:[^"]*\)".*/\1/p' | head -1)"
fi

info "Building distribution package…"
prod_args=( --package "$COMPONENT" )
if [[ "$SIGN_PKG" == "true" ]]; then
    [[ -n "$PKG_IDENTITY" ]] || die "SIGN_PKG=true but no 'Developer ID Installer' identity found — set PKG_IDENTITY or set SIGN_PKG=false"
    info "Signing pkg with: $PKG_IDENTITY"
    prod_args+=( --sign "$PKG_IDENTITY" )
else
    info "Building UNSIGNED pkg (fine for Jamf policy installs)"
fi
productbuild "${prod_args[@]}" "$PKG_PATH"

# ---------------------------------------------------------------------------
# Mirror the finished pkg (optional) — e.g. to an iCloud archive folder
# ---------------------------------------------------------------------------
MIRRORED_PATH=""
if [[ -n "$MIRROR_DIST" ]]; then
    info "Mirroring pkg → $MIRROR_DIST"
    mkdir -p "$MIRROR_DIST"
    cp "$PKG_PATH" "$MIRROR_DIST/"
    MIRRORED_PATH="$MIRROR_DIST/$(basename "$PKG_PATH")"
fi

# ---------------------------------------------------------------------------
# Bump build counter in the project (optional)
# ---------------------------------------------------------------------------
if [[ "$BUMP" == "true" ]]; then
    NEXT_BUILD=$(( BASE_BUILD + 1 ))
    info "Bumping CURRENT_PROJECT_VERSION → $NEXT_BUILD in project.pbxproj"
    /usr/bin/sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1${NEXT_BUILD};/g" "$PROJECT/project.pbxproj"
fi

printf '\n✅ Created: %s\n' "$PKG_PATH"
if [[ -n "$MIRRORED_PATH" ]]; then
    printf '   mirrored to: %s\n' "$MIRRORED_PATH"
fi
if [[ "$SIGN_PKG" == "true" && -n "$PKG_IDENTITY" ]]; then
    printf '   pkg signed: %s\n' "$PKG_IDENTITY"
fi
if [[ "$NOTARIZE" == "true" ]]; then
    printf '   app notarized + stapled (pkg not notarized)\n'
fi
exit 0
