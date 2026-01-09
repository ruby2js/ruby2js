# Photo Gallery Demo - Camera Integration

A focused demo showcasing camera integration with Juntos across all targets, including native mobile (Capacitor) and desktop (Electron).

## Overview

| Demo | Pattern | What It Shows |
|------|---------|---------------|
| Blog | CRUD | Table stakes, Rails conventions |
| Chat | Real-time | Turbo Streams, WebSockets |
| **Photo Gallery** | Camera + Native | Browser/native camera, binary storage, desktop integration |

### The Story

> Access camera from Ruby. Take photos with webcam or device camera, store them, display in a gallery. Works on all targets—browser uses `getUserMedia()`, Capacitor uses native camera, Electron adds desktop integration with system tray, global shortcuts, and background operation.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Client (browser, Capacitor, or Electron renderer)       │
│  ┌─────────────────────────────────────────────────────┐│
│  │  Ruby Stimulus Controller                           ││
│  │  ├── takePhoto()                                    ││
│  │  │   ├── Browser/Electron: getUserMedia() → webcam  ││
│  │  │   └── Capacitor: Camera.getPhoto() → native      ││
│  │  └── Sends base64 to server/stores locally          ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  Storage (varies by target)                              │
│  ├── browser/capacitor: IndexedDB (Dexie)               │
│  ├── electron: SQLite (better-sqlite3)                  │
│  ├── node: SQLite/PostgreSQL/MySQL                      │
│  ├── cloudflare: D1                                     │
│  └── vercel: Neon/Turso                                 │
└─────────────────────────────────────────────────────────┘

Electron-specific (desktop only):
┌─────────────────────────────────────────────────────────┐
│  Main Process                                            │
│  ├── System tray icon (menu bar)                        │
│  ├── Global shortcut (Cmd+Shift+P) — works from any app │
│  ├── Frameless popup window                             │
│  ├── No dock icon (background utility)                  │
│  └── IPC bridge to renderer                             │
└─────────────────────────────────────────────────────────┘
```

## Data Model

### Photo

Simple, append-only. No updates, no deletes.

```ruby
class Photo < ApplicationRecord
  attribute :client_id, :string      # UUID (for future sync)
  attribute :image_data, :text       # Base64 encoded image
  attribute :caption, :string
  attribute :taken_at, :datetime

  validates :image_data, presence: true
  validates :taken_at, presence: true

  before_create do
    self.client_id ||= SecureRandom.uuid
    self.taken_at ||= Time.current
  end
end
```

## Implementation

### Stimulus Controller (Ruby)

```ruby
class CameraController < Stimulus::Controller
  targets [:imageData, :preview, :captionInput, :video]

  def takePhoto
    if defined?(Capacitor)
      # Native app - use Capacitor Camera plugin
      result = await Camera.getPhoto(
        resultType: CameraResultType::Base64,
        source: CameraSource::Camera,
        quality: 80
      )
      handlePhoto(result.base64String)
    else
      # Browser - use getUserMedia
      stream = await navigator.mediaDevices.getUserMedia(video: true)
      base64 = await captureFrame(stream)
      stream.getTracks.each { |track| track.stop }
      handlePhoto(base64)
    end
  end

  def captureFrame(stream)
    # Show video preview, capture frame to canvas
    videoTarget.srcObject = stream
    await videoTarget.play

    canvas = document.createElement('canvas')
    canvas.width = videoTarget.videoWidth
    canvas.height = videoTarget.videoHeight
    canvas.getContext('2d').drawImage(videoTarget, 0, 0)

    # Return base64 without data URL prefix
    canvas.toDataURL('image/jpeg', 0.8).sub('data:image/jpeg;base64,', '')
  end

  def handlePhoto(base64)
    imageDataTarget.value = base64
    previewTarget.src = "data:image/jpeg;base64,#{base64}"
    previewTarget.classList.remove('hidden')
    videoTarget.classList.add('hidden')
    captionInputTarget.focus
  end

  def chooseFromGallery
    if defined?(Capacitor)
      result = await Camera.getPhoto(
        resultType: CameraResultType::Base64,
        source: CameraSource::Photos,
        quality: 80
      )
      handlePhoto(result.base64String)
    else
      # Browser fallback - file input
      input = document.createElement('input')
      input.type = 'file'
      input.accept = 'image/*'
      input.onchange = -> { handleFileSelect(input) }
      input.click
    end
  end

  def handleFileSelect(input)
    file = input.files[0]
    return unless file

    reader = FileReader.new
    reader.onload = -> {
      base64 = reader.result.sub(/^data:image\/\w+;base64,/, '')
      handlePhoto(base64)
    }
    reader.readAsDataURL(file)
  end
