# Rails-in-JS Demo

A Rails-like blog application running entirely in JavaScript. Ruby source files are transpiled to JavaScript via Ruby2JS, demonstrating that idiomatic Rails code can run in the browser.

## Quick Start

```bash
# Install dependencies
npm install

# Start dev server with hot reload
npm run dev

# Open http://localhost:3000
```

## Available Commands

| Command | Description |
|---------|-------------|
| `npm run dev` | Start dev server with hot reload (Ruby transpilation) |
| `npm run dev -- --selfhost` | Dev server using JS-based transpilation (experimental) |
| `npm run build` | One-shot build (transpile all Ruby files) |
| `npm run start` | Serve with npx serve (no hot reload) |

## How It Works

```
app/models/*.rb          → dist/models/*.js
app/controllers/*.rb     → dist/controllers/*.js
app/views/*.html.erb     → dist/views/erb/*.js
config/*.rb              → dist/config/*.js
db/*.rb                  → dist/db/*.js
```

Ruby source files in `app/`, `config/`, and `db/` are transpiled to JavaScript using Ruby2JS with Rails-specific filters. The transpiled JavaScript runs in the browser with sql.js (SQLite compiled to WebAssembly) as the database.

## Development Workflow

1. Start `npm run dev`
2. Edit any `.rb` or `.erb` file in `app/`, `config/`, or `db/`
3. Save the file
4. Browser automatically reloads with changes

## Project Structure

```
rails-in-js/
├── app/
│   ├── controllers/      # Ruby controller classes
│   ├── helpers/          # Ruby helper modules
│   ├── models/           # Ruby ActiveRecord-style models
│   └── views/articles/   # ERB templates
├── config/
│   ├── routes.rb         # Rails-style routing
│   └── schema.rb         # Database schema
├── db/
│   └── seeds.rb          # Seed data
├── lib/
│   └── rails.js          # JavaScript runtime (ApplicationRecord, etc.)
├── dist/                 # Generated JavaScript (git-ignored)
├── scripts/
│   └── build.rb          # Ruby transpilation script
├── dev-server.mjs        # Hot reload dev server
├── index.html            # Entry point
└── package.json
```

## Sourcemaps

The build generates sourcemaps so you can debug Ruby in the browser:

1. Open DevTools → Sources
2. Find your `.rb` files (e.g., `app/models/article.rb`)
3. Set breakpoints directly in Ruby code
4. Step through Ruby source when debugging

## Known Limitations

- Database resets on page reload (IndexedDB persistence not yet implemented)
- `--selfhost` mode falls back to Ruby (JS-based Rails filters not yet available)

## See Also

- [Rails-in-JS Plan](../../plans/RAILS_IN_JS.md) - Full project plan and roadmap
- [Ruby2JS](https://www.ruby2js.com/) - The transpiler powering this demo
