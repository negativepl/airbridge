#!/bin/bash
#
# bump-version.sh — Bump version across Android, macOS, and git tag
#
# Usage:
#   ./scripts/bump-version.sh patch    # 1.0.0 -> 1.0.1
#   ./scripts/bump-version.sh minor    # 1.0.0 -> 1.1.0
#   ./scripts/bump-version.sh major    # 1.0.0 -> 2.0.0
#   ./scripts/bump-version.sh 2.3.1    # set exact version
#

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADLE="$ROOT/android/Airbridge/app/build.gradle.kts"
PLIST="$ROOT/macos/Airbridge/Resources/Info.plist"
APP_PLIST="$HOME/Applications/Airbridge.app/Contents/Info.plist"

# Read current version from gradle
CURRENT=$(grep 'versionName' "$GRADLE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

echo "Current version: $CURRENT"

# Calculate new version
case "${1:-}" in
    patch)
        PATCH=$((PATCH + 1))
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    "")
        echo "Usage: $0 <patch|minor|major|X.Y.Z>"
        exit 1
        ;;
    *)
        # Exact version provided
        if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IFS='.' read -r MAJOR MINOR PATCH <<< "$1"
        else
            echo "Error: Invalid version format. Use X.Y.Z"
            exit 1
        fi
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
# versionCode = major*10000 + minor*100 + patch
VERSION_CODE=$((MAJOR * 10000 + MINOR * 100 + PATCH))

echo "New version: $NEW_VERSION (code: $VERSION_CODE)"

# 1. Update Android build.gradle.kts
sed -i '' "s/versionCode = [0-9]*/versionCode = $VERSION_CODE/" "$GRADLE"
sed -i '' "s/versionName = \"[^\"]*\"/versionName = \"$NEW_VERSION\"/" "$GRADLE"
echo "  Updated: $GRADLE"

# 2. Update macOS Info.plist (in repo)
if [ -f "$PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$PLIST"
    echo "  Updated: $PLIST"
fi

# 3. Update macOS app bundle Info.plist (if installed)
if [ -f "$APP_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$APP_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$APP_PLIST"
    echo "  Updated: $APP_PLIST"
fi

echo ""
echo "Version bumped to $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  git add -A && git commit -m \"Bump version to $NEW_VERSION\""
echo "  git tag v$NEW_VERSION"
echo "  git push origin master --tags"
echo "  ./scripts/release.sh   # build + create GitHub release"