end
```

### View (ERB)

```erb
<%# app/views/photos/index.html.erb %>
<div data-controller="camera">
  <h1>Photo Gallery</h1>

  <!-- Capture buttons -->
  <div class="actions">
    <button data-action="click->camera#takePhoto">
      Take Photo
    </button>
    <button data-action="click->camera#chooseFromGallery">
      Choose from Gallery
    </button>
  </div>

  <!-- New photo form -->
  <%= form_with model: Photo.new, data: { action: "turbo:submit-end->camera#reset" } do |f| %>
    <%= f.hidden_field :image_data, data: { camera_target: "imageData" } %>

    <!-- Video preview for browser camera -->
    <video data-camera-target="video" class="hidden preview" autoplay playsinline></video>

    <!-- Image preview after capture -->
    <img data-camera-target="preview" class="hidden preview" />

    <%= f.text_field :caption,
        placeholder: "Add a caption...",
        data: { camera_target: "captionInput" } %>

    <%= f.submit "Save" %>
  <% end %>

  <!-- Gallery grid -->
  <div id="photos" class="gallery">
    <%= render @photos %>
  </div>
</div>
```

```erb
<%# app/views/photos/_photo.html.erb %>
<div id="<%= dom_id(photo) %>" class="photo-card">
  <img src="data:image/jpeg;base64,<%= photo.image_data %>" />
  <p><%= photo.caption %></p>
  <time><%= photo.taken_at.strftime("%b %d, %Y") %></time>
</div>
```

### Controller

```ruby
class PhotosController < ApplicationController
  def index
    @photos = Photo.order(taken_at: :desc)
  end

  def create
    @photo = Photo.new(photo_params)

    if @photo.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to photos_path }
      end
    end
  end

  private

  def photo_params
    params.require(:photo).permit(:image_data, :caption)
  end
end
```

### Turbo Stream Response

```erb
<%# app/views/photos/create.turbo_stream.erb %>
<%= turbo_stream.prepend "photos", @photo %>
```

## Capacitor Setup

### Dependencies

```json
{
  "dependencies": {
    "@capacitor/core": "^5.0.0",
    "@capacitor/camera": "^5.0.0"
  }
}
```

### Capacitor Config

```typescript
// capacitor.config.ts
import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.photogallery',
  appName: 'Photo Gallery',
  webDir: 'dist',
  plugins: {
    Camera: {
      // iOS: Add to Info.plist automatically
      // Android: Add to AndroidManifest.xml automatically
    }
  }
};

export default config;
```

### Platform Permissions

**iOS (Info.plist)** - Added automatically by Capacitor:
```xml
<key>NSCameraUsageDescription</key>
<string>Take photos for your gallery</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Select photos from your library</string>
```

**Android (AndroidManifest.xml)** - Added automatically by Capacitor:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

## Electron Setup

### Dependencies

```json
{
  "dependencies": {
    "electron": "^28.0.0",
    "better-sqlite3": "^9.0.0"
  },
  "devDependencies": {
    "electron-builder": "^24.0.0"
  }
}
```

### Electron Main Process

```javascript
// main.js
const { app, BrowserWindow, Tray, Menu, globalShortcut, nativeImage } = require('electron');
const path = require('path');

let tray = null;
let mainWindow = null;

// Don't show in dock (macOS) — runs as background utility
app.dock?.hide();

