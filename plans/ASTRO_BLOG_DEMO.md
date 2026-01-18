# Astro Blog Demo Plan

This plan covers selfhosting the framework transformers, creating an Astro blog demo, and deploying it via CI.

## Overview

Unlike other demos (Rails + Juntos), this demo:
- Uses **Astro** as the framework (not Rails)
- Is a **static site generator** (not a full-stack app)
- Demonstrates **`.astro.rb` → `.astro`** transformation
- Deploys as a **static site** to GitHub Pages

## Phase 1: Selfhost the Transformers

Add template compilers and component transformers to the selfhost build.

### Files to Transpile

| Ruby Source | JavaScript Output | Purpose |
|-------------|-------------------|---------|
| `lib/ruby2js/vue_template_compiler.rb` | `demo/selfhost/lib/vue_template_compiler.js` | Vue `{{ }}` expressions |
| `lib/ruby2js/vue_component_transformer.rb` | `demo/selfhost/lib/vue_component_transformer.js` | `.vue.rb` → `.vue` |
| `lib/ruby2js/svelte_template_compiler.rb` | `demo/selfhost/lib/svelte_template_compiler.js` | Svelte `{ }` expressions |
| `lib/ruby2js/svelte_component_transformer.rb` | `demo/selfhost/lib/svelte_component_transformer.js` | `.svelte.rb` → `.svelte` |
| `lib/ruby2js/astro_template_compiler.rb` | `demo/selfhost/lib/astro_template_compiler.js` | Astro `{ }` expressions |
| `lib/ruby2js/astro_component_transformer.rb` | `demo/selfhost/lib/astro_component_transformer.js` | `.astro.rb` → `.astro` |

### Implementation Steps

1. **Create transpile scripts** in `demo/selfhost/scripts/`:
   ```ruby
   # transpile_vue_template_compiler.rb
   require_relative '../../../lib/ruby2js'
   require_relative '../../../lib/ruby2js/vue_template_compiler'

   source = File.read("#{__dir__}/../../../lib/ruby2js/vue_template_compiler.rb")
   puts Ruby2JS.convert(source, filters: [:selfhost, :esm, :functions]).to_s
   ```

2. **Add to Rakefile** (`demo/selfhost/Rakefile`):
   ```ruby
   # Template compiler dependencies
   vue_template_deps = FileList["#{ROOT}/lib/ruby2js/vue_template_compiler.rb"]

   desc "Build vue_template_compiler.js"
   file "#{SELFHOST}/lib/vue_template_compiler.js" => [*vue_template_deps] do
     FileUtils.mkdir_p("#{SELFHOST}/lib")
     sh bundle_exec("ruby #{SELFHOST}/scripts/transpile_vue_template_compiler.rb > #{SELFHOST}/lib/vue_template_compiler.js")
   end

   # Repeat for other compilers...

   task :build_lib => [
     "#{SELFHOST}/lib/erb_compiler.js",
     "#{SELFHOST}/lib/migration_sql.js",
     "#{SELFHOST}/lib/seed_sql.js",
     "#{SELFHOST}/lib/vue_template_compiler.js",
     "#{SELFHOST}/lib/vue_component_transformer.js",
     "#{SELFHOST}/lib/svelte_template_compiler.js",
     "#{SELFHOST}/lib/svelte_component_transformer.js",
     "#{SELFHOST}/lib/astro_template_compiler.js",
     "#{SELFHOST}/lib/astro_component_transformer.js"
   ]
   ```

3. **Export from ruby2js package** (`demo/selfhost/package.json`):
   ```json
   {
     "exports": {
       "./lib/vue_template_compiler.js": "./lib/vue_template_compiler.js",
       "./lib/vue_component_transformer.js": "./lib/vue_component_transformer.js",
       "./lib/svelte_template_compiler.js": "./lib/svelte_template_compiler.js",
       "./lib/svelte_component_transformer.js": "./lib/svelte_component_transformer.js",
       "./lib/astro_template_compiler.js": "./lib/astro_template_compiler.js",
       "./lib/astro_component_transformer.js": "./lib/astro_component_transformer.js"
     }
   }
   ```

4. **Add tests to spec_manifest.json**:
   ```json
   {
     "partial": [
       "vue_template_compiler_spec.rb",
       "vue_component_transformer_spec.rb",
       "svelte_template_compiler_spec.rb",
       "svelte_component_transformer_spec.rb",
       "astro_template_compiler_spec.rb",
       "astro_component_transformer_spec.rb"
     ]
   }
   ```

### Definition of Done

