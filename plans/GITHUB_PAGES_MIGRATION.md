# GitHub Pages Migration Plan

## Overview

Migrate ruby2js.com hosting from Fly.io to GitHub Pages. The site is fully static (Bridgetown generates HTML, nginx serves it), making GitHub Pages a suitable and simpler alternative.

## Current Setup

- **Build**: Dockerfile with two stages (Ruby build, nginx serve)
- **Deployment**: Fly.io via `.github/workflows/fly-deploy.yml`
- **Domain**: ruby2js.com (DNS configuration unknown)
- **Build steps**:
  1. `bundle exec rake` - builds demo assets (Opal compilation, selfhost bundle)
  2. `bundle exec rake deploy` - builds Bridgetown static site
  3. Output: `docs/output/` directory

## Benefits of Migration

| Aspect     | Fly.io                        | GitHub Pages         |
| ---------- | ----------------------------- | -------------------- |
| Cost       | ~$0-5/month (auto-stop helps) | Free                 |
| Complexity | Dockerfile + fly.toml         | Single workflow file |
| CDN        | Single region (iad)           | Global CDN           |
| SSL        | Automatic                     | Automatic            |
| Build      | Remote Docker build           | GitHub Actions       |

## Implementation Steps

### Phase 1: Create GitHub Actions Workflow

Create `.github/workflows/github-pages.yml`:

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches:
      - master

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.4'
          bundler-cache: true

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'yarn'
          cache-dependency-path: docs/yarn.lock

      - name: Install docs dependencies
        working-directory: docs
        run: |
          bundle install
          yarn install

      - name: Install selfhost dependencies
        working-directory: demo/selfhost
        run: npm install

      - name: Build demo assets
        working-directory: docs
        run: bundle exec rake

      - name: Build site
        working-directory: docs
        env:
          BRIDGETOWN_ENV: production
        run: bundle exec rake deploy

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: docs/output

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

### Phase 2: Configure GitHub Pages

1. Go to repo Settings → Pages
2. Set Source to "GitHub Actions"
3. Custom domain: `ruby2js.com`
4. Enable "Enforce HTTPS"

### Phase 3: DNS Configuration

Ensure DNS records point to GitHub Pages:

```
# Apex domain (ruby2js.com)
A     @    185.199.108.153
A     @    185.199.109.153
A     @    185.199.110.153
A     @    185.199.111.153

# Subdomain (www.ruby2js.com)
CNAME www  ruby2js.github.io
```

### Phase 4: Verify and Cutover

1. Push workflow to a test branch first
2. Verify build succeeds in Actions tab
3. Test at `ruby2js.github.io` or preview URL
4. Verify custom domain works
5. Test critical paths:
   - Homepage loads
   - Documentation pages render
   - Opal demo works (`/demo/`)
   - Selfhost demo works (`/demo/selfhost/`)
   - `.wasm` files load correctly
   - Search functionality works

### Phase 5: Cleanup

1. Remove or disable `.github/workflows/fly-deploy.yml`
2. Optionally remove `Dockerfile` and `fly.toml`
3. Delete Fly.io app: `flyctl apps destroy ruby2js`

## Testing with act

[act](https://github.com/nektos/act) allows running GitHub Actions locally before pushing.

### Installation

```bash
# macOS
brew install act

# Linux
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

### Running the Workflow Locally

```bash
# List available jobs
act -l

# Dry run (show what would execute)
act -n

# Run the build job only (skip deploy - requires GitHub token)
act -j build

# Run with verbose output
act -j build -v

# Use a larger runner image (more compatible, ~18GB)
act -j build -P ubuntu-latest=catthehacker/ubuntu:full-latest
```

### act Configuration

Create `.actrc` in repo root for default options:

```
-P ubuntu-latest=catthehacker/ubuntu:act-latest
--container-architecture linux/amd64
```

### Limitations

- The `deploy` job requires GitHub Pages tokens (skip with `-j build`)
- The `actions/upload-pages-artifact` may behave differently locally
- Large runner images are slow to download initially

### Verifying Build Output

After running `act -j build`, check the output manually:

```bash
# The build output will be in docs/output/
ls -la docs/output/

# Test locally with a simple server
cd docs/output
python3 -m http.server 8000
# Visit http://localhost:8000
```

## Potential Issues

### URL Handling Differences

GitHub Pages has fixed trailing slash behavior. Current nginx config strips trailing slashes:

```nginx
rewrite ^(.+)/+$ $scheme://$http_host$1 permanent;
```

GitHub Pages will serve both `/docs/foo` and `/docs/foo/` without redirects. This is unlikely to cause problems but worth monitoring for SEO.

### MIME Types

GitHub Pages should handle `.mjs` and `.wasm` correctly. Verify the selfhost demo loads Prism WASM after migration.

### Cache Headers

nginx config sets `Cache-Control: no-cache, must-revalidate`. GitHub Pages uses its own caching strategy (typically aggressive caching with cache-busting via content hashes). Bridgetown likely handles this via asset fingerprinting.

## Rollback Plan

If issues arise after migration:

1. Re-enable fly-deploy.yml workflow
2. Push to trigger Fly.io deployment
3. Update DNS if changed
4. Disable GitHub Pages in repo settings

## Timeline

No specific timeline - implement when convenient. Migration can be done incrementally:

1. Add GitHub Pages workflow (runs in parallel with Fly.io)
2. Verify everything works
3. Switch DNS
4. Remove Fly.io resources
