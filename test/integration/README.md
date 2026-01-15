# Integration Tests

Runtime integration tests for Ruby2JS demos using Vitest and better-sqlite3 with in-memory databases.

## Overview

These tests validate that the published tarballs from [releases](https://ruby2js.github.io/ruby2js/releases/) work correctly by:

1. Downloading demo tarballs and npm packages
2. Building the demo with `better-sqlite3` + `node` target
3. Running scenarios against an in-memory SQLite database

## Quick Start

```bash
cd test/integration

# Install test dependencies
npm install

# Setup: download tarballs and build demo
npm run setup

# Run tests
npm test
```

## Setup Options

```bash
# Download everything from GitHub Pages releases (default)
npm run setup

# Use local artifacts for everything
# (requires: bundle exec rake -f demo/selfhost/Rakefile release + demo tarball)
npm run setup -- --local

# Download demo tarball, use local npm package tarballs
# (requires: bundle exec rake -f demo/selfhost/Rakefile release)
npm run setup -- --local-packages

# Setup a different demo
npm run setup -- chat
npm run setup -- --local-packages blog
```

### Source Modes

| Mode | Demo Source | NPM Packages | Use Case |
|------|-------------|--------------|----------|
| (default) | GitHub releases | GitHub releases | Validate published releases |
| `--local` | local artifacts | local artifacts | Full local testing |
| `--local-packages` | GitHub releases | local artifacts | Test package fixes quickly |

## What's Tested

### Model Operations
- Create, read, update, delete (CRUD)
- Validations (presence, length)
- Associations (has_many, belongs_to)
- Query interface (where, order, limit, first, count)

### Controller Actions
- Index listing
- Show individual record
- Create new records
- (Extensible for update, destroy)

## Architecture

```
test/integration/
├── package.json       # vitest, better-sqlite3 dependencies
├── vitest.config.mjs  # Test configuration
├── setup.mjs          # Downloads tarballs, builds demo
├── blog.test.mjs      # Blog demo scenarios
└── workspace/         # Created by setup.mjs
    └── blog/
        └── dist/      # Built demo (what tests import)
```

## Adding Tests for Other Demos

1. Run setup with the demo name: `node setup.mjs chat`
2. Create a test file: `chat.test.mjs`
3. Import from `workspace/chat/dist/`

## CI Integration

These tests can be added to CI after the build-tarballs job:

```yaml
integration-test:
  needs: [build-tarballs]
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
    - uses: ruby/setup-ruby@v1
    - name: Download tarballs
      uses: actions/download-artifact@v4
      with:
        name: tarballs
        path: artifacts/tarballs
    - name: Run integration tests
      run: |
        cd test/integration
        npm install
        node setup.mjs --local
        npm test
```
