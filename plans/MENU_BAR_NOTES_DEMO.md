# Menu Bar Notes Demo - Electron System Tray

A focused demo showcasing Electron's system tray and global shortcuts with Juntos.

## Overview

| Demo | Pattern | What It Shows |
|------|---------|---------------|
| Blog | CRUD | Table stakes, Rails conventions |
| Chat | Real-time | Turbo Streams, WebSockets |
| Photo Gallery | Native API | Capacitor camera, binary storage |
| **Menu Bar Notes** | Desktop integration | System tray, global shortcuts, background app |

### The Story

> Build a desktop utility that's always one keystroke away. Lives in your menu bar, captures notes instantly, works even when the app isn't focused. Things browsers simply can't do.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Electron App                       │
│  ┌───────────────────────────────────────────────┐  │
│  │  Main Process                                 │  │
│  │  ├── Tray icon (menu bar)                     │  │
│  │  ├── Global shortcut (Cmd+Shift+N)            │  │
│  │  └── BrowserWindow (popup)                    │  │
│  └───────────────────────────────────────────────┘  │
│                        ↓                             │
│  ┌───────────────────────────────────────────────┐  │
│  │  Renderer Process                             │  │
│  │  ├── Ruby Stimulus Controller                 │  │
│  │  └── Notes UI (list + input)                  │  │
│  └───────────────────────────────────────────────┘  │
│                        ↓                             │
│  ┌───────────────────────────────────────────────┐  │
│  │  SQLite (better-sqlite3)                      │  │
│  │  └── notes: id, content, created_at           │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Data Model

### Note

Simple, append-only. No updates, no deletes.

```ruby
class Note < ApplicationRecord
  attribute :client_id, :string      # UUID (for future sync)
  attribute :content, :text
  attribute :created_at, :datetime

  validates :content, presence: true

  before_create do
    self.client_id ||= SecureRandom.uuid
    self.created_at ||= Time.current
  end
end
```

## Implementation

### Electron Main Process

```javascript
// main.js
const { app, BrowserWindow, Tray, Menu, globalShortcut, nativeImage } = require('electron');
const path = require('path');

let tray = null;
let mainWindow = null;

// Don't show in dock (macOS)
app.dock?.hide();

app.whenReady().then(() => {
  createTray();
  createWindow();
  registerShortcuts();
});

function createTray() {
  const icon = nativeImage.createFromPath(path.join(__dirname, 'assets/tray-icon.png'));
  tray = new Tray(icon.resize({ width: 16, height: 16 }));

  tray.setToolTip('Quick Notes');
  tray.on('click', toggleWindow);

  const contextMenu = Menu.buildFromTemplate([
    { label: 'Open Notes', click: toggleWindow },
    { label: 'Quit', click: () => app.quit() }
  ]);
  tray.setContextMenu(contextMenu);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 320,
    height: 400,
    show: false,
    frame: false,
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true
    }
  });

  mainWindow.loadFile('dist/index.html');

  // Hide instead of close
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

  // Tell renderer to focus input
  mainWindow.webContents.send('focus-input');
}

function registerShortcuts() {
  // Global shortcut works even when app isn't focused
  globalShortcut.register('CommandOrControl+Shift+N', () => {
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
  onFocusInput: (callback) => ipcRenderer.on('focus-input', callback),
  hideWindow: () => ipcRenderer.send('hide-window')
});
```

### Stimulus Controller (Ruby)

```ruby
class NotesController < Stimulus::Controller
  targets [:input, :list]

  def connect
    # Listen for focus event from main process
    window.electron.onFocusInput do
      inputTarget.focus
      inputTarget.select
    end

    loadNotes
  end

  def submit(event)
    event.preventDefault

    content = inputTarget.value.strip
    return if content.empty?

    # Save to SQLite
    note = Note.create(content: content)

    # Prepend to list
    prependNote(note)

    # Clear input
    inputTarget.value = ''

    # Hide window after save
    window.electron.hideWindow
  end

  def loadNotes
    notes = Note.order(created_at: :desc).limit(50)
    notes.each { |note| appendNote(note) }
  end

  private

  def prependNote(note)
    html = renderNote(note)
    listTarget.insertAdjacentHTML('afterbegin', html)
  end

  def appendNote(note)
    html = renderNote(note)
    listTarget.insertAdjacentHTML('beforeend', html)
  end

  def renderNote(note)
    <<~HTML
      <div class="note" id="note-#{note.id}">
        <p>#{note.content}</p>
        <time>#{note.created_at.strftime('%b %d, %I:%M %p')}</time>
      </div>
    HTML
  end
end
```

### View (ERB)

```erb
<%# app/views/notes/index.html.erb %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Quick Notes</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      background: #1a1a1a;
      color: #fff;
      border-radius: 8px;
      overflow: hidden;
    }

    .container {
      display: flex;
      flex-direction: column;
      height: 100vh;
    }

    .input-area {
      padding: 12px;
      border-bottom: 1px solid #333;
    }

    .input-area form {
      display: flex;
      gap: 8px;
    }

    .input-area input {
      flex: 1;
      padding: 8px 12px;
      border: none;
      border-radius: 6px;
      background: #333;
      color: #fff;
      font-size: 14px;
    }

    .input-area input:focus {
      outline: 2px solid #007aff;
    }

    .input-area button {
      padding: 8px 16px;
      border: none;
      border-radius: 6px;
      background: #007aff;
      color: #fff;
      font-size: 14px;
      cursor: pointer;
    }

    .notes-list {
      flex: 1;
      overflow-y: auto;
      padding: 8px;
    }

    .note {
      padding: 12px;
      margin-bottom: 8px;
      background: #2a2a2a;
      border-radius: 6px;
    }

    .note p {
      font-size: 14px;
      margin-bottom: 4px;
    }

    .note time {
      font-size: 11px;
      color: #888;
    }

    .empty {
      text-align: center;
      color: #666;
      padding: 40px;
    }
  </style>
</head>
<body>
  <div class="container" data-controller="notes">
    <div class="input-area">
      <form data-action="submit->notes#submit">
        <input
          type="text"
          data-notes-target="input"
          placeholder="Quick note... (Enter to save)"
          autofocus
        />
        <button type="submit">Save</button>
      </form>
    </div>

    <div class="notes-list" data-notes-target="list">
      <!-- Notes loaded by controller -->
    </div>
  </div>
</body>
</html>
```