- [ ] All 6 transformers transpile without errors
- [ ] Selfhost tests pass for transformer specs
- [ ] Exports work: `import { AstroComponentTransformer } from 'ruby2js/lib/astro_component_transformer.js'`

---

## Phase 2: Update Vite Plugin

Extend `vite-plugin-ruby2js` to handle `.vue.rb`, `.svelte.rb`, `.astro.rb` files.

### Implementation

```javascript
// packages/vite-plugin-ruby2js/src/index.js

import { VueComponentTransformer } from 'ruby2js/lib/vue_component_transformer.js';
import { SvelteComponentTransformer } from 'ruby2js/lib/svelte_component_transformer.js';
import { AstroComponentTransformer } from 'ruby2js/lib/astro_component_transformer.js';

export default function ruby2js(options = {}) {
  return {
    name: 'vite-plugin-ruby2js',

    async transform(code, id) {
      await ensurePrism();

      // Handle .vue.rb → .vue
      if (id.endsWith('.vue.rb')) {
        const result = VueComponentTransformer.transform(code, options);
        if (result.errors.length > 0) {
          throw new Error(`Vue transform errors: ${JSON.stringify(result.errors)}`);
        }
        return { code: result.component, map: null };
      }

      // Handle .svelte.rb → .svelte
      if (id.endsWith('.svelte.rb')) {
        const result = SvelteComponentTransformer.transform(code, options);
        if (result.errors.length > 0) {
          throw new Error(`Svelte transform errors: ${JSON.stringify(result.errors)}`);
        }
        return { code: result.component, map: null };
      }

      // Handle .astro.rb → .astro
      if (id.endsWith('.astro.rb')) {
        const result = AstroComponentTransformer.transform(code, options);
        if (result.errors.length > 0) {
          throw new Error(`Astro transform errors: ${JSON.stringify(result.errors)}`);
        }
        return { code: result.component, map: null };
      }

      // Existing .rb → .js handling
      if (!id.endsWith('.rb')) return null;
      // ... existing code ...
    },

    // Tell Vite to treat transformed files as their target type
    resolveId(source, importer) {
      if (source.endsWith('.vue.rb')) {
        return source.replace('.vue.rb', '.vue');
      }
      if (source.endsWith('.svelte.rb')) {
        return source.replace('.svelte.rb', '.svelte');
      }
      if (source.endsWith('.astro.rb')) {
        return source.replace('.astro.rb', '.astro');
      }
    }
  };
}
```

### Definition of Done

- [ ] `vite-plugin-ruby2js` transforms `.vue.rb` → `.vue`
- [ ] `vite-plugin-ruby2js` transforms `.svelte.rb` → `.svelte`
- [ ] `vite-plugin-ruby2js` transforms `.astro.rb` → `.astro`
- [ ] Plugin tests pass

---

## Phase 3: Create Astro Blog Demo

### Directory Structure

```
test/astro-blog/
├── create-astro-blog          # Creation script (executable)
└── Dockerfile                 # For containerized testing
```

### Demo App Structure (created by script)

```
astro-blog/
├── astro.config.mjs
├── package.json
├── src/
│   ├── content/
│   │   └── posts/
│   │       ├── first-post.md
│   │       ├── second-post.md
│   │       └── third-post.md
│   ├── layouts/
│   │   └── Layout.astro.rb
│   ├── components/
│   │   ├── PostCard.astro.rb
│   │   └── Header.astro.rb
│   └── pages/
│       ├── index.astro.rb
│       └── posts/
│           └── [...slug].astro.rb
└── public/
    └── favicon.ico
```

### Key Files

**`src/pages/index.astro.rb`**:
```ruby
@title = "My Blog"
@posts = Astro.glob("../content/posts/*.md")
@sorted_posts = @posts.sort_by { |p| p.frontmatter.date }.reverse
__END__
<Layout title={title}>
  <Header />
  <main>
    <h1>Recent Posts</h1>
    <div class="posts">
      {sorted_posts.map { |post|
        <PostCard post={post} />
      }}
    </div>
  </main>
</Layout>
```

**`src/pages/posts/[...slug].astro.rb`**:
```ruby
@slug = params[:slug]
@posts = await Astro.glob("../../content/posts/*.md")
@post = @posts.find { |p| p.file.include?(@slug) }
@content = @post.Content
__END__
<Layout title={post.frontmatter.title}>
  <Header />
  <article>
    <h1>{post.frontmatter.title}</h1>
    <time>{post.frontmatter.date}</time>
    <div class="content">
      <Content />
    </div>
  </article>
</Layout>
```

