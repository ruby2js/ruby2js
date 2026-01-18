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

- [x] All 6 transformers transpile without errors
- [x] Selfhost tests pass for transformer specs
- [x] Exports work: `import { AstroComponentTransformer } from 'ruby2js/lib/astro_component_transformer.js'`

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

- [x] `vite-plugin-ruby2js` transforms `.vue.rb` → `.vue`
- [x] `vite-plugin-ruby2js` transforms `.svelte.rb` → `.svelte`
- [x] `vite-plugin-ruby2js` transforms `.astro.rb` → `.astro`
- [x] Plugin tests pass

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
- [x] Demo deploys to GitHub Pages

**Future (with integration):**
- [x] `ruby2js-astro` package published
- [x] Creation script simplified (no prebuild)
- [x] Watch mode works during development
- [x] Demo updated to use integration

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

- [x] `node setup.mjs astro_blog` works
- [x] `npm test -- astro_blog.test.mjs` passes
- [x] Tests validate transformation correctness

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

- [x] `create-astro-blog` job runs in CI
- [x] Integration test passes in CI
- [x] Astro demo deploys to `ruby2js.github.io/ruby2js/astro-blog/`
- [x] Demo is accessible and functional

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

## Success Criteria (Phases 1-5)

- [x] All 6 transformers (Vue, Svelte, Astro × template + component) are selfhosted
- [x] Vite plugin handles `.vue.rb`, `.svelte.rb`, `.astro.rb` files
- [x] Astro blog demo builds and runs locally
- [x] Integration tests validate correct transformation
- [x] Demo is live at `ruby2js.github.io/ruby2js/astro-blog/`
- [x] FRAMEWORK_PARITY.md Phase 6 marked complete with working packages

---

## Phase 6: Full-Stack Demo with ActiveRecord and ISR

### Vision

Replace the current markdown-based astro-blog demo with a full-stack demonstration that proves the documentation at https://www.ruby2js.com/docs/juntos/coming-from/astro is real and working.

**Note:** The existing Rails blog demo remains unchanged. This phase evolves only the astro-blog demo into a self-contained app with both authoring and publishing capabilities via Astro islands.

### Architecture: Self-Contained Astro App

```
┌─────────────────────────────────────────────────────────────┐
│                     Astro Blog Demo                          │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Static Shell (Astro SSG)                │    │
│  │  - Landing page (/)                                  │    │
│  │  - About page (/about)                               │    │
│  │  - Post list shell (/posts)                          │    │
│  │  - Post detail shell (/posts/[slug])                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           Islands (client:load hydration)            │    │
│  │                                                      │    │
│  │  ┌──────────────┐    ┌──────────────┐               │    │
│  │  │ PostList.jsx │    │ PostForm.jsx │               │    │
│  │  │ (publishing) │    │ (authoring)  │               │    │
│  │  └──────┬───────┘    └──────┬───────┘               │    │
│  │         │                   │                        │    │
│  │         └─────────┬─────────┘                        │    │
│  │                   │                                  │    │
│  │            ┌──────▼──────┐                           │    │
│  │            │  IndexedDB  │                           │    │
│  │            │   + ISR     │                           │    │
│  │            └─────────────┘                           │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### ISR Implementation (In-Memory)

For the demo, ISR uses a simple in-memory cache with stale-while-revalidate semantics:

```javascript
// ~30 lines of ISR adapter
const cache = new Map();

async function withRevalidate(key, ttlSeconds, fetcher) {
  const cached = cache.get(key);
  const now = Date.now();

  if (cached && now < cached.staleAt) {
    return cached.data; // Fresh
  }

  if (cached) {
    // Stale - return cached, revalidate in background
    fetcher().then(data => {
      cache.set(key, { data, staleAt: now + ttlSeconds * 1000 });
    });
    return cached.data;
  }

  // Missing - fetch fresh
  const data = await fetcher();
  cache.set(key, { data, staleAt: now + ttlSeconds * 1000 });
  return data;
}
```

The `# Pragma: revalidate 60` pragma triggers this pattern.

### Demo Structure

**Static pages** (rendered at build time):
- `/` - Landing page with site intro
- `/about` - Static about page

**Dynamic pages** (ActiveRecord + ISR via islands):
- `/posts` - Post listing island + authoring form island
- `/posts/[slug]` - Individual post island + edit form island

