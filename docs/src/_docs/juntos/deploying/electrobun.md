---
order: 648
title: Electrobun Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Build ultra-lightweight desktop apps using Electrobun's Bun backend and system WebView.

{% toc %}

## Overview

[Electrobun](https://blackboard.sh/electrobun/docs/) creates native desktop applications with the smallest bundle sizes of any desktop framework. It uses your system's WebView for rendering and [Bun](https://bun.sh/) (TypeScript) for the backend — no Rust required.

**Comparison with other desktop targets:**

| Aspect | Electron | Tauri | Electrobun |
|--------|----------|-------|------------|
| Bundle size | ~150MB | ~3-10MB | ~14MB |
| Startup time | 2-5s | ~500ms | <50ms |
| Update size | 100MB+ | ~10MB | ~14KB |
| Memory usage | Higher | Lower | Lowest |
| Backend | Node.js (JavaScript) | Rust | Bun (TypeScript) |
| WebView | Bundled Chromium | System WebView | System WebView |

**Use cases:**

- Desktop apps where startup time and update size matter
- Projects where you prefer TypeScript over Rust for native features
- Apps that benefit from Bun's fast runtime
- Cross-platform distribution (macOS, Windows, Linux)

**Platform support:** macOS 14+, Windows 11+, Ubuntu 22.04+

## Prerequisites

1. **Bun runtime** — Required for Electrobun backend

   ```bash
   curl -fsSL https://bun.sh/install | bash
   ```

2. **Electrobun CLI** — Build and development tools

   ```bash
   bun add -g electrobun
   ```

## Database Options

Since Electrobun uses a system WebView (browser-like environment), compatible databases are:

| Adapter | Storage | Notes |
|---------|---------|-------|
| `sqljs` | SQLite/WASM | Recommended for offline apps |
| `pglite` | PostgreSQL/WASM | Full PostgreSQL in-browser |
| `neon` | Serverless PostgreSQL | Requires network |
| `turso` | SQLite edge | Requires network |

For offline apps, use `sqljs` which stores data in IndexedDB.

## Build

```bash
# Build for Electrobun
bin/juntos build -t electrobun -d sqljs

# Navigate to dist
cd dist
```

## Generated Structure

After building, you'll have:

```
dist/
├── app/                        # Transpiled Rails app
├── lib/                        # Runtime
├── index.html                  # WebView entry point
└── electrobun.config.ts        # Electrobun configuration
```

## Development

Run the development server:

```bash
bunx --bun vite
```

Vite works out of the box with Bun — the existing Juntos Vite pipeline works unchanged.

## Electrobun's Typed RPC

Unlike Electron's channel-based IPC or Tauri's Rust commands, Electrobun uses a typed RPC model. You define a shared TypeScript type that both sides reference:

```typescript
// Shared RPC type
type AppRPC = {
  bun: {
    requests: { readFile: (args: {path: string}) => string };
    messages: { logToBun: (args: {msg: string}) => void };
  };
  webview: {
    requests: { getFormData: () => object };
    messages: { showNotification: (args: {title: string}) => void };
  };
};
```

The Juntos runtime sets up a default RPC schema. Override `Application.defineRPC()` to add custom commands.

## Using Electrobun APIs in Stimulus

Access Electrobun APIs from your Ruby controllers:

```ruby
# app/javascript/controllers/desktop_controller.rb
class DesktopController < Stimulus::Controller
  def connect
    return unless Application.isElectrobun

    # Listen for events bridged from Bun process
    document.addEventListener("electrobun:quick-capture") do
      activateCamera()
    end
  end

  def openFile
    # Invoke a Bun-side function (async)
    Application.invoke("openFileDialog", {}).then do |path|
      console.log("Selected:", path)
    end
  end

  def logMessage(msg)
    # Fire-and-forget message to Bun process
    Application.send("logToBun", { msg: msg })
  end
end
```

## Custom RPC Handlers

To add custom Bun-side commands, extend the Application class:

```ruby
# app/javascript/application.rb
class Application < Application
  def self.defineRPC(electroview)
    electroview.defineRPC(
      handlers: {
        requests: {
          readFile: ->(args) { Bun.file(args.path).text() }
        },
        messages: {
          logToBun: ->(args) { console.log(args.msg) }
        }
      }
    )
  end
end
```

## Runtime Detection

Electrobun injects `window.__electrobunWindowId` into every webview automatically. The runtime detects this:

```ruby
if Application.isElectrobun
  # Electrobun-specific code
end
```

## Build for Distribution

```bash
# From the dist directory
electrobun build
```

Electrobun uses bsdiff-based updates, producing patches as small as ~14KB for incremental updates.

## Configuration

The generated `electrobun.config.ts` includes sensible defaults:

```typescript
export default {
  name: "My App",
  identifier: "com.example.myapp",
  mainEntry: "bun/index.ts",
  views: {
    "main-ui": {
      entry: "index.html"
    }
  },
  window: {
    width: 1200,
    height: 800,
    title: "My App"
  }
};
```

See [Electrobun Configuration](https://blackboard.sh/electrobun/docs/) for all options.

## Comparison with Electron and Tauri

| Feature | Electron | Tauri | Electrobun |
|---------|----------|-------|------------|
| **Generated files** | `main.js`, `preload.js` | `tauri.conf.json` | `electrobun.config.ts` |
| **Native code** | JavaScript (Node.js) | Rust | TypeScript (Bun) |
| **IPC model** | Channel strings | Command names | Typed RPC |
| **Ruby2JS generates** | All JavaScript | Frontend only | Frontend only |
| **Custom native features** | Edit generated JS | Write Rust | Write TypeScript |
| **Learning curve** | Lower (JS everywhere) | Higher (requires Rust) | Low (TypeScript) |

Choose Electron if you want Ruby2JS to generate everything. Choose Tauri if bundle size matters and you know Rust. Choose Electrobun if you want the smallest bundles with a TypeScript backend.

## Troubleshooting

### Bun not found

Install Bun:

```bash
curl -fsSL https://bun.sh/install | bash
```

### WebView not rendering

Verify your system meets the minimum requirements:
- macOS 14+ (Sonoma or later)
- Windows 11+
- Ubuntu 22.04+

### RPC not connecting

Ensure `Electroview` is initialized before making RPC calls. The Juntos runtime handles this in `Application.start()`, but custom initialization may need to await it:

```ruby
Application.start().then do
  # Safe to use RPC here
  Application.invoke("myCommand", {})
end
```

## Resources

- [Electrobun Documentation](https://blackboard.sh/electrobun/docs/)
- [Electrobun GitHub](https://github.com/blackboardsh/electrobun)
- [BrowserWindow API](https://blackboard.sh/electrobun/docs/apis/browser-window/)
- [Bun Runtime](https://bun.sh/)
