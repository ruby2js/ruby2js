---
order: 660
title: Photo Gallery Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

A camera-enabled photo gallery showcasing native device integration. The same code runs in browsers with webcam, on mobile with native camera (Capacitor), and on desktop with system tray integration (Electron).

{% toc %}

## Create the App

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/photo_gallery/create-photo-gallery | bash -s photo_gallery
cd photo_gallery
```

This creates a Rails app with:

- **Photo model** — stores base64 image data with caption and timestamp
- **Camera controller** — Stimulus controller written in Ruby
- **Platform detection** — Automatically uses native camera on mobile
- **Tailwind CSS** — styled gallery grid and capture UI

## Run with Rails

First, verify it works as a standard Rails app:

```bash
RAILS_ENV=production bin/rails db:prepare
bin/rails server -e production
```

Open http://localhost:3000. Click "Take Photo" to activate your webcam. Capture photos, add captions, and see them appear in the gallery.

## Run in the Browser

Stop Rails. Run the same app in your browser:

```bash
bin/juntos dev -d dexie
```

Open http://localhost:3000. Same gallery. Same webcam access. But now:

- **No Ruby runtime** — the browser runs transpiled JavaScript
- **IndexedDB storage** — photos persist in your browser via [Dexie](https://dexie.org/)
- **Hot reload** — edit a Ruby file, save, browser refreshes

### Camera Permissions

The browser will request camera access when you click "Take Photo". Grant permission to enable the webcam. Photos are captured as base64 JPEG and stored directly in IndexedDB.

## Run on Node.js

```bash
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite
```

Open http://localhost:3000. Same gallery—but now Node.js serves requests, and [better-sqlite3](https://github.com/WiseLibs/better-sqlite3) provides the database.

## Build for Mobile (Capacitor)

Capacitor wraps your web app in a native shell, providing access to device APIs like the camera.

```bash
bin/juntos build -t capacitor -d dexie
cd dist
npm install
npx cap add ios      # Requires Xcode
npx cap add android  # Requires Android Studio
```

The Camera plugin is pre-configured in `config/ruby2js.yml`. When you add platforms, Capacitor automatically installs the native plugin code and configures permissions in `Info.plist` (iOS) and `AndroidManifest.xml` (Android).

### Run on iOS

```bash
npx cap run ios
```

This opens Xcode. Select a simulator or connected device and run. When you tap "Take Photo", the native iOS camera opens instead of the webcam.

### Run on Android

```bash
npx cap run android
```

This opens Android Studio. Select an emulator or connected device and run. The native Android camera integrates seamlessly.

### How It Works

The Stimulus controller detects Capacitor and uses the native Camera plugin:

```ruby
def takePhoto
  if isCapacitor
    # Native mobile - use Capacitor Camera plugin
    takePhotoCapacitor()
  else
    # Browser - use getUserMedia
    takePhotoBrowser()
  end
end

def takePhotoCapacitor
  Camera = (await import("@capacitor/camera")).Camera
  CameraResultType = (await import("@capacitor/camera")).CameraResultType
  CameraSource = (await import("@capacitor/camera")).CameraSource

  result = await Camera.getPhoto(
    quality: 80,
    resultType: CameraResultType.Base64,
    source: CameraSource.Camera
  )
  handlePhoto(result.base64String)
rescue => error
  console.error("Camera error:", error)
  takePhotoBrowser()  # Fall back to browser camera
end
```

The dynamic import (`await import("@capacitor/camera")`) means the plugin is only loaded when needed. If the plugin isn't installed, the `rescue` block falls back to the browser camera.

## Build for Desktop (Electron)

Electron creates desktop apps with system tray integration and global shortcuts.

```bash
bin/juntos build -t electron -d sqlite
cd dist
npm install
npm start
```

### Desktop Experience

The app runs as a background utility:

- **System tray icon** — appears in the menu bar (macOS) or system tray (Windows)
- **No dock icon** — doesn't clutter your dock
- **Global shortcut** — `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows) opens capture popup from any app
- **Frameless popup** — positioned below the tray icon for quick captures
- **Auto-hide** — popup closes when you click outside

### Package for Distribution

```bash
npm run package
```

This creates distributable packages:

- **macOS:** `dist/Photo Gallery.dmg`
- **Windows:** `dist/Photo Gallery Setup.exe`
- **Linux:** `dist/photo-gallery.AppImage`

## The Code

The camera controller is written in Ruby. **Try it** — see how it transpiles:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["stimulus", "esm", "functions"]
}'></div>

```ruby
class CameraController < Stimulus::Controller
  def takePhotoBrowser
    # Start video stream from webcam
    stream = await navigator.mediaDevices.getUserMedia(video: { facingMode: "user" })
    videoTarget.srcObject = stream
    videoTarget.classList.remove("hidden")
    captureBtnTarget.classList.remove("hidden")
  end

  def capture
    # Capture frame from video to canvas
    canvas = document.createElement("canvas")
    canvas.width = videoTarget.videoWidth
    canvas.height = videoTarget.videoHeight
    canvas.getContext("2d").drawImage(videoTarget, 0, 0)

    # Stop video stream
    videoTarget.srcObject.getTracks().each { |track| track.stop() }

    # Get base64 image data
    dataUrl = canvas.toDataURL("image/jpeg", 0.8)
    base64 = dataUrl.sub("data:image/jpeg;base64,", "")
    handlePhoto(base64)
  end

  def handlePhoto(base64)
    imageDataTarget.value = base64
    previewTarget.src = "data:image/jpeg;base64,#{base64}"
    formTarget.classList.remove("hidden")
  end
end
```

**Try it** — the model is standard Rails:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

```ruby
class Photo < ApplicationRecord
  validates :image_data, presence: true
end
```

## What This Demo Shows

### Camera Integration

- **Browser webcam** — `getUserMedia()` API with video preview
- **Native camera** — Capacitor Camera plugin on iOS/Android
- **File picker** — "Choose from Gallery" fallback

### Stimulus Controller

- **Written in Ruby** — transpiles to JavaScript
- **Platform detection** — `isCapacitor()` method
- **Async/await** — native camera calls use promises
- **DOM manipulation** — canvas capture, class toggling

### Desktop Integration (Electron)

- **System tray** — menu bar icon with context menu
- **Global shortcuts** — works even when app isn't focused
- **IPC communication** — main process triggers renderer actions
- **Background utility** — no dock icon, minimal footprint

### Data Flow

- **Base64 encoding** — photos stored as text in database
- **Turbo Streams** — new photos appear without page reload
- **Multi-database** — same code works with IndexedDB, SQLite, D1, Neon

## What Works Differently

- **Capacitor camera** — returns base64 directly, no canvas needed
- **Electron popup** — frameless window positioned below tray
- **Permissions** — browser prompts; native apps use Info.plist/AndroidManifest

## What Doesn't Work

- **Video recording** — this demo captures still photos only
- **Photo editing** — no crop, rotate, or filters
- **Server sync** — photos are local only (future enhancement)

## Next Steps

- Try the [Blog Demo](/docs/juntos/demos/blog) for CRUD patterns
- Try the [Chat Demo](/docs/juntos/demos/chat) for real-time features
- Read the [Architecture](/docs/juntos/architecture) to understand what gets generated
- Check [Deployment Guides](/docs/juntos/deploying/) for platform setup