**Post Model:**
```ruby
# models/post.rb
class Post < ApplicationRecord
  # title, slug, body, excerpt, published_at
  scope :published, -> { where.not(published_at: nil) }
end
```

**Example Page Shell:**
```ruby
# pages/posts/index.astro.rb
__END__
<Layout title="Posts">
  <Header />
  <PostList client:load />
  <PostForm client:load />
</Layout>
```

**Example Publishing Island:**
```ruby
# components/PostList.jsx.rb
# Pragma: revalidate 60

@posts, @setPosts = useState([])

useEffect [] do
  data = await Post.published.order(published_at: :desc)
  setPosts(data)
end
__END__
<div class="posts">
  {posts.map { |post| <PostCard post={post} /> }}
</div>
```

**Example Authoring Island:**
```ruby
# components/PostForm.jsx.rb

@title, @setTitle = useState("")
@body, @setBody = useState("")

def handleSubmit(e)
  e.preventDefault
  post = Post.new(title: @title, body: @body, slug: @title.parameterize)
  await post.save
  setTitle("")
  setBody("")
end
__END__
<form onSubmit={handleSubmit}>
  <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Title" />
  <textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder="Body" />
  <button type="submit">Create Post</button>
</form>
```

**Layout with View Transitions:**
```ruby
# layouts/Layout.astro.rb
import { ViewTransitions } from 'astro:transitions'

@title = props[:title]
__END__
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title}</title>
  <ViewTransitions />
</head>
<body>
  <slot />
</body>
</html>
```

View Transitions provide smooth animated navigation between pages - a key Astro 3+ feature that works seamlessly with the Ruby integration.

### Demo Flow

Within the same Astro app:

1. **View posts** → PostList island queries IndexedDB, displays cached results
2. **Create post** → PostForm island saves to IndexedDB
3. **See update** → After revalidate period, PostList fetches fresh data

```
┌─────────────────────────────────────────────────────────────┐
│                     Astro Blog Demo                          │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    /posts page                        │   │
│  │                                                       │   │
│  │  ┌─────────────────┐         ┌─────────────────┐     │   │
│  │  │   PostList      │         │   PostForm      │     │   │
│  │  │   (publishing)  │◀────────│   (authoring)   │     │   │
│  │  │                 │  ISR    │                 │     │   │
│  │  │  - First Post   │ refresh │  Title: [____]  │     │   │
│  │  │  - Second Post  │         │  Body:  [____]  │     │   │
│  │  │  - Third Post   │         │  [Create Post]  │     │   │
│  │  └────────┬────────┘         └────────┬────────┘     │   │
│  │           │                           │              │   │
│  │           └───────────┬───────────────┘              │   │
│  │                       │                              │   │
│  │                ┌──────▼──────┐                       │   │
│  │                │  IndexedDB  │                       │   │
│  │                └─────────────┘                       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Dockerfile

Uses the same Juntos commands as other demos, supporting multiple targets:

```dockerfile
FROM ruby

# Install Node.js 24 (LTS)
RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and run the creation script
COPY create-astro-blog .
RUN chmod +x create-astro-blog && ./create-astro-blog astro-blog

WORKDIR /app/astro-blog

# Build args for Juntos
ARG DATABASE=sqlite
ARG TARGET=node

ENV JUNTOS_DATABASE=${DATABASE}
ENV JUNTOS_TARGET=${TARGET}

# Build with specified database and target
RUN bin/juntos build -d ${DATABASE} -t ${TARGET}

# Run migrations (skip for browser targets - they migrate client-side)
RUN if [ "${TARGET}" != "browser" ]; then bin/juntos db prepare -d ${DATABASE} -t ${TARGET}; fi

EXPOSE 4321