app.whenReady().then(() => {
  createTray();
  createWindow();
  registerShortcuts();
});

function createTray() {
  const icon = nativeImage.createFromPath(path.join(__dirname, 'assets/tray-icon.png'));
  tray = new Tray(icon.resize({ width: 16, height: 16 }));

  tray.setToolTip('Photo Gallery');
  tray.on('click', toggleWindow);

  const contextMenu = Menu.buildFromTemplate([
    { label: 'Quick Capture', click: toggleWindow },
    { label: 'View Gallery', click: showGallery },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() }
  ]);
  tray.setContextMenu(contextMenu);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 400,
    height: 500,
    show: false,
    frame: false,          // Frameless popup
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true
    }
  });

  mainWindow.loadFile('dist/index.html');

  // Hide instead of close when clicking outside
  mainWindow.on('blur', () => mainWindow.hide());
}

function toggleWindow() {
  if (mainWindow.isVisible()) {
    mainWindow.hide();
  } else {
    showWindow();
  }
}

function showWindow() {
  // Position below tray icon
  const trayBounds = tray.getBounds();
  const windowBounds = mainWindow.getBounds();

  const x = Math.round(trayBounds.x + (trayBounds.width / 2) - (windowBounds.width / 2));
  const y = Math.round(trayBounds.y + trayBounds.height + 4);

  mainWindow.setPosition(x, y, false);
  mainWindow.show();
  mainWindow.focus();

  // Tell renderer to activate camera
  mainWindow.webContents.send('quick-capture');
}

function showGallery() {
  // Resize for gallery view
  mainWindow.setSize(800, 600);
  mainWindow.center();
  mainWindow.show();
  mainWindow.focus();
}

function registerShortcuts() {
  // Global shortcut works even when another app has focus
  globalShortcut.register('CommandOrControl+Shift+P', () => {
    showWindow();
  });
}

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});
```

### Preload Script

```javascript
// preload.js
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electron', {
  onQuickCapture: (callback) => ipcRenderer.on('quick-capture', callback),
  hideWindow: () => ipcRenderer.send('hide-window'),
  isElectron: true
});
```

### Electron-aware Stimulus Controller

The CameraController detects Electron and responds to IPC events:

```ruby
class CameraController < Stimulus::Controller
  def connect
    # Listen for quick capture shortcut from main process
    if window.electron
      window.electron.onQuickCapture { takePhoto }
    end
  end

  def takePhoto
    if defined?(Capacitor)
      # Native mobile - use Capacitor Camera plugin
      result = await Camera.getPhoto(
        resultType: CameraResultType::Base64,
        source: CameraSource::Camera,
        quality: 80
      )
      handlePhoto(result.base64String)
    else
      # Browser or Electron - use getUserMedia
      stream = await navigator.mediaDevices.getUserMedia(video: true)
      base64 = await captureFrame(stream)
      stream.getTracks.each { |track| track.stop }
      handlePhoto(base64)
    end
  end

  def handlePhoto(base64)
    imageDataTarget.value = base64
    previewTarget.src = "data:image/jpeg;base64,#{base64}"
    previewTarget.classList.remove('hidden')
    videoTarget.classList.add('hidden')
    captionInputTarget.focus
  end

  def save
    # After saving, hide window if in Electron quick-capture mode
    if window.electron
      window.electron.hideWindow
    end
  end
end
```

### Platform Notes

**macOS:**
- Tray icon appears in menu bar
- `app.dock.hide()` removes from dock
- Global shortcut: Cmd+Shift+P

**Windows:**
- Tray icon appears in system tray
- Global shortcut: Ctrl+Shift+P

**Linux:**
- Tray support varies by desktop environment
- May need `libappindicator` on some distros

### Package for Distribution

```bash
# Build distributable
npm run package

