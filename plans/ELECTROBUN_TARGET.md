# Electrobun Target Plan

Add [Electrobun](https://blackboard.sh/electrobun/docs/) as a deployment target for Juntos, enabling ultra-lightweight desktop applications with TypeScript on both sides.

**Issue:** [#300](https://github.com/ruby2js/ruby2js/issues/300)

## Why Electrobun

Electrobun is a desktop app framework that uses Bun (not Node.js) for the main process and system WebViews for rendering. Compared to the existing desktop targets:

| Metric | Electron | Tauri | Electrobun |
|--------|----------|-------|------------|
| Bundle size | ~150MB | ~25MB | ~14MB |
| Startup time | 2-5s | ~500ms | <50ms |
| Update size | 100MB+ | ~10MB | ~14KB |
| Memory | 100-200MB | 30-50MB | 15-30MB |
| Backend language | JavaScript (Node) | Rust | TypeScript (Bun) |

The TypeScript backend is the key differentiator vs Tauri — no Rust required. The Bun runtime gives it a significant performance edge over Electron.

**Platform support:** macOS 14+, Windows 11+, Ubuntu 22.04+ (officially).

## Architecture Comparison

### Electron (current)
- Main process: Node.js
- Renderer: Bundled Chromium
- IPC: `ipcMain`/`ipcRenderer` via channel strings, `contextBridge` + `preload.js`
- Detection: `window.electronAPI` global
- Build: Vite + electron-builder

### Tauri (current)
- Main process: Rust
- Renderer: System WebView
- IPC: `window.__TAURI__.core.invoke("command", args)` — calls Rust functions
- Detection: `window.__TAURI__` global
- Build: Vite + `cargo tauri build`

### Electrobun (proposed)
- Main process: Bun (TypeScript)
- Renderer: System WebView
- IPC: Typed RPC via `Electroview` class — no global, no channel strings
- Detection: No global API object (needs alternative approach)
- Build: Bun bundler + `electrobun.config.ts`

## Electrobun API Surface

### Bun-side (Main Process)

| API | Import | Purpose |
|-----|--------|---------|
| `BrowserWindow` | `electrobun/bun` | Window management (create, resize, move, minimize, maximize, fullscreen, always-on-top) |
| `BrowserView` | `electrobun/bun` | Webview creation, RPC definition |
| `ApplicationMenu` | `electrobun/bun` | Native menu bars (roles, accelerators, submenus) |
| `ContextMenu` | `electrobun/bun` | Native right-click menus |
| `Tray` | `electrobun/bun` | System tray icons with menus |
| `Updater` | `electrobun/bun` | bsdiff-based auto-updates (~14KB patches) |
| `Electrobun.events` | `electrobun/bun` | Global event system |

### Browser-side (Renderer)

| API | Import | Purpose |
|-----|--------|---------|
| `Electroview` | `electrobun/view` | Initialize browser APIs, set up RPC handlers |
| `<electrobun-webview>` | HTML tag | Embedded webviews (OOPIF) |

### Typed RPC Model

Electrobun's IPC is fundamentally different from Electron and Tauri. Instead of channel strings or command names, you define a shared TypeScript type:

```typescript
// Shared type (both sides reference this)
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

// Bun side
const rpc = BrowserView.defineRPC<AppRPC>({
  handlers: {
    requests: { readFile: ({path}) => Bun.file(path).text() },
    messages: { logToBun: ({msg}) => console.log(msg) }
  }
});
const win = new BrowserWindow({ url: "views://main-ui/index.html", rpc });

// Browser side
const rpc = Electroview.defineRPC<AppRPC>({
  handlers: {
    requests: { getFormData: () => ({ ... }) },
    messages: { showNotification: ({title}) => alert(title) }
  }
});
const electrobun = new Electroview({ rpc });

// Call Bun from browser:
electrobun.rpc.request.readFile({path: "/tmp/data.txt"}).then(content => ...);
electrobun.rpc.send.logToBun({msg: "hello"});
```

## Implementation Analysis

### Mechanical (copy-and-adapt)

**1. Pragma filter** (`lib/ruby2js/filter/pragma.rb`)

Add to `PRAGMAS`:
```ruby
'electrobun' => :target_electrobun,
```

Add to `TARGET_PRAGMAS`:
```ruby
[:target_electrobun, 'electrobun'],
```

**2. Target arrays** (multiple files in `packages/juntos-dev/`)

- `cli.mjs` — Add `'electrobun'` to database compatibility matrix (similar to Tauri: `sqljs`, `pglite`, `neon`, `turso`)
- `vite.mjs` — Add to `browserTargets` arrays, add Rollup externals case for `electrobun/bun`, `electrobun/view`
- `transform.mjs` — Add to `browserTargets`; do NOT add to `nodeTargets` (Electrobun uses Bun, not Node.js)

**3. Documentation** (`docs/src/_docs/juntos/deploying/electrobun.md`)

Follow the Electron/Tauri doc structure: overview, prerequisites, database options, build, project structure, API usage from Stimulus, distribution.

### Non-Trivial — Requires Design Decisions

**1. Runtime target: RPC bridging**

The existing Electron and Tauri targets wrap a global API object:

```javascript
// Current pattern (Electron)
static get isElectron() {
  return typeof window.electronAPI !== 'undefined';
}
static sendToMain(channel, ...args) {
  this.electronAPI.send(channel, ...args);
}
```

Electrobun has no global. The `Electroview` class must be instantiated with an RPC schema. The runtime target needs to:

1. Create and manage an `Electroview` singleton
2. Define a default RPC schema that covers common Juntos operations (or let the user extend it)
3. Bridge RPC events into DOM custom events so Stimulus controllers can listen (matching the existing `electron:*` / `tauri:*` pattern)

**Proposed approach:**

```javascript
// packages/juntos/targets/electrobun/rails.js
import { Electroview } from "electrobun/view";
import { Application as BrowserApplication } from '../browser/rails.js';

export class Application extends BrowserApplication {
  static #electrobun = null;

  static get isElectrobun() {
    // Detection: check for electrobun view module availability
    return typeof Electroview !== 'undefined';
  }

  static get electrobun() {
    return this.#electrobun;
  }

  static async start() {
    if (this.isElectrobun) {
      this.#electrobun = new Electroview({ rpc: this.defineRPC() });
      this.setupElectrobunListeners();
    }
    return super.start();
  }

  // Default RPC — apps override this for custom commands
  static defineRPC() {
    return Electroview.defineRPC({
      handlers: {
        requests: {},
        messages: {
          quickCapture: () => {
            document.dispatchEvent(new CustomEvent('electrobun:quick-capture'));
          },
          navigate: ({path}) => {
            document.dispatchEvent(new CustomEvent('electrobun:navigate', {detail: {path}}));
          }
        }
      }
    });
  }

  // Send request to Bun main process
  static async invoke(method, args) {
    return this.#electrobun?.rpc.request[method]?.(args);
  }

  // Send fire-and-forget message to Bun main process
  static send(method, args) {
    this.#electrobun?.rpc.send[method]?.(args);
  }
}
```

**Ruby usage from Stimulus controllers:**

```ruby
class DesktopController < Stimulus::Controller
  def connect
    return unless Application.isElectrobun

    # Listen for events bridged from Bun process
    document.addEventListener("electrobun:quick-capture") do
      activateCamera()
    end
  end

  def openFile
    # Invoke a Bun-side function
    Application.invoke("openFileDialog", {}).then do |path|
      console.log("Selected:", path)
    end
  end
end
```

**2. Build pipeline: Vite vs Bun bundler**

Electrobun uses Bun's bundler and its own CLI (`bunx electrobun init`, `bun start`), not Vite. Options:

- **Option A: Vite output → Electrobun input.** Use Vite to build the frontend as usual, then configure `electrobun.config.ts` to point at the Vite output. Electrobun's `url` option can load from `views://` which maps to bundled files. This keeps the existing Juntos Vite pipeline intact.

- **Option B: Replace Vite with Bun bundler.** Use Bun's built-in bundler for the Electrobun target. Simpler for Electrobun but diverges from all other Juntos targets.

- **Option C: Generate electrobun.config.ts alongside Vite config.** `juntos build -t electrobun` generates both, letting Electrobun's CLI handle the final packaging while Vite handles the Ruby2JS transpilation.

**Recommendation: Option A** (or C as refinement). Vite handles the Ruby-to-JS transpilation and bundling; Electrobun's config points at the Vite output directory. This minimizes changes to the existing build system.

**3. Asset URL scheme**

Electrobun loads bundled assets via `views://` instead of relative paths or `file://`. The build system would need to rewrite asset references in the generated HTML/JS. This is similar to how Capacitor rewrites for `capacitor://localhost` — check if that pattern exists and can be reused.

**4. Runtime detection**

Without a global like `window.__TAURI__`, detection options:
- Import-time: If `electrobun/view` import succeeds, we're in Electrobun (module availability)
- Build-time: The Juntos build sets a flag (e.g., `globalThis.__ELECTROBUN__ = true`)
- Environment: Check for Electrobun-specific globals that may exist but aren't documented yet

**Recommendation:** Build-time flag injected by the Vite/build config, similar to how frameworks use `import.meta.env`.

## Risks and Open Questions

1. **Maturity** — Electrobun is newer than Electron and Tauri. API stability is uncertain. Worth waiting for a stable release before investing heavily.

2. **Bun dependency** — Requires Bun runtime installed. Not as ubiquitous as Node.js. However, Juntos already supports Bun as a server target.

3. **RPC schema extensibility** — How do users add custom Bun-side commands? The runtime target needs a clean extension point (override `defineRPC()`).

4. **Vite compatibility** — Needs verification that Vite-bundled output works correctly when loaded via Electrobun's `views://` scheme.

5. **No `preload.js` equivalent** — Electron's preload script runs before page scripts and can set up APIs. Electrobun's `preload` option exists on `BrowserWindow` but works differently (runs after HTML parsing). Need to verify this is sufficient for the Juntos runtime initialization.

## Implementation Order

1. **Pragma + target arrays** — Mechanical, low risk, enables `# Pragma: electrobun` immediately
2. **Runtime target** — `packages/juntos/targets/electrobun/rails.js` with the Electroview singleton pattern
3. **Build config generation** — `electrobun.config.ts` template in `juntos build -t electrobun`
4. **Vite integration** — Verify Vite output + `views://` scheme works, add Rollup externals
5. **Documentation** — Deployment guide with prerequisites, build steps, Stimulus examples
6. **Demo** — Port an existing demo (blog or notes) to Electrobun target

## References

- [Electrobun Documentation](https://blackboard.sh/electrobun/docs/)
- [Electrobun GitHub](https://github.com/blackboardsh/electrobun)
- [BrowserWindow API](https://blackboard.sh/electrobun/docs/apis/browser-window/)
- [Architecture Overview](https://blackboard.sh/electrobun/docs/guides/architecture/overview/)
- [Existing Electron target](../packages/juntos/targets/electron/rails.js)
- [Existing Tauri target](../packages/juntos/targets/tauri/rails.js)