**`src/layouts/Layout.astro.rb`**:
```ruby
@title = props[:title]
__END__
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title}</title>
  <style>
    body { font-family: system-ui; max-width: 800px; margin: 0 auto; padding: 2rem; }
    .posts { display: grid; gap: 1rem; }
    article { line-height: 1.6; }
  </style>
</head>
<body>
  <slot />
</body>
</html>
```

**`src/components/PostCard.astro.rb`**:
```ruby
@post = props[:post]
@title = @post.frontmatter.title
@date = @post.frontmatter.date
@excerpt = @post.frontmatter.excerpt
@url = @post.url
__END__
<article class="post-card">
  <h2><a href={url}>{title}</a></h2>
  <time>{date}</time>
  <p>{excerpt}</p>
</article>
```

### Creation Script

#### Current State (Prebuild Script)

The current implementation uses a manual prebuild script because Astro doesn't support custom page extensions. This requires:
- A `scripts/prebuild.mjs` file with ~80 lines of transformation logic
- Modified npm scripts: `"dev": "npm run prebuild && astro dev"`
- No watch mode - must restart dev server for Ruby changes

See `test/astro-blog/create-astro-blog` for the full implementation.

#### Future State (With `ruby2js-astro` Integration)

**Dependency:** Requires `ruby2js-astro` package from FRAMEWORK_PARITY.md Phase 6.3

Once the Astro integration exists, the creation script simplifies dramatically:

```bash
#!/usr/bin/env bash
# Create an Astro blog demo with .astro.rb files
# Usage: create-astro-blog [app-name]

set -e
APP_NAME="${1:-astro-blog}"

echo "Creating Astro blog: $APP_NAME"

# Create Astro project
npm create astro@latest "$APP_NAME" -- --template minimal --no-git --skip-houston --yes
cd "$APP_NAME"

# Install ruby2js-astro integration (single package!)
npm install ruby2js-astro

# Update astro.config.mjs (one line added!)
cat > astro.config.mjs << 'CONFIG'
import { defineConfig } from 'astro/config';
import ruby2js from 'ruby2js-astro';

export default defineConfig({
  integrations: [ruby2js()]
});
CONFIG

# Create directory structure and content files
mkdir -p src/content/posts src/layouts src/components src/pages/posts public

# Create .astro.rb files...
# (content creation - unchanged)

echo "Done! Run: cd $APP_NAME && npm run dev"
```

**What's removed:**
- ❌ `scripts/prebuild.mjs` (80 lines) - handled by integration
- ❌ `npm pkg set scripts.prebuild=...` - not needed
- ❌ `npm pkg set scripts.dev="npm run prebuild && ..."` - not needed
- ❌ Manual Prism initialization - handled by integration

**What's gained:**
- ✅ Watch mode during `astro dev`
- ✅ Proper error reporting via Astro's build system
- ✅ Single package install instead of manual script setup

### Migration Path

When `ruby2js-astro` is published:

1. Update `test/astro-blog/create-astro-blog` to use the simplified script
2. Remove prebuild script generation
3. Update package.json script modifications
4. Test that watch mode works

### Definition of Done

**Current (with prebuild):**
- [x] `create-astro-blog` script creates working demo
- [x] `npm run dev` works locally (no watch)
- [x] `npm run build` produces static site
- [ ] Demo deploys to GitHub Pages

**Future (with integration):**
- [ ] `ruby2js-astro` package published
- [ ] Creation script simplified (no prebuild)
- [ ] Watch mode works during development
- [ ] Demo updated to use integration

---

## Phase 4: Add Integration Test

### Test File: `test/integration/astro_blog.test.mjs`

Unlike other demos (which test runtime behavior with SQLite), the Astro test validates:
1. Build completes without errors
2. Generated HTML is correct
3. Ruby expressions were transformed properly

