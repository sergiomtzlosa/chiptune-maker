# Release and notarization

This document describes the direct-distribution path for Chiptune Maker. The app is sandbox-disabled, hardened-runtime enabled, and signed with a Developer ID Application certificate.

## Prerequisites

- A **Developer ID Application** certificate in the login keychain.
- An Apple ID team ID.
- A `notarytool` keychain profile:

  ```sh
  xcrun notarytool store-credentials "ChiptuneMakerNotary" \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "app-specific-password"
  ```

- XcodeGen and the command-line tools.
- Optional: LAME installed for MP3 export testing.

## 1. Build a universal Release app

```sh
xcodegen generate

xcodebuild \
  -project ChiptuneMaker.xcodeproj \
  -scheme ChiptuneMaker \
  -configuration Release \
  -derivedDataPath build-release \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="TEAMID" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  build
```

The product is `build-release/Build/Products/Release/ChiptuneMaker.app`.

## 2. Sign

If you later bundle a dylib such as `libmp3lame.dylib`, sign it before the app:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  "ChiptuneMaker.app/Contents/Frameworks/libmp3lame.dylib"
```

Then sign the app:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  "build-release/Build/Products/Release/ChiptuneMaker.app"

codesign --verify --deep --strict --verbose=2 \
  "build-release/Build/Products/Release/ChiptuneMaker.app"
```

Do not use `--deep` when signing; use it only for verification.

## 3. Notarize

```sh
ditto -c -k --keepParent \
  "build-release/Build/Products/Release/ChiptuneMaker.app" \
  "ChiptuneMaker.zip"

xcrun notarytool submit "ChiptuneMaker.zip" \
  --keychain-profile "ChiptuneMakerNotary" \
  --wait

xcrun stapler staple \
  "build-release/Build/Products/Release/ChiptuneMaker.app"

xcrun stapler validate \
  "build-release/Build/Products/Release/ChiptuneMaker.app"
```

## 4. Create the DMG

```sh
hdiutil create \
  -volname "Chiptune Maker" \
  -srcfolder "build-release/Build/Products/Release/ChiptuneMaker.app" \
  -ov -format UDZO \
  "ChiptuneMaker-0.1.0.dmg"

codesign --force --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  "ChiptuneMaker-0.1.0.dmg"
```

## 5. Verify Gatekeeper

On a clean Mac or a fresh user account:

```sh
spctl --assess --type execute --verbose=4 "/Applications/ChiptuneMaker.app"
```

Open the DMG, drag the app to Applications, launch it, and confirm that no Gatekeeper warning appears.

## Notes

- The app has no app sandbox entitlement. This is intentional for direct distribution and for invoking a local LAME executable.
- Hardened runtime is enabled in `project.yml`.
- If you enable the sandbox later, add the appropriate entitlements and replace the external LAME process with a bundled, signed dylib.
- The repository does not include a code-signing certificate or notarization credentials.