CMD ["bin/juntos", "server"]
```

**Build options:**

| Command | Database | Target | Use Case |
|---------|----------|--------|----------|
| `docker build -t astro-blog .` | SQLite | Node.js | Self-hosted server |
| `docker build --build-arg DATABASE=dexie --build-arg TARGET=browser -t astro-blog .` | IndexedDB | Browser | Static hosting / CDN |

Run with: `docker run -p 4321:4321 astro-blog`

Same Ruby code works in both environments - the Post model automatically uses the appropriate database backend.

### Definition of Done

- [ ] Post model with ActiveRecord queries (IndexedDB)
- [ ] Seed data (3 posts)
- [ ] Static pages: index (landing), about
- [ ] Publishing islands: PostList, PostCard, PostDetail
- [ ] Authoring islands: PostForm (create/edit)
- [ ] View Transitions for smooth page navigation
- [ ] In-memory ISR adapter (~30 lines)
- [ ] `# Pragma: revalidate` working in islands
- [ ] Dockerfile for containerized deployment
- [ ] Update integration test (`test/integration/astro_blog.test.mjs`)
- [ ] Documentation: ISR page, demo page, cross-references
- [ ] Full authoring → publishing workflow demonstrated

### Integration Test Updates

The existing test validates static markdown content. Update to test:

```javascript
describe('Astro Blog Integration Tests', () => {
  describe('Build Output', () => {
    it('generates static pages', () => {
      // Landing page and about page exist
    });

    it('generates post shell pages', () => {
      // /posts/index.html and /posts/[slug]/index.html exist
    });
  });

  describe('Islands', () => {
    it('includes PostList island with client:load', () => {
      // Check for hydration script
    });

    it('includes PostForm island with client:load', () => {
      // Check for form component
    });
  });

  describe('ActiveRecord', () => {
    it('includes Post model', () => {
      // Check for model JS in build output
    });

    it('includes seed data', () => {
      // Seeds should be bundled for browser target
    });
  });

  describe('ISR', () => {
    it('includes ISR adapter', () => {
      // Check for withRevalidate function
    });
  });
});
```

### Documentation Updates

**New file: `docs/src/_docs/juntos/isr.md`**

Standalone ISR documentation covering:
- Concept: stale-while-revalidate caching
- Unified pragma syntax: `# Pragma: revalidate 60`
- Per-target implementation table:

| Target | Cache Layer | Implementation |
|--------|-------------|----------------|
| Browser | In-memory | JavaScript Map with TTL |
| Node.js | In-memory | JavaScript Map with TTL |
| Vercel | Native | `revalidate` export |
| Cloudflare | Cache API | Native edge caching |

- Link to Astro Blog demo as working example
- Future roadmap: Service Worker, Redis

**New file: `docs/src/_docs/juntos/demos/astro-blog.md`**

Demo documentation covering:
- What it demonstrates (Astro islands, ISR, ActiveRecord, authoring + publishing)
- How to run (browser, Node.js, Docker)
- Architecture diagram
- Key files walkthrough

**Update: `docs/src/_docs/juntos/demos/index.md`**

Add to Available Demos table:
```markdown
| **[Astro Blog](/docs/juntos/demos/astro-blog)** | Astro islands, ISR caching, ActiveRecord with IndexedDB/SQLite, authoring + publishing |
```

**Update: `docs/src/_docs/juntos/coming-from/astro.md`**

Update ISR section (lines 305-319) to:
- Link to new ISR page
- Reference the working Astro Blog demo
- Show authoring + publishing pattern

**Update: `docs/src/_docs/juntos/deploying/browser.md` and `node.md`**

Add ISR section linking to the main ISR page.

**Update: `docs/src/_docs/juntos/roadmap.md`**

Add to "Recently Implemented":
- In-memory ISR for browser and Node.js targets
- `# Pragma: revalidate` support

### Success Criteria

- [ ] Demo proves https://www.ruby2js.com/docs/juntos/coming-from/astro is real
- [ ] Create post in form → see it appear in list (after revalidate)
- [ ] Edit post → see changes reflected
- [ ] Delete post → see it removed
- [ ] ISR caching observable (fast loads within TTL)
- [ ] Documentation complete (ISR page, demo page, cross-references)

### Future Roadmap (If Demand)

These enhancements are documented but not implemented in the initial demo:

| Feature | Current | Future |
|---------|---------|--------|
| Browser ISR | In-memory cache | Service Worker + Cache API |
| Node.js ISR | In-memory cache | Redis |
| Offline support | Not implemented | Service Worker |
| Multiple platforms | Browser only | Node.js, Cloudflare, Vercel, Electron, Tauri, Capacitor |

The architecture supports these upgrades without changing application code—only the ISR adapter implementation would change.