# Output:
# - macOS: dist/Photo Gallery.dmg
# - Windows: dist/Photo Gallery Setup.exe
# - Linux: dist/photo-gallery.AppImage
```

### electron-builder config

```json
{
  "build": {
    "appId": "com.example.photo-gallery",
    "productName": "Photo Gallery",
    "mac": {
      "category": "public.app-category.photography",
      "target": "dmg"
    },
    "win": {
      "target": "nsis"
    },
    "linux": {
      "target": "AppImage"
    }
  }
}
```

## Build & Run

```bash
# Create the app
curl -sL .../create-photo-gallery | bash -s photo_gallery
cd photo_gallery

# Run in browser (webcam)
bin/juntos dev -d dexie

# Run on Node.js (webcam, SQLite storage)
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite

# Deploy to Cloudflare (webcam, D1 storage)
bin/juntos deploy -d d1

# Build for Capacitor (native mobile camera)
bin/juntos build -t capacitor -d dexie
cd dist
npm install
npx cap add ios      # Requires Xcode
npx cap add android  # Requires Android Studio
npx cap run ios      # Opens Xcode, run on device/simulator
npx cap run android  # Opens Android Studio, run on device/emulator

# Build for Electron (desktop with system tray)
bin/juntos build -t electron -d sqlite
cd dist
npm install
npm start            # Run in development
npm run package      # Build distributable (.dmg, .exe, .AppImage)
```

## Demo Flow

### Browser / Node / Edge
1. **Open app** in browser
2. **Click "Take Photo"** → Webcam activates
3. **Capture photo** → Preview shown
4. **Add caption** → Optional
5. **Click "Save"** → Stored in database
6. **See gallery** → Photo appears at top

### Capacitor (Mobile)
1. **Launch app** on iPhone/Android
2. **Tap "Take Photo"** → Native camera opens
3. **Take picture** → Returns to app with preview
4. **Add caption** → Optional
5. **Tap "Save"** → Stored in IndexedDB
6. **See gallery** → Photo appears at top

### Electron (Desktop)
1. **Launch app** → Appears in menu bar (not dock)
2. **Click tray icon** or **press Cmd+Shift+P** from any app
3. **Popup appears** → Webcam activates automatically
4. **Capture photo** → Preview shown
5. **Add caption** → Optional
6. **Click "Save"** → Stored in SQLite, popup closes
7. **Click tray → "View Gallery"** → Full gallery window opens

## What This Proves

| Capability | Demonstrated |
|------------|--------------|
| Browser camera | `getUserMedia()` API |
| Capacitor native camera | `Camera.getPhoto()` plugin |
| Electron system tray | `Tray` API, menu bar icon |
| Electron global shortcuts | `globalShortcut.register()` — works from any app |
| Electron frameless popup | Custom window positioned below tray |
| Electron background app | No dock icon, runs as utility |
| Ruby calling browser/native APIs | Stimulus controller in Ruby |
| Binary data storage | Base64 images in any database |
| Turbo Streams | Real-time UI updates |
| Multi-target | Same code on browser, node, edge, mobile, desktop |

## What This Doesn't Do (Yet)

- No server sync (local only)
- No user authentication
- No delete functionality
- No image editing
- No sharing

These are intentionally deferred. This demo focuses on **native camera integration**.

## Future: Social Feed Integration

This demo becomes a building block:

```
Blog (text posts)
    +
Chat (real-time)
    +
Photo Gallery (images)
    =
Social Feed (combined, with sync)
```

The `Photo` model's `client_id` field enables future sync:

```ruby
# Future sync endpoint
def sync
  # Get new photos from server
  new_photos = fetch("/api/photos?since=#{last_sync_at}")
  new_photos.each { |p| Photo.create(p) }

  # Push local photos to server
  local_photos = Photo.where('created_at > ?', last_push_at)
  post("/api/photos", photos: local_photos)
end
```

No conflicts because:
- Append-only (no updates)
- No deletes
- `client_id` ensures uniqueness

## Files to Generate

```
photo_gallery/
├── app/
│   ├── models/
│   │   └── photo.rb
│   ├── controllers/
│   │   └── photos_controller.rb
│   ├── views/
│   │   └── photos/
│   │       ├── index.html.erb
│   │       ├── _photo.html.erb
│   │       └── create.turbo_stream.erb
│   └── javascript/
│       └── controllers/
│           └── camera_controller.rb
├── config/
│   ├── routes.rb
│   └── database.yml
├── db/
│   └── schema.rb
└── package.json