```javascript
import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEMO_DIR = join(__dirname, 'workspace/astro-blog');

describe('Astro Blog Integration Tests', () => {
  beforeAll(() => {
    // Build should have already run during setup
    expect(existsSync(join(DEMO_DIR, 'dist'))).toBe(true);
  });

  describe('Build Output', () => {
    it('generates index.html', () => {
      const indexPath = join(DEMO_DIR, 'dist/index.html');
      expect(existsSync(indexPath)).toBe(true);

      const html = readFileSync(indexPath, 'utf-8');
      expect(html).toContain('<h1>Recent Posts</h1>');
      expect(html).toContain('post-card');
    });

    it('generates post pages', () => {
      const postPath = join(DEMO_DIR, 'dist/posts/first-post/index.html');
      expect(existsSync(postPath)).toBe(true);

      const html = readFileSync(postPath, 'utf-8');
      expect(html).toContain('<article>');
    });

    it('transforms snake_case to camelCase', () => {
      const indexPath = join(DEMO_DIR, 'dist/index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Should not contain snake_case attributes
      expect(html).not.toMatch(/post_card|sorted_posts/);
    });

    it('transforms Ruby blocks to arrow functions', () => {
      // Check intermediate .astro files (before Astro compiles to HTML)
      // Or check that the output reflects correct iteration
      const indexPath = join(DEMO_DIR, 'dist/index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Should have multiple post cards (from .map)
      const postCards = html.match(/class="post-card"/g);
      expect(postCards?.length).toBeGreaterThan(1);
    });
  });

  describe('Content', () => {
    it('renders markdown content', () => {
      const postPath = join(DEMO_DIR, 'dist/posts/first-post/index.html');
      const html = readFileSync(postPath, 'utf-8');

      // Should contain rendered markdown
      expect(html).toContain('</p>');
    });
  });
});
```

### Update `test/integration/setup.mjs`

Add astro-blog support:

```javascript
// Special handling for Astro demos (static site, not Rails)
if (demo === 'astro-blog') {
  console.log('\n4. Building Astro demo...');
  execSync('npm run build', {
    cwd: demoDir,
    stdio: 'inherit'
  });
  console.log('\n5. Setup complete!');
  return;
}
```

### Definition of Done

- [ ] `node setup.mjs astro-blog` works
- [ ] `npm test -- astro_blog.test.mjs` passes
- [ ] Tests validate transformation correctness

---

## Phase 5: Update CI Workflow

### Add Demo Creation Job

```yaml
create-astro-blog:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Set up Node
      uses: actions/setup-node@v4
      with:
        node-version: "24"

    - name: Create astro-blog demo
      run: |
        test/astro-blog/create-astro-blog artifacts/astro-blog
        tar -czf artifacts/demo-astro-blog.tar.gz -C artifacts astro-blog

    - name: Upload astro-blog demo
      uses: actions/upload-artifact@v4
      with:
        name: demo-astro-blog
        path: artifacts/demo-astro-blog.tar.gz
        retention-days: 7
```

### Update Integration Test Matrix

```yaml
integration-test:
  needs: [build-tarballs, create-blog, create-chat, create-photo-gallery, create-workflow, create-notes, create-astro-blog]
  strategy:
    matrix:
      demo: [blog, chat, photo_gallery, workflow, notes, astro_blog]
```

### Update build-site Job

```yaml
- name: Build Astro demo
  run: |
    echo "Building astro-blog for GitHub Pages..."
    base_path="/ruby2js/astro-blog/"
    (cd artifacts/astro-blog && npm install && npm run build -- --base "$base_path")

- name: Assemble site
  run: |
    # ... existing demos ...

    # Copy Astro demo (already built as static site)
    cp -r artifacts/astro-blog/dist _site/astro-blog

    # Update index.html to include Astro demo
    # ... add to demos list ...
```

### Update Index Page

```html
<div class="demo">
  <h2><a href="astro-blog/">Astro Blog</a></h2>
  <p>Static site with .astro.rb files. Ruby blocks to arrow functions.</p>
</div>
```

### Update 404.html

```javascript
const demos = ['blog', 'chat', 'notes', 'photo-gallery', 'workflow', 'astro-blog'];
```

### Definition of Done

- [ ] `create-astro-blog` job runs in CI
- [ ] Integration test passes in CI
- [ ] Astro demo deploys to `ruby2js.github.io/ruby2js/astro-blog/`
- [ ] Demo is accessible and functional

---

## Implementation Order

| Phase | Tasks | Dependencies |
|-------|-------|--------------|
| 1 | Selfhost transformers | None |
| 2 | Update Vite plugin | Phase 1 |
| 3 | Create demo | Phase 2 |
| 4 | Add integration test | Phase 3 |
| 5 | Update CI | Phases 3, 4 |

**Estimated effort:** 2-3 days

## Success Criteria

- [ ] All 6 transformers (Vue, Svelte, Astro × template + component) are selfhosted
- [ ] Vite plugin handles `.vue.rb`, `.svelte.rb`, `.astro.rb` files
- [ ] Astro blog demo builds and runs locally
- [ ] Integration tests validate correct transformation
- [ ] Demo is live at `ruby2js.github.io/ruby2js/astro-blog/`
- [ ] FRAMEWORK_PARITY.md Phase 4 marked complete with working demos