## Build & Run

```bash
# Create the app
curl -sL .../create-menu-bar-notes | bash -s menu_bar_notes
cd menu_bar_notes

# Build for Electron
bin/juntos build -t electron -d better-sqlite3

# Run
cd dist
npm install
npm start
```

## Package for Distribution

```bash
# Install electron-builder
npm install --save-dev electron-builder

# Build distributable
npm run package

# Output:
# - macOS: dist/Menu Bar Notes.dmg
# - Windows: dist/Menu Bar Notes Setup.exe
# - Linux: dist/menu-bar-notes.AppImage
```

### electron-builder config

```json
{
  "name": "menu-bar-notes",
  "version": "1.0.0",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "package": "electron-builder"
  },
  "build": {
    "appId": "com.example.menubar-notes",
    "productName": "Menu Bar Notes",
    "mac": {
      "category": "public.app-category.productivity",
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

## Demo Flow

1. **Launch app** → Appears in menu bar (not dock)
2. **Click tray icon** → Popup appears below icon
3. **Or press Cmd+Shift+N** → Popup appears from anywhere
4. **Type note, press Enter** → Saved, popup closes
5. **Click tray again** → See all notes
6. **Notes persist** → Survive app restart (SQLite)

## What This Proves

| Capability | Demonstrated |
|------------|--------------|
| System tray | `Tray` API |
| Global shortcuts | `globalShortcut.register` |
| Frameless window | Custom popup UI |
| Position near tray | `tray.getBounds()` |
| Native SQLite | `better-sqlite3` (not WASM) |
| Background app | Runs without dock icon |
| IPC | Main ↔ Renderer communication |

## What This Doesn't Do (Yet)

- No server sync (local only)
- No search
- No delete/edit
- No categories/tags
- No rich text

These are intentionally deferred. This demo focuses on **Electron desktop integration**.

## Platform Notes

### macOS
- Tray icon appears in menu bar
- `app.dock.hide()` removes from dock
- Global shortcut: Cmd+Shift+N

### Windows
- Tray icon appears in system tray
- Global shortcut: Ctrl+Shift+N

### Linux
- Tray support varies by desktop environment
- May need `libappindicator` on some distros

## Future: Social Feed Integration

Like Photo Gallery, this becomes a building block:

```
Blog (text posts)
    +
Chat (real-time)
    +
Photo Gallery (Capacitor images)
    +
Menu Bar Notes (Electron quick capture)
    =
Cross-platform app with desktop widget
```

The `client_id` field enables future sync:

```ruby
# Notes created on desktop sync to mobile
Note.where('created_at > ?', last_sync_at)
```

## Files to Generate

```
menu_bar_notes/
├── main.js                    # Electron main process
├── preload.js                 # Context bridge
├── assets/
│   └── tray-icon.png          # 16x16 menu bar icon
├── app/
│   ├── models/
│   │   └── note.rb
│   ├── views/
│   │   └── notes/
│   │       └── index.html.erb
│   └── javascript/
│       └── controllers/
│           └── notes_controller.rb
├── config/
│   ├── routes.rb
│   └── database.yml
├── db/
│   └── schema.rb
└── package.json
```

## Implementation Checklist

### Phase 1: Basic Notes App (Window)

- [ ] Create Note model
- [ ] Create index view with form
- [ ] Create NotesController (Stimulus)
- [ ] Test in regular Electron window

### Phase 2: Tray Integration

- [ ] Add tray icon
- [ ] Create popup window (frameless)
- [ ] Position below tray
- [ ] Hide on blur

### Phase 3: Global Shortcut

- [ ] Register Cmd+Shift+N
- [ ] Show window on shortcut
- [ ] Focus input automatically

### Phase 4: Polish

- [ ] Add tray icon for dark/light mode
- [ ] Handle shortcut conflict gracefully
- [ ] Add "Quit" in context menu
- [ ] Test on macOS, Windows, Linux

### Phase 5: Documentation

- [ ] Create docs/src/_docs/juntos/demos/menu-bar-notes.md
- [ ] Add to demos index
- [ ] Create test/menu_bar_notes/create-menu-bar-notes script

## Success Criteria

1. **Tray icon works** - Visible in menu bar, click shows popup
2. **Global shortcut works** - Cmd+Shift+N from any app opens popup
3. **Notes persist** - Survive app restart (SQLite)
4. **Fast** - Popup appears instantly
5. **Unobtrusive** - No dock icon, hides on blur

## References

- [Electron Tray](https://www.electronjs.org/docs/latest/api/tray)
- [Electron globalShortcut](https://www.electronjs.org/docs/latest/api/global-shortcut)
- [Electron BrowserWindow](https://www.electronjs.org/docs/latest/api/browser-window)
- [better-sqlite3](https://github.com/WiseLibs/better-sqlite3)
- [electron-builder](https://www.electron.build/)
