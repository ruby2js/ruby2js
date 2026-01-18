---
order: 647
title: Tauri Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Build lightweight native desktop apps using Tauri's Rust backend and system WebView.

{% toc %}

## Overview

[Tauri](https://tauri.app/) creates native desktop applications with significantly smaller bundle sizes than Electron by using your system's WebView instead of bundling Chromium. The trade-off: native features are written in Rust rather than JavaScript.

**Advantages over Electron:**

| Aspect | Electron | Tauri |
|--------|----------|-------|
| Bundle size | ~150MB | ~3-10MB |
| Memory usage | Higher | Lower |
| Backend | Node.js (JavaScript) | Rust |
| WebView | Bundled Chromium | System WebView |

**Use cases:**

- Lightweight desktop apps
- Apps where bundle size matters
- Cross-platform distribution (macOS, Windows, Linux)
- Projects where you're comfortable with Rust for native features

## Prerequisites

1. **Rust toolchain** — Required for Tauri backend

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Tauri CLI** — Build and development tools

   ```bash
   cargo install tauri-cli
   ```

Platform-specific requirements:

- **macOS:** Xcode Command Line Tools (`xcode-select --install`)
- **Windows:** Visual Studio Build Tools with C++ workload
- **Linux:**
  ```bash
  sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file \
    libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
  ```

## Database Options

Since Tauri uses a system WebView (browser-like environment), compatible databases are:

| Adapter | Storage | Notes |
|---------|---------|-------|
| `sqljs` | SQLite/WASM | Recommended for offline apps |
| `pglite` | PostgreSQL/WASM | Full PostgreSQL in-browser |
| `neon` | Serverless PostgreSQL | Requires network |
| `turso` | SQLite edge | Requires network |
| `supabase` | PostgreSQL | Requires network |

For offline apps, use `sqljs` which stores data in IndexedDB.

## Build

```bash
# Build for Tauri
bin/juntos build -t tauri -d sqljs

# Navigate to dist
cd dist
```

## Generated Structure

After building, you'll have:

```
dist/
├── app/                    # Transpiled Rails app
├── lib/                    # Runtime
├── index.html              # WebView entry point
└── src-tauri/
    ├── tauri.conf.json     # Tauri configuration
    ├── icons/              # App icons (add your icons here)
    └── README.md           # Setup instructions
```

## Initialize Rust Project

The build generates `tauri.conf.json` but not the Rust source files. Initialize them with:

```bash
# From the dist directory
cargo tauri init
```

This creates the Rust project structure while preserving your existing configuration:

```
dist/
└── src-tauri/
    ├── tauri.conf.json     # Your generated config (preserved)
    ├── Cargo.toml          # Rust dependencies
    ├── build.rs            # Build script
    └── src/
        └── main.rs         # Rust entry point
```

## Development

Run the development server with hot reload:

```bash
cargo tauri dev
```

This starts:
1. Your Vite dev server (frontend)
2. The Tauri app window pointing to the dev server

## Using Tauri APIs in Stimulus

Access Tauri APIs from your Ruby controllers:

```ruby
# app/javascript/controllers/desktop_controller.rb
class DesktopController < Stimulus::Controller
  def connect
    return unless window.__TAURI__

    # Listen for events from Rust backend
    window.__TAURI__.event.listen("file-opened") do |event|
      handleFileOpened(event.payload)
    end
  end

  def openFile
    # Invoke a Rust command
    window.__TAURI__.core.invoke("open_file_dialog").then do |path|
      console.log("Selected:", path)
    end
  end

  def saveToFile(content)
    window.__TAURI__.core.invoke("save_file", { content: content })
  end
end
```

## Adding Rust Commands

To add custom native features, edit `src-tauri/src/main.rs`:

```rust
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}!", name)
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![greet])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

Call from JavaScript:

```ruby
# In a Stimulus controller
window.__TAURI__.core.invoke("greet", { name: "World" }).then do |message|
  console.log(message)  # "Hello, World!"
end
```

## App Icons

Generate icons from a source image:

```bash
cargo tauri icon path/to/app-icon.png
```

This creates all required icon sizes in `src-tauri/icons/`.

## Build for Distribution

```bash
cargo tauri build
```

Output locations:

- **macOS:** `src-tauri/target/release/bundle/dmg/`
- **Windows:** `src-tauri/target/release/bundle/nsis/`
- **Linux:** `src-tauri/target/release/bundle/appimage/`

## Configuration

The generated `tauri.conf.json` includes sensible defaults. Key options:

```json
{
  "productName": "My App",
  "identifier": "com.example.myapp",
  "build": {
    "frontendDist": "../dist",
    "devUrl": "http://localhost:5173"
  },
  "app": {
    "windows": [{
      "title": "My App",
      "width": 1200,
      "height": 800
    }]
  }
}
```

See [Tauri Configuration Reference](https://v2.tauri.app/reference/config/) for all options.

## Comparison with Electron

| Feature | Electron | Tauri |
|---------|----------|-------|
| **Generated files** | `main.js`, `preload.js` | `tauri.conf.json` only |
| **Native code** | JavaScript (Node.js) | Rust |
| **Ruby2JS generates** | All JavaScript | Frontend only |
| **Custom native features** | Edit generated JS | Write Rust |
| **Learning curve** | Lower (JS everywhere) | Higher (requires Rust) |

Choose Electron if you want Ruby2JS to generate everything. Choose Tauri if bundle size matters and you're comfortable with Rust for native features.

## Troubleshooting

### WebView not found (Linux)

Install WebKitGTK:

```bash
sudo apt install libwebkit2gtk-4.1-dev
```

### Rust compilation errors

Ensure you have the latest stable Rust:

```bash
rustup update stable
```

### Window not showing

Check `tauri.conf.json` has valid window configuration:

```json
"app": {
  "windows": [{
    "visible": true,
    "width": 800,
    "height": 600
  }]
}
```

## Resources

- [Tauri v2 Documentation](https://v2.tauri.app/)
- [Tauri Configuration Reference](https://v2.tauri.app/reference/config/)
- [Tauri GitHub Repository](https://github.com/tauri-apps/tauri)
- [Tauri Discord Community](https://discord.com/invite/tauri)

🧪 **Feedback requested** — [Share your experience](https://github.com/ruby2js/ruby2js/discussions)
