# Ruby2JS Tests

This directory contains test scripts and demo creation scripts for Ruby2JS.

## Demo Creation Scripts

Each subdirectory contains a script to create a sample Rails application:

| Script | Description |
|--------|-------------|
| `blog/create-blog` | Blog with articles and comments (CRUD, nested routes) |
| `chat/create-chat` | Chat app (Turbo Streams, Stimulus) |
| `photo_gallery/create-photo-gallery` | Photo gallery (getUserMedia camera integration) |
| `workflow/create-workflow` | Workflow builder (React Flow integration) |

### Creating a Demo

```bash
# Create in a specific directory
test/blog/create-blog my-blog

# Or use default name
test/blog/create-blog
```

## Smoke Tests

The smoke test (`smoke-test.mjs`) compares Ruby and selfhost (JavaScript) builds to ensure they produce identical output.

### Running Smoke Tests Locally

From a clean git clone:

```bash
# 1. Clone and enter repo
git clone https://github.com/ruby2js/ruby2js.git
cd ruby2js

# 2. Install Ruby dependencies
bundle install

# 3. Install npm dependencies for selfhost and juntos
(cd demo/selfhost && npm install)
(cd packages/juntos && npm install)

# 4. Build tarballs (creates artifacts/tarballs/)
bundle exec rake -f demo/selfhost/Rakefile release

# 5. Create a demo (e.g., chat)
test/chat/create-chat artifacts/chat

# 6. Install ruby2js packages from tarballs
npm install artifacts/tarballs/ruby2js-beta.tgz artifacts/tarballs/juntos-beta.tgz artifacts/tarballs/juntos-dev-beta.tgz

# 7. Run smoke test
node test/smoke-test.mjs artifacts/chat --database dexie
```

### Smoke Test Options

```
Usage: node test/smoke-test.mjs <demo-directory> [options]

Options:
  --database, -db  Database adapter (dexie, sqljs, sqlite)
  --target, -t     Build target (node, browser)
  --diff, -d       Show unified diff for content differences

Examples:
  node test/smoke-test.mjs demo/blog
  node test/smoke-test.mjs demo/blog --database dexie
  node test/smoke-test.mjs demo/chat --database sqlite --diff
  node test/smoke-test.mjs demo/blog --target browser --database dexie
```

### What the Smoke Test Checks

1. **Ruby build** - Builds the demo using the Ruby SelfhostBuilder
2. **Selfhost build** - Builds using the JavaScript SelfhostBuilder
3. **JS syntax check** - Validates all generated JS files have valid syntax
4. **Common issues check** - Looks for Ruby-isms that shouldn't appear in JS
5. **Build comparison** - Ensures Ruby and selfhost builds produce identical output
6. **Import resolution** - Verifies all relative imports resolve correctly

## Dockerfile

The `Dockerfile` builds all demos for browser deployment with nginx:

```bash
cd test
docker build -t ruby2js-demos .
docker run --rm -p 8080:80 ruby2js-demos
# Open http://localhost:8080
```
