# ruby2js-rails

Rails runtime adapters, targets, and build tools for Ruby2JS applications.

This package provides everything needed to run Rails-like Ruby code transpiled to JavaScript, supporting both browser and server environments.

## Installation

```bash
npm install ruby2js-rails
```

Or via URL (for the latest beta):

```bash
npm install https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz
```

## Bin Commands

| Command               | Description                                      |
| --------------------- | ------------------------------------------------ |
| `ruby2js-rails-dev`   | Development server with hot reload               |
| `ruby2js-rails-build` | Transpile Ruby to JavaScript                     |
| `ruby2js-rails-server`| Production server (Node.js)                      |

## Package Contents

### Database Adapters (`adapters/`)

| File                            | Runtime | Database                |
| ------------------------------- | ------- | ----------------------- |
| `active_record_base.mjs`        | All     | Base class for adapters |
| `active_record_sqljs.mjs`       | Browser | sql.js (SQLite WASM)    |
| `active_record_dexie.mjs`       | Browser | Dexie (IndexedDB)       |
| `active_record_pglite.mjs`      | Browser | PGlite (PostgreSQL)     |
| `active_record_better_sqlite3.mjs` | Node | better-sqlite3          |
| `active_record_pg.mjs`          | Node    | PostgreSQL (pg)         |
| `active_record_mysql2.mjs`      | Node    | MySQL (mysql2)          |
| `active_record_d1.mjs`          | Cloudflare | D1                   |

### Runtime Targets (`targets/`)

| Directory   | Description                          |
| ----------- | ------------------------------------ |
| `browser/`  | History API routing, DOM updates     |
| `node/`     | HTTP server (http.createServer)      |
| `bun/`      | HTTP server (Bun.serve)              |
| `deno/`     | HTTP server (Deno.serve)             |
| `cloudflare/` | Cloudflare Workers                 |

### Runtime Libraries

| File                | Description                     |
| ------------------- | ------------------------------- |
| `rails_base.js`     | Core Rails-like framework       |
| `rails_server.js`   | Server-side extensions          |
| `erb_runtime.mjs`   | ERB template helpers            |
| `phlex_runtime.mjs` | Phlex component runtime         |

### Build Tools

| File              | Description                              |
| ----------------- | ---------------------------------------- |
| `build.mjs`       | Transpile Ruby to JavaScript (selfhost)  |
| `dev-server.mjs`  | Hot reload development server            |
| `server.mjs`      | Production server entry point            |

## Usage

### In package.json

```json
{
  "scripts": {
    "dev": "ruby2js-rails-dev",
    "build": "ruby2js-rails-build",
    "start": "ruby2js-rails-server"
  },
  "dependencies": {
    "ruby2js-rails": "https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz"
  }
}
```

### Programmatic Usage

```javascript
import { SelfhostBuilder } from 'ruby2js-rails/build.mjs';

const builder = new SelfhostBuilder('./dist');
builder.build();
```

## Development

This package lives at `packages/ruby2js-rails/` in the Ruby2JS repository.

### Building build.mjs

The `build.mjs` file is transpiled from `lib/ruby2js/rails/builder.rb`:

```bash
cd demo/selfhost

# Development version (relative paths for local testing)
bundle exec rake build_mjs

# npm package version (imports from ruby2js package)
bundle exec rake build_mjs:npm
```

### Local Development

For local development, the demo uses a `file:` dependency that creates a symlink:

```json
{
  "dependencies": {
    "ruby2js-rails": "file:../../packages/ruby2js-rails"
  }
}
```

## See Also

- [Ruby2JS](https://www.ruby2js.com/) - The Ruby to JavaScript transpiler
- [ruby2js-on-rails demo](../../demo/ruby2js-on-rails/) - Example application
- [selfhost](../../demo/selfhost/) - Self-hosted Ruby2JS converter