# Additional files generated for Electron target:
dist/
├── main.js              # Electron main process
├── preload.js           # Context bridge (IPC)
├── assets/
│   ├── tray-icon.png    # Menu bar icon (light mode)
│   └── tray-icon-dark.png  # Menu bar icon (dark mode)
└── package.json         # Includes electron-builder config
```

## Implementation Checklist

### Phase 1: Core Gallery

- [x] Create Photo model
- [x] Create PhotosController with index/create
- [x] Create views (index, _photo partial, turbo_stream)
- [x] Add CameraController (Stimulus) with browser camera support

### Phase 2: Test Core Targets

- [x] Test browser target with webcam (Dexie/IndexedDB)
- [x] Test server target with webcam (Node/SQLite - same code works on Cloudflare D1, Vercel, etc.)

### Phase 3: Capacitor Target

- [ ] Add Capacitor target to builder
- [ ] Configure Capacitor camera plugin
- [ ] Test on iOS simulator
- [ ] Test on Android emulator

### Phase 4: Electron Target

- [ ] Add Electron target to builder
- [ ] Generate main.js (main process)
- [ ] Generate preload.js (context bridge)
- [ ] Add system tray with icon
- [ ] Add global shortcut (Cmd+Shift+P)
- [ ] Create frameless popup window
- [ ] Position popup below tray icon
- [ ] Hide dock icon (macOS)
- [ ] Add IPC for quick-capture event
- [ ] Test on macOS
- [ ] Test on Windows
- [ ] Test on Linux

### Phase 5: Polish

- [ ] Add loading states
- [ ] Handle camera permission denial gracefully
- [ ] Add "Choose from Gallery" option
- [ ] Responsive grid layout
- [ ] Electron: dark/light mode tray icons

### Phase 6: Documentation

- [ ] Create docs/src/_docs/juntos/demos/photo-gallery.md
- [ ] Add to demos index
- [x] Create test/photo_gallery/create-photo-gallery script
- [ ] Document Capacitor setup and deployment
- [ ] Document Electron setup and packaging

## Success Criteria

1. **Browser camera works** - Click button, webcam activates, photo captured
2. **Photos persist** - Survive page refresh (database)
3. **Multi-target** - Same code runs on browser, node, edge, mobile, desktop
4. **Ruby throughout** - Model, controller, Stimulus all in Ruby
5. **Turbo integration** - New photos appear without page reload
6. **Capacitor works** - Native camera on iOS/Android
7. **Electron system tray** - Icon in menu bar, click opens popup
8. **Electron global shortcut** - Cmd+Shift+P opens popup from any app
9. **Electron background** - No dock icon, runs as utility

## References

### Camera APIs
- [getUserMedia()](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia) - Browser camera API
- [Capacitor Camera Plugin](https://capacitorjs.com/docs/apis/camera) - Native mobile camera

### Electron
- [Electron Tray](https://www.electronjs.org/docs/latest/api/tray) - System tray integration
- [Electron globalShortcut](https://www.electronjs.org/docs/latest/api/global-shortcut) - System-wide shortcuts
- [Electron BrowserWindow](https://www.electronjs.org/docs/latest/api/browser-window) - Window management
- [electron-builder](https://www.electron.build/) - Packaging for distribution

### Databases
- [Dexie.js](https://dexie.org/) - IndexedDB wrapper (browser/Capacitor)
- [better-sqlite3](https://github.com/WiseLibs/better-sqlite3) - SQLite for Node.js/Electron

### Related Demos
- [Blog Demo](../docs/src/_docs/juntos/demos/blog.md) - CRUD patterns
- [Chat Demo](../docs/src/_docs/juntos/demos/chat.md) - Real-time patterns
