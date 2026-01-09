---
order: 646
title: Electron Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Build native desktop apps for macOS, Windows, and Linux using Electron.

{% toc %}

## Overview

[Electron](https://www.electronjs.org/) packages your web app as a native desktop application with full access to operating system APIs. Your Rails code runs in Chromium with Node.js integration for native features.

**Use cases:**

- Desktop apps from your web codebase
- System tray utilities
- Global keyboard shortcuts
- File system access
- Offline desktop tools

## Prerequisites

1. **Node.js 18+** — Required for Electron
2. **npm or yarn** — Package management

Platform-specific requirements for building:

- **macOS:** Xcode Command Line Tools (`xcode-select --install`)
- **Windows:** Visual Studio Build Tools
- **Linux:** Build essentials (`apt install build-essential`)

## Database Options

| Adapter | Storage | Notes |
|---------|---------|-------|
| `sqlite` | SQLite file | Recommended, uses better-sqlite3 |
| `sqljs` | SQLite/WASM | In-memory or persisted |
| `neon` | Serverless PostgreSQL | Requires network |
| `turso` | SQLite edge | Requires network |

For offline desktop apps, use `sqlite` for best performance. The `better-sqlite3` package provides synchronous access from the main process.

## Build

```bash
# Build for Electron
bin/juntos build -t electron -d sqlite

# Navigate to dist
cd dist

# Install dependencies
npm install

# Run in development
npm start
```

## Project Structure

After building, `dist/` contains:

```
dist/
├── app/                    # Transpiled Rails app
├── lib/                    # Runtime
├── index.html              # Renderer entry point
├── main.js                 # Main process
├── preload.js              # Context bridge (IPC)
├── assets/
│   ├── icon.png            # App icon
│   └── tray-icon.png       # System tray icon
├── package.json            # Electron + electron-builder
└── db/
    └── app.sqlite3         # Database file (created on first run)
```

## Generated Files

### main.js

The main process handles window management, system tray, and native APIs:

```javascript
const { app, BrowserWindow, Tray, Menu, globalShortcut, nativeImage } = require('electron');
const path = require('path');

let mainWindow = null;
let tray = null;

app.whenReady().then(() => {
  createWindow();
  createTray();
  registerShortcuts();
});

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile('index.html');
}

function createTray() {
  const icon = nativeImage.createFromPath(
    path.join(__dirname, 'assets/tray-icon.png')
  );
  tray = new Tray(icon.resize({ width: 16, height: 16 }));

  const contextMenu = Menu.buildFromTemplate([
    { label: 'Show App', click: () => mainWindow.show() },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() }
  ]);

  tray.setContextMenu(contextMenu);
  tray.on('click', () => mainWindow.show());
}

function registerShortcuts() {
  globalShortcut.register('CommandOrControl+Shift+P', () => {
    mainWindow.show();
    mainWindow.webContents.send('quick-capture');
  });
}

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});
```

### preload.js

The preload script safely exposes APIs to the renderer:

```javascript
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // Receive events from main process
  onQuickCapture: (callback) => {
    ipcRenderer.on('quick-capture', callback);
  },
  onWindowShow: (callback) => {
    ipcRenderer.on('window-show', callback);
  },

  // Send events to main process
  send: (channel, ...args) => {
    const validChannels = ['hide-window', 'show-notification'];
    if (validChannels.includes(channel)) {
      ipcRenderer.send(channel, ...args);
    }
  },

  // Request/response pattern
  invoke: (channel, ...args) => {
    const validChannels = ['get-app-path', 'read-file'];
    if (validChannels.includes(channel)) {
      return ipcRenderer.invoke(channel, ...args);
    }
  }
});
```

### Using Electron APIs in Stimulus

```ruby
# app/javascript/controllers/desktop_controller.rb
class DesktopController < Stimulus::Controller
  def connect
    return unless window.electronAPI

    # Listen for quick capture shortcut
    window.electronAPI.onQuickCapture do
      activateCamera()
    end
  end

  def hideWindow
    window.electronAPI.send("hide-window")
  end

  def showNotification(title, body)
    window.electronAPI.send("show-notification", { title: title, body: body })
  end
end
```

## System Tray

The generated `main.js` includes system tray support. Customize the tray menu:

```javascript
// In main.js
const contextMenu = Menu.buildFromTemplate([
  { label: 'Quick Capture', click: () => {
    mainWindow.show();
    mainWindow.webContents.send('quick-capture');
  }},
  { label: 'View Gallery', click: () => {
    mainWindow.show();
    mainWindow.webContents.send('navigate', '/photos');
  }},
  { type: 'separator' },
  { label: 'Preferences...', click: () => {
    // Open preferences window
  }},
  { type: 'separator' },
  { label: 'Quit', accelerator: 'CommandOrControl+Q', click: () => app.quit() }
]);
```

### Background Utility Mode

For menu bar utilities (no dock icon):

```javascript
// In main.js, before app.whenReady()
if (process.platform === 'darwin') {
  app.dock.hide();
}
```

## Global Shortcuts

Register system-wide keyboard shortcuts:

```javascript
// In main.js
function registerShortcuts() {
  // Quick capture from any app
  globalShortcut.register('CommandOrControl+Shift+P', () => {
    mainWindow.show();
    mainWindow.focus();
    mainWindow.webContents.send('quick-capture');
  });

  // Toggle window visibility
  globalShortcut.register('CommandOrControl+Shift+G', () => {
    if (mainWindow.isVisible()) {
      mainWindow.hide();
    } else {
      mainWindow.show();
    }
  });
}
```

## Packaging for Distribution

### Install electron-builder

```bash
npm install --save-dev electron-builder
```

### package.json configuration

```json
{
  "name": "my-app",
  "version": "1.0.0",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "package": "electron-builder",
    "package:mac": "electron-builder --mac",
    "package:win": "electron-builder --win",
    "package:linux": "electron-builder --linux"
  },
  "build": {
    "appId": "com.example.myapp",
    "productName": "My App",
    "directories": {
      "output": "release"
    },
    "mac": {
      "category": "public.app-category.productivity",
      "target": ["dmg", "zip"],
      "icon": "assets/icon.icns"
    },
    "win": {
      "target": ["nsis", "portable"],
      "icon": "assets/icon.ico"
    },
    "linux": {
      "target": ["AppImage", "deb"],
      "icon": "assets/icon.png",
      "category": "Utility"
    }
  }
}
```

### Build Commands

```bash
# All platforms (from macOS)
npm run package

# Specific platform
npm run package:mac
npm run package:win
npm run package:linux
```

### Output

```
dist/release/
├── My App-1.0.0.dmg           # macOS installer
├── My App-1.0.0-mac.zip       # macOS zip
├── My App Setup 1.0.0.exe     # Windows installer
├── My App 1.0.0.exe           # Windows portable
├── My App-1.0.0.AppImage      # Linux AppImage
└── my-app_1.0.0_amd64.deb     # Linux Debian package
```

## Code Signing

### macOS

For distribution outside the Mac App Store:

1. **Apple Developer Account** — $99/year
2. **Developer ID Certificate**
   ```bash
   # In Keychain Access, request certificate from Apple
   ```
3. **Notarization**
   ```json
   // In package.json build config
   "mac": {
     "hardenedRuntime": true,
     "gatekeeperAssess": false,
     "entitlements": "build/entitlements.mac.plist",
     "entitlementsInherit": "build/entitlements.mac.plist",
     "notarize": {
       "teamId": "YOUR_TEAM_ID"
     }
   }
   ```

### Windows

For trusted installations (no SmartScreen warning):

1. **Code Signing Certificate** — From DigiCert, Sectigo, etc.
2. **Configure in package.json**
   ```json
   "win": {
     "certificateFile": "path/to/cert.pfx",
     "certificatePassword": "password"
   }
   ```

## Auto-Updates

### Using electron-updater

```bash
npm install electron-updater
```

```javascript
// In main.js
const { autoUpdater } = require('electron-updater');

app.whenReady().then(() => {
  autoUpdater.checkForUpdatesAndNotify();
});

autoUpdater.on('update-available', () => {
  // Notify user
});

autoUpdater.on('update-downloaded', () => {
  autoUpdater.quitAndInstall();
});
```

Host updates on GitHub Releases, S3, or your own server.

## Troubleshooting

### "App can't be opened" (macOS)

Unsigned apps are blocked by Gatekeeper:

```bash
# For development only
xattr -cr "My App.app"
```

For distribution, sign and notarize your app.

### Native module errors

`better-sqlite3` requires rebuilding for Electron:

```bash
npm install electron-rebuild --save-dev
npx electron-rebuild
```

### DevTools

Open DevTools in the renderer:

```javascript
// In main.js
mainWindow.webContents.openDevTools();
```

Or use keyboard shortcut: `Cmd+Option+I` (macOS) / `Ctrl+Shift+I` (Windows/Linux)

## Comparison with Other Desktop Frameworks

| Aspect | Electron | Tauri | NW.js |
|--------|----------|-------|-------|
| Runtime | Chromium + Node.js | System WebView + Rust | Chromium + Node.js |
| Bundle size | ~150MB | ~3-10MB | ~150MB |
| Native access | Full Node.js | Rust backend | Full Node.js |
| Memory usage | Higher | Lower | Higher |
| Cross-platform | Excellent | Good | Excellent |

Electron is the most mature and widely used option. Tauri is smaller but requires Rust for native features.

## Limitations

- **Bundle size** — Apps include Chromium (~150MB minimum)
- **Memory usage** — Each app runs its own Chromium instance
- **Startup time** — Slower than native apps
- **Native look** — Requires extra work to match platform conventions
