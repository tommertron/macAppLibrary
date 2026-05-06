#!/bin/bash
set -e

APP_NAME="macAppLibrary"
VERSION=$(awk -F'= ' '/MARKETING_VERSION/ {gsub(/;/, "", $2); print $2; exit}' "${APP_NAME}.xcodeproj/project.pbxproj")
TEAM_ID="4RQBJ49K9T"
IDENTITY="Developer ID Application: Thomas Robertson (${TEAM_ID})"

ARCHIVE_PATH="dist/build/${APP_NAME}.xcarchive"
EXPORT_DIR="dist/export"
DMG_STAGE="dist/dmg-stage"
DMG_NAME="dist/${APP_NAME}-${VERSION}.dmg"

echo "🧹 Cleaning dist..."
rm -rf dist
mkdir -p dist/build

echo "🔨 Archiving (Release)..."
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    -quiet

echo "📦 Exporting signed app..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist ExportOptions.plist \
    -quiet

echo "💿 Staging DMG contents..."
mkdir -p "${DMG_STAGE}"
cp -R "${EXPORT_DIR}/${APP_NAME}.app" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

echo "💿 Creating DMG..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

echo "✅ DMG created: ${DMG_NAME}"

echo "🔏 Notarizing (this takes a minute or two)..."
if [ -n "${APPLE_ID}" ] && [ -n "${APPLE_APP_PASSWORD}" ]; then
    xcrun notarytool submit "${DMG_NAME}" \
        --apple-id "${APPLE_ID}" \
        --password "${APPLE_APP_PASSWORD}" \
        --team-id "${TEAM_ID}" \
        --wait
else
    xcrun notarytool submit "${DMG_NAME}" \
        --keychain-profile "macAppLibrary" \
        --wait
fi
echo "📎 Stapling ticket..."
xcrun stapler staple "${DMG_NAME}"
echo "✅ Notarized and stapled"

echo ""
echo "🎉 Done!"
echo "   DMG: ${DMG_NAME}"
echo ""
echo "To share: send the .dmg — users double-click, drag ${APP_NAME} to Applications."
