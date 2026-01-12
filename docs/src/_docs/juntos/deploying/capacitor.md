---
order: 645
title: Capacitor Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Build native iOS and Android apps from your Rails codebase using Capacitor.

{% toc %}

## Overview

[Capacitor](https://capacitorjs.com/) wraps your web app in a native shell, providing access to device APIs like camera, GPS, and push notifications. Your Rails code runs in a WebView with full access to the Capacitor plugin ecosystem.

**Use cases:**

- iOS and Android apps from one codebase
- Native device features (camera, filesystem, biometrics)
- App Store and Google Play distribution
- Offline-first mobile apps

## Prerequisites

### iOS Development

1. **macOS** — Required for iOS builds
2. **Xcode** — Install from Mac App Store
3. **Xcode Command Line Tools**
   ```bash
   xcode-select --install
   ```
4. **CocoaPods**
   ```bash
   sudo gem install cocoapods
   ```

### Android Development

1. **Android Studio** — [Download](https://developer.android.com/studio)
2. **Android SDK** — Installed via Android Studio
3. **Java Development Kit** — Android Studio includes this

## Database Options

| Adapter | Storage | Notes |
|---------|---------|-------|
| `dexie` | IndexedDB | Recommended, persists in WebView |
| `sqljs` | SQLite/WASM | In-memory or persisted |
| `neon` | Serverless PostgreSQL | Requires network |
| `turso` | SQLite edge | Requires network |

For offline-first apps, use `dexie` or `sqljs`. For connected apps, HTTP-based adapters work normally.

## Build

```bash
# Build for Capacitor
bin/juntos build -t capacitor -d dexie

# Navigate to dist
cd dist

# Install dependencies
npm install

# Add platforms (installs plugins into native projects)
npx cap add ios
npx cap add android
```

### Pre-configuring Plugins

Add Capacitor plugins to `config/ruby2js.yml` so they're automatically included in the build:

```yaml
# config/ruby2js.yml
dependencies:
  "@capacitor/camera": "^6.0.0"
  "@capacitor/geolocation": "^6.0.0"
```

These dependencies are added to the generated `package.json` and installed with `npm install`.

### Adding Plugins Later

To add plugins after the initial build:

```bash
cd dist
npm install @capacitor/camera
npx cap sync
```

**Important:** Run `npx cap sync` after adding plugins to update the native projects with permissions and dependencies.

## Project Structure

After building, `dist/` contains:

```
dist/
├── app/                    # Transpiled Rails app
├── lib/                    # Runtime (browser target)
├── index.html              # Entry point
├── capacitor.config.ts     # Capacitor configuration
├── package.json            # Includes Capacitor dependencies
├── ios/                    # iOS project (after cap add)
│   └── App/
│       ├── App.xcodeproj
│       └── Podfile
└── android/                # Android project (after cap add)
    └── app/
        └── build.gradle
```

## Generated Configuration

### capacitor.config.ts

```typescript
import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.myapp',
  appName: 'My App',
  webDir: '.',
  server: {
    // Development only - remove for production
    url: 'http://localhost:3000',
    cleartext: true
  },
  plugins: {
    Camera: {
      // Permissions configured automatically
    }
  }
};

export default config;
```

### package.json

```json
{
  "dependencies": {
    "@capacitor/core": "^6.0.0",
    "@capacitor/ios": "^6.0.0",
    "@capacitor/android": "^6.0.0",
    "@capacitor/camera": "^6.0.0"
  },
  "devDependencies": {
    "@capacitor/cli": "^6.0.0"
  }
}
```

## Run on iOS

### Simulator

```bash
cd dist
npx cap run ios
```

This opens Xcode. Select a simulator and click Run.

### Physical Device

1. Connect your iPhone via USB
2. In Xcode, select your device from the destination menu
3. You may need to trust your development certificate on the device
4. Click Run

### Development Workflow

For faster iteration during development:

```bash
# Terminal 1: Run dev server
bin/juntos dev -d dexie

# Terminal 2: Sync and run
cd dist
npx cap sync ios
npx cap run ios
```

The app loads from your dev server, enabling hot reload.

## Run on Android

### Emulator

```bash
cd dist
npx cap run android
```

This opens Android Studio. Select an emulator and click Run.

### Physical Device

1. Enable Developer Mode on your Android device
2. Enable USB Debugging
3. Connect via USB
4. Select your device in Android Studio
5. Click Run

## Native Plugins

Capacitor plugins provide access to native APIs. Pre-configure them in `config/ruby2js.yml` or install manually, then use them in your Ruby Stimulus controllers:

### Camera

```yaml
# config/ruby2js.yml
dependencies:
  "@capacitor/camera": "^6.0.0"
```

```ruby
# app/javascript/controllers/camera_controller.rb
class CameraController < Stimulus::Controller
  def takePhoto
    Camera = (await import("@capacitor/camera")).Camera
    CameraResultType = (await import("@capacitor/camera")).CameraResultType

    result = await Camera.getPhoto(
      quality: 80,
      resultType: CameraResultType.Base64
    )

    previewTarget.src = "data:image/jpeg;base64,#{result.base64String}"
  end
end
```

### Geolocation

```yaml
# config/ruby2js.yml
dependencies:
  "@capacitor/geolocation": "^6.0.0"
```

```ruby
class LocationController < Stimulus::Controller
  def getLocation
    Geolocation = (await import("@capacitor/geolocation")).Geolocation

    position = await Geolocation.getCurrentPosition()
    console.log("Lat:", position.coords.latitude)
    console.log("Lng:", position.coords.longitude)
  end
end
```

### Push Notifications

```yaml
# config/ruby2js.yml
dependencies:
  "@capacitor/push-notifications": "^6.0.0"
```

```ruby
class NotificationController < Stimulus::Controller
  def connect
    PushNotifications = (await import("@capacitor/push-notifications")).PushNotifications

    # Request permission
    await PushNotifications.requestPermissions()

    # Register for push
    await PushNotifications.register()

    # Handle registration token
    PushNotifications.addListener("registration") do |token|
      console.log("Push token:", token.value)
      # Send token to your server
    end
  end
end
```

## Platform Permissions

Capacitor automatically configures permissions when you install plugins.

### iOS (Info.plist)

Camera plugin adds:

```xml
<key>NSCameraUsageDescription</key>
<string>Take photos for your gallery</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Select photos from your library</string>
```

### Android (AndroidManifest.xml)

Camera plugin adds:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

## App Store Submission

### iOS

1. **Apple Developer Account** — $99/year
2. **App Store Connect** — Create app listing
3. **Certificates & Provisioning**
   ```bash
   # In Xcode: Signing & Capabilities
   # Select your team, enable automatic signing
   ```
4. **Archive and Upload**
   - Product → Archive
   - Distribute App → App Store Connect

### Android

1. **Google Play Developer Account** — $25 one-time
2. **Google Play Console** — Create app listing
3. **Generate Signed APK/Bundle**
   ```bash
   cd dist/android
   ./gradlew bundleRelease
   ```
4. **Upload to Play Console**
   - Upload `app-release.aab` from `app/build/outputs/bundle/release/`

## Troubleshooting

### "Pod install failed"

```bash
cd dist/ios/App
pod install --repo-update
```

### "SDK not found" (Android)

Open Android Studio → SDK Manager → Install required SDK versions.

### Camera not working in simulator

iOS Simulator doesn't support camera. Test on a physical device.

### WebView debugging

**iOS:** Safari → Develop → [Your Device] → [Your App]

**Android:** Chrome → `chrome://inspect` → Select your WebView

## Comparison with React Native

| Aspect | Capacitor | React Native |
|--------|-----------|--------------|
| UI rendering | WebView | Native components |
| Code reuse | 100% web code | Partial |
| Performance | Good | Better for complex UI |
| Native access | Via plugins | Direct |
| Learning curve | Minimal if you know web | React + native concepts |

Capacitor is ideal when you have an existing web app (like a Juntos app) and want to deploy it to mobile with native features.

## Limitations

- **WebView performance** — Complex animations may be slower than native
- **Platform differences** — Some CSS/JS may behave differently
- **App size** — WebView apps are typically larger than pure native
- **Background execution** — Limited compared to native apps
