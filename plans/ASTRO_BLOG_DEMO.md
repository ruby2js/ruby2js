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

The `test/astro-blog/create-astro-blog` script uses the `ruby2js-astro` integration:

```bash
# Install ruby2js and ruby2js-astro
npm install ruby2js ruby2js-astro

# Configure astro.config.mjs
cat > astro.config.mjs << 'CONFIG'
import { defineConfig } from 'astro/config';
import ruby2js from 'ruby2js-astro';

export default defineConfig({
  integrations: [ruby2js()]
});
CONFIG
```

The integration provides:
- Watch mode with HMR during `astro dev`
- Proper error reporting via Astro's build system
- Automatic transformation of `.astro.rb` files

See `test/astro-blog/create-astro-blog` for the full implementation.

### Definition of Done

- [x] `create-astro-blog` script creates working demo
- [x] `ruby2js-astro` integration with watch mode (HMR)
- [x] `npm run dev` works locally with hot reload
- [x] `npm run build` produces static site
- [x] Demo deploys to GitHub Pages

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
| 6 | Full-stack demo with Preact islands (.jsx.rb) | Phases 1-5 |
| 7 | ERB → pnode transformer (.erb.rb) | Phase 6 |
| 8 | Full CRUD and ISR | Phase 6 or 7 |
| 9 | Multi-target and documentation | Phase 8 |

## Success Criteria (Phases 1-5)

- [x] All 6 transformers (Vue, Svelte, Astro × template + component) are selfhosted
- [x] Vite plugin handles `.vue.rb`, `.svelte.rb`, `.astro.rb` files
- [x] Astro blog demo builds and runs locally
- [x] Integration tests validate correct transformation
- [x] Demo is live at `ruby2js.github.io/ruby2js/astro-blog/`
- [x] FRAMEWORK_PARITY.md Phase 6 marked complete with working packages

---

## Phase 6: Full-Stack Demo with ActiveRecord and Preact Islands

### Vision

Replace the current markdown-based astro-blog demo with a full-stack demonstration that proves the documentation at https://www.ruby2js.com/docs/juntos/coming-from/astro is real and working.

**Note:** The existing Rails blog demo remains unchanged. This phase evolves only the astro-blog demo into a self-contained app with both authoring and publishing capabilities via Astro islands.

### Content Progression

The demo showcases how Ruby2JS fits naturally into Astro projects at every level of complexity:

| Level | Standard Astro | Ruby2JS | Demo Example |
|-------|----------------|---------|--------------|
| 1. Static content | `.md` | `.md` (unchanged) | About page |
| 2. Astro pages | `.astro` | `.astro.rb` | Layout, index, post shell |
| 3. Islands | `.jsx` / `.tsx` | `.jsx.rb` or `.erb.rb` | PostList, PostForm |

This demonstrates that Ruby2JS **enhances** Astro at each stage—it doesn't require full client-side interactivity. Simple content stays simple.

### Why Preact (for Islands)?

- **Rails-like DX**: Write Ruby code (`.jsx.rb` files) that transpiles to JSX
- **Native Astro support**: `client:load` hydration works out of the box
- **Tiny footprint**: ~3KB gzipped
- **Familiar patterns**: `useState`, `useEffect` map nicely to Ruby
- **View Transitions**: Best integration with Astro's navigation features

### Architecture: Self-Contained Astro App

```
┌─────────────────────────────────────────────────────────────┐
│                     Astro Blog Demo                          │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Static Content                          │    │
│  │  - About page (/about)        [.md]                  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Astro Pages (SSG)                       │    │
│  │  - Landing page (/)           [.astro.rb]            │    │
│  │  - Post list shell (/posts)   [.astro.rb]            │    │
│  │  - Post detail (/posts/[slug]) [.astro.rb]           │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │        Preact Islands (client:load hydration)        │    │
│  │                    [.jsx.rb files]                    │    │
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
│  │            │   (Dexie)   │                           │    │
│  │            └─────────────┘                           │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Transpilation Pipeline

```
.jsx.rb (Ruby with inline JSX)
    ↓
vite-plugin-ruby2js (React + JSX + Functions + ESM filters)
    ↓
xnode AST → xnode converter
    ↓
.jsx output (actual JSX syntax: <div className={...}>)
    ↓
Vite/Astro (with @astrojs/preact)
    ↓
Preact h() calls
```

The pipeline uses **existing Ruby2JS infrastructure**—no new transformer needed:

1. **React filter**: Converts pnode AST to xnode AST (when JSX filter present)
2. **JSX filter**: Signals React filter to output xnode instead of createElement
3. **xnode converter**: Serializes xnode AST to actual JSX syntax
4. **Vite**: Transforms JSX to Preact's `h()` calls via `@astrojs/preact`

This differs from `.astro.rb` files which use `AstroComponentTransformer` with `__END__` templates. `.jsx.rb` files use **inline JSX** (JSX embedded in Ruby code, not separated by `__END__`).

### Demo Structure

**Level 1 - Static content** (`.md` → rendered as-is):
- `/about` - Simple markdown page

**Level 2 - Astro pages** (`.astro.rb` → rendered at build time):
- `/` - Landing page with site intro
- `/posts` - Post listing shell (hosts islands)
- `/posts/[slug]` - Post detail shell (hosts islands)

**Level 3 - Islands** (`.jsx.rb` → hydrate on client):
- `PostList` - Displays posts from IndexedDB
- `PostForm` - Creates/edits posts

### Configuration

**astro.config.mjs:**
```javascript
import { defineConfig } from 'astro/config';
import preact from '@astrojs/preact';
import ruby2js from 'ruby2js-astro';

export default defineConfig({
  integrations: [
    ruby2js(),
    preact()
  ]
});
```

**vite.config.js** (for .jsx.rb handling):
```javascript
import ruby2js from 'vite-plugin-ruby2js';

export default {
  plugins: [
    ruby2js({
      include: ['**/*.jsx.rb'],
      filters: ['React', 'JSX', 'Functions', 'ESM']
    })
  ]
};
```

**Note:** The `JSX` filter is required to output actual JSX syntax (e.g., `<div className={...}>`) instead of `React.createElement()` calls. This allows Vite to further transform the JSX with Preact's pragma.

### Example: Static Content (Level 1)

**src/pages/about.md:**
```markdown
---
layout: ../layouts/Layout.astro
title: About
---

# About This Blog

This is a demo of Ruby2JS with Astro. It shows how Ruby can be used
at every level of an Astro project—from simple markdown content like
this page, to Astro components, to interactive islands.

Built with ❤️ using Ruby2JS.
```

No Ruby required. Markdown stays markdown.

### Post Model

```ruby
# src/models/Post.rb
class Post < ActiveRecord
  self.table_name = 'posts'

  # title, slug, body, excerpt, published_at
  validates_presence_of :title
  validates_presence_of :body

  scope :published, -> { where.not(published_at: nil) }
end
```

Transpiles to JavaScript using the Dexie adapter for IndexedDB storage.

### Example Preact Island (Ruby)

**src/islands/PostList.jsx.rb:**
```ruby
import { useState, useEffect } from 'preact/hooks'
import Post from '../models/Post'

def PostList()
  posts, setPosts = useState([])
  loading, setLoading = useState(true)

  useEffect -> {
    Post.all.then do |data|
      setPosts(data)
      setLoading(false)
    end
  }, []

  return <div class="loading">Loading...</div> if loading

  <div class="posts">
    {posts.map do |post|
      <article key={post.id} class="post-card">
        <h2><a href={"/posts/#{post.slug}"}>{post.title}</a></h2>
        <p>{post.excerpt || post.body.slice(0, 100)}...</p>
      </article>
    end}
  </div>
end

export default PostList
```

**Transpiles to:**
```jsx
import { useState, useEffect } from 'preact/hooks';
import Post from '../models/Post';

function PostList() {
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Post.all.then(data => {
      setPosts(data);
      setLoading(false);
    });
  }, []);

  if (loading) return <div class="loading">Loading...</div>;

  return (
    <div class="posts">
      {posts.map(post => (
        <article key={post.id} class="post-card">
          <h2><a href={`/posts/${post.slug}`}>{post.title}</a></h2>
          <p>{post.excerpt || post.body.slice(0, 100)}...</p>
        </article>
      ))}
    </div>
  );
}

export default PostList;
```

### Example Authoring Island (Ruby)

**src/islands/PostForm.jsx.rb:**
```ruby
import { useState } from 'preact/hooks'
import Post from '../models/Post'

def PostForm(props)
  title, setTitle = useState(props[:post]&.title || "")
  body, setBody = useState(props[:post]&.body || "")
  saving, setSaving = useState(false)

  handleSubmit = ->(e) {
    e.preventDefault
    setSaving(true)

    post = props[:post] || Post.new
    post.title = title
    post.body = body

    post.save.then do
      setTitle("")
      setBody("")
      setSaving(false)
      props[:onSave]&.(post)
    end
  }

  <form onSubmit={handleSubmit} class="post-form">
    <input
      value={title}
      onInput={(e) => setTitle(e.target.value)}
      placeholder="Title"
      disabled={saving}
    />
    <textarea
      value={body}
      onInput={(e) => setBody(e.target.value)}
      placeholder="Write your post..."
      rows={6}
      disabled={saving}
    />
    <button type="submit" disabled={saving}>
      {saving ? "Saving..." : (props[:post] ? "Update" : "Create Post")}
    </button>
  </form>
end

export default PostForm
```

### Astro Page Shell

**src/pages/posts/index.astro.rb:**
```ruby
import Layout from '../../layouts/Layout.astro'
import PostList from '../../islands/PostList'
import PostForm from '../../islands/PostForm'

@title = "Blog Posts"
__END__
<Layout title={title}>
  <main class="container">
    <h1>Blog Posts</h1>

    <section class="posts-section">
      <PostList client:load />
    </section>

    <section class="create-section">
      <h2>Create New Post</h2>
      <PostForm client:load />
    </section>
  </main>
</Layout>
```

### Layout with View Transitions

**src/layouts/Layout.astro.rb:**
```ruby
import { ViewTransitions } from 'astro:transitions'

@title = Astro.props[:title] || "Astro Blog"
__END__
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title}</title>
  <ViewTransitions />
  <style>
    .container { max-width: 800px; margin: 0 auto; padding: 2rem; }
    .post-card { padding: 1rem; margin: 1rem 0; border: 1px solid #ddd; border-radius: 8px; }
    .post-form input, .post-form textarea { width: 100%; margin: 0.5rem 0; padding: 0.5rem; }
    .post-form button { background: #3b82f6; color: white; padding: 0.5rem 1rem; border: none; border-radius: 4px; cursor: pointer; }
  </style>
</head>
<body>
  <nav style="padding: 1rem; border-bottom: 1px solid #ddd;">
    <a href="/">Home</a> | <a href="/posts">Posts</a> | <a href="/about">About</a>
  </nav>
  <slot />
</body>
</html>
```

View Transitions provide smooth animated navigation between pages - a key Astro 3+ feature that works seamlessly with the Ruby integration.

### Demo Flow

Within the same Astro app:

1. **View posts** → PostList island queries IndexedDB via Dexie, displays results
2. **Create post** → PostForm island saves to IndexedDB
3. **See update** → PostList re-fetches on navigation (View Transitions)

```
┌─────────────────────────────────────────────────────────────┐
│                     Astro Blog Demo                          │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    /posts page                        │   │
│  │                                                       │   │
│  │  ┌─────────────────┐         ┌─────────────────┐     │   │
│  │  │   PostList      │         │   PostForm      │     │   │
│  │  │   (Preact)      │◀────────│   (Preact)      │     │   │
│  │  │                 │ refresh │                 │     │   │
│  │  │  - First Post   │         │  Title: [____]  │     │   │
│  │  │  - Second Post  │         │  Body:  [____]  │     │   │
│  │  │  - Third Post   │         │  [Create Post]  │     │   │
│  │  └────────┬────────┘         └────────┬────────┘     │   │
│  │           │                           │              │   │
│  │           └───────────┬───────────────┘              │   │
│  │                       │                              │   │
│  │                ┌──────▼──────┐                       │   │
│  │                │  IndexedDB  │                       │   │
│  │                │   (Dexie)   │                       │   │
│  │                └─────────────┘                       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Database Setup

**src/lib/db.js:**
```javascript
import { initDatabase, defineSchema, openDatabase, registerSchema } from 'ruby2js-rails/adapters/active_record_dexie.mjs';

// Register table schemas
registerSchema('posts', '++id, title, slug, created_at, updated_at');

// Initialize and open
export async function setupDatabase() {
  await initDatabase({ database: 'astro_blog' });
  defineSchema(1);
  await openDatabase();
}
```

**src/lib/seeds.js:**
```javascript
import Post from '../models/Post';

export async function runSeeds() {
  const count = await Post.count();
  if (count > 0) return; // Already seeded

  await Post.create({
    title: 'Getting Started with Ruby2JS',
    body: 'Ruby2JS allows you to write your Astro components in Ruby...',
    slug: 'getting-started'
  });

  await Post.create({
    title: 'Preact Islands in Astro',
    body: 'Astro islands provide partial hydration for interactive components...',
    slug: 'preact-islands'
  });

  await Post.create({
    title: 'ActiveRecord in the Browser',
    body: 'With Dexie.js as the backend, you can use ActiveRecord patterns...',
    slug: 'activerecord-browser'
  });

  console.log('Seeded 3 posts');
}
```

### Dockerfile

Builds a static Astro site that runs entirely in the browser:

```dockerfile
FROM node:24-slim

WORKDIR /app

# Copy the creation script
COPY create-astro-blog .
RUN chmod +x create-astro-blog && ./create-astro-blog astro-blog

WORKDIR /app/astro-blog

# Build the static site
RUN npm run build

# Serve with a simple static server
RUN npm install -g serve

EXPOSE 4321

CMD ["serve", "-s", "dist", "-l", "4321"]
```

**Build and run:**
```bash
docker build -t astro-blog .
docker run -p 4321:4321 astro-blog
```

The demo runs entirely client-side with IndexedDB - no server database needed.

### Definition of Done

**Level 1 - Static content:**
- [ ] About page (`src/pages/about.md`)

**Level 2 - Astro pages:**
- [ ] Landing page (`src/pages/index.astro.rb`)
- [ ] Post list shell (`src/pages/posts/index.astro.rb`)
- [ ] Post detail shell (`src/pages/posts/[slug].astro.rb`)
- [ ] Layout with View Transitions (`src/layouts/Layout.astro.rb`)

**Level 3 - Islands:**
- [ ] PostList island (`src/islands/PostList.jsx.rb`)
- [ ] PostForm island (`src/islands/PostForm.jsx.rb`)
- [ ] Post model with ActiveRecord queries (Dexie/IndexedDB)
- [ ] Seed data (3 posts)

**Infrastructure:**
- [ ] vite-plugin-ruby2js configured for `.jsx.rb` → JSX
- [ ] Dockerfile for containerized deployment
- [ ] Update integration test (`test/integration/astro_blog.test.mjs`)
- [ ] Full authoring → publishing workflow demonstrated

### Integration Test Updates

The existing test validates static markdown content. Update to test:

```javascript
describe('Astro Blog Integration Tests', () => {
  describe('Build Output', () => {
    it('generates static pages', () => {
      // Landing page, about page, and posts shell exist
      expect(existsSync(join(DIST_DIR, 'index.html'))).toBe(true);
      expect(existsSync(join(DIST_DIR, 'about/index.html'))).toBe(true);
      expect(existsSync(join(DIST_DIR, 'posts/index.html'))).toBe(true);
    });
  });

  describe('Preact Islands', () => {
    it('includes PostList island with client:load', () => {
      const html = readFileSync(join(DIST_DIR, 'posts/index.html'), 'utf-8');
      // Astro adds hydration scripts for client:load components
      expect(html).toContain('astro-island');
    });

    it('transpiled .jsx.rb to valid JSX', () => {
      // Check that the bundled JS doesn't contain Ruby syntax
      const jsFiles = globSync(join(DIST_DIR, '_astro/*.js'));
      expect(jsFiles.length).toBeGreaterThan(0);
    });
  });

  describe('ActiveRecord', () => {
    it('includes Dexie for IndexedDB', () => {
      const html = readFileSync(join(DIST_DIR, 'posts/index.html'), 'utf-8');
      // Should reference the database setup
      expect(html).toMatch(/dexie|indexeddb/i);
    });
  });

  describe('View Transitions', () => {
    it('includes ViewTransitions in layout', () => {
      const html = readFileSync(join(DIST_DIR, 'index.html'), 'utf-8');
      expect(html).toContain('view-transition');
    });
  });
});
```

### Success Criteria

- [ ] **Three levels demonstrated**: static `.md`, Astro `.astro.rb`, islands `.jsx.rb`
- [ ] `.astro.rb` files transpile to valid Astro components
- [ ] `.jsx.rb` files transpile to valid Preact components
- [ ] Preact islands hydrate with `client:load`
- [ ] Post model works with IndexedDB via Dexie
- [ ] Create post in form → see it appear in list
- [ ] View Transitions provide smooth navigation
- [ ] Demo proves Ruby2JS enhances Astro at every level, not just full interactivity

---

## Phase 7: ERB → pnode Transformer for Islands

### Overview

Add an alternative authoring experience for Preact islands using ERB-style templates (`.erb.rb` files) instead of JSX-style (`.jsx.rb` files). This provides a more Rails-like developer experience.

### Why ERB?

- **Rails-familiar syntax**: `<%= %>` and `<% %>` feel natural to Rails developers
- **HTML-centric**: Focus on markup with embedded Ruby, not Ruby with embedded JSX
- **Single File Components**: Ruby code before `__END__`, ERB template after
- **Leverages existing infrastructure**: pnodes + React filter already handle component output

### Architecture

```
.erb.rb (Ruby SFC)  →  pnode AST  →  React filter  →  Preact JSX
                    ↑
    ┌───────────────┴───────────────┐
    │  1. Parse Ruby code (Prism)   │
    │  2. Parse ERB template (XML)  │
    │  3. Convert HTML → pnodes     │
    │  4. Merge into Ruby AST       │
    └───────────────────────────────┘
```

### pnode Format

The existing pnode representation is used:

```ruby
s(:pnode, :div, {class: "posts"},
  s(:pnode, :h1, {}, "Hello"),
  s(:pnode, nil, {}, *children)  # Fragment
)
```

### Transpilation Pipeline

1. **Split SFC**: Separate Ruby code from `__END__` template
2. **Parse Ruby**: Standard Prism/Ruby2JS parsing
3. **Parse ERB template**: Simple recursive descent XML parser
   - Well-formed XML only (JSX subset)
   - `<%= expr %>` → expression interpolation
   - `<% code %>` → control flow
4. **Convert to pnodes**: HTML elements become pnode AST nodes
5. **Emit via React filter**: pnodes → `React.createElement()` (Preact-compatible)

### HTML Parser Approach

Since we're targeting JSX-subset (well-formed XML), the parser is simple:

```ruby
# lib/ruby2js/erb_pnode_transformer.rb
class ErbPnodeTransformer
  def parse_element(scanner)
    return parse_text(scanner) unless scanner.scan(/</)

    tag = scanner.scan(/\w+/)
    attrs = parse_attributes(scanner)

    if scanner.scan(/\/>/)
      # Self-closing: <br />
      return s(:pnode, tag.to_sym, attrs)
    end

    scanner.scan(/>/)
    children = parse_children(scanner)
    scanner.scan(/<\/#{tag}>/)

    s(:pnode, tag.to_sym, attrs, *children)
  end

  def parse_erb_expression(text)
    # <%= expr %> → Ruby expression → pnode child
    # <% code %> → control flow (map, if, etc.)
  end
end
```

### File Extension

`.erb.rb` - Follows the established pattern:
- `.astro.rb` → Astro components
- `.vue.rb` → Vue components
- `.jsx.rb` → Preact/React components (JSX syntax)
- `.erb.rb` → Preact/React components (ERB syntax)

### Example: PostList.erb.rb

**Input (Ruby SFC with ERB template):**
```ruby
# src/islands/PostList.erb.rb
import { useState, useEffect } from 'preact/hooks'
import Post from '../models/Post'

def PostList()
  posts, setPosts = useState([])
  loading, setLoading = useState(true)

  useEffect -> {
    Post.all.then do |data|
      setPosts(data)
      setLoading(false)
    end
  }, []

  render
end

export default PostList
__END__
<% if loading %>
  <div class="loading">Loading...</div>
<% else %>
  <div class="posts">
    <% posts.each do |post| %>
      <article key={post.id} class="post-card">
        <h2><a href="/posts/<%= post.slug %>"><%= post.title %></a></h2>
        <p><%= post.excerpt || post.body.slice(0, 100) %>...</p>
      </article>
    <% end %>
  </div>
<% end %>
```

**Output (Preact JSX):**
```jsx
import { useState, useEffect } from 'preact/hooks';
import Post from '../models/Post';

function PostList() {
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Post.all.then(data => {
      setPosts(data);
      setLoading(false);
    });
  }, []);

  return loading ? (
    <div class="loading">Loading...</div>
  ) : (
    <div class="posts">
      {posts.map(post => (
        <article key={post.id} class="post-card">
          <h2><a href={`/posts/${post.slug}`}>{post.title}</a></h2>
          <p>{post.excerpt || post.body.slice(0, 100)}...</p>
        </article>
      ))}
    </div>
  );
}

export default PostList;
```

### Implementation Steps

1. **Create ErbPnodeTransformer** (`lib/ruby2js/erb_pnode_transformer.rb`)
   - SFC splitting (reuse pattern from other transformers)
   - XML parser for well-formed HTML
   - ERB expression parsing (`<%= %>`, `<% %>`)
   - pnode AST generation

2. **Update vite-plugin-ruby2js**
   - Add `.erb.rb` extension handling
   - Route through ErbPnodeTransformer
   - Apply React filter for pnode → JSX output

3. **Add transpile script** (`demo/selfhost/scripts/transpile_erb_pnode_transformer.rb`)
   - Selfhost the transformer for browser use

4. **Add tests**
   - Unit tests for XML parsing
   - Unit tests for ERB expression handling
   - Integration tests for full SFC → JSX pipeline

### ERB Tag Mapping

| ERB Syntax | Meaning | pnode Output |
|------------|---------|--------------|
| `<%= expr %>` | Output expression | Expression as child |
| `<%- expr %>` | Output (trimmed) | Expression as child |
| `<% code %>` | Execute code | Control flow AST node |
| `<% if %>...<% end %>` | Conditional | Ternary or `&&` expression |
| `<% each %>...<% end %>` | Iteration | `.map()` call |

### Comparison: JSX vs ERB

**JSX style (.jsx.rb):**
```ruby
<div class="posts">
  {posts.map do |post|
    <article key={post.id}>
      <h2>{post.title}</h2>
    </article>
  end}
</div>
```

**ERB style (.erb.rb):**
```erb
<div class="posts">
  <% posts.each do |post| %>
    <article key={post.id}>
      <h2><%= post.title %></h2>
    </article>
  <% end %>
</div>
```

Both produce the same Preact output. ERB is more familiar to Rails developers; JSX is more familiar to React/Preact developers.

### Definition of Done

- [ ] `ErbPnodeTransformer` class with XML parser
- [ ] ERB expression handling (`<%= %>`, `<% %>`)
- [ ] Control flow mapping (if/else, each → map)
- [ ] pnode output compatible with React filter
- [ ] vite-plugin-ruby2js handles `.erb.rb` files
- [ ] Selfhosted transformer for browser use
- [ ] Unit tests for parser
- [ ] Integration tests for full pipeline
- [ ] Demo includes at least one `.erb.rb` island

### Success Criteria

- [ ] `PostList.erb.rb` transpiles to valid Preact JSX
- [ ] ERB and JSX styles can coexist in same project
- [ ] Rails developers recognize the authoring experience
- [ ] pnode → React filter pipeline works correctly

---

## Phase 8: Full CRUD and ISR

### Overview

Extend the basic demo with edit/delete functionality and ISR caching.

### Edit/Delete Islands

**src/islands/PostDetail.jsx.rb:**
```ruby
import { useState } from 'preact/hooks'
import Post from '../models/Post'
import PostForm from './PostForm'

def PostDetail(props)
  post, setPost = useState(props[:post])
  editing, setEditing = useState(false)
  deleted, setDeleted = useState(false)

  handleDelete = -> {
    return unless confirm("Delete this post?")
    post.destroy.then do
      setDeleted(true)
    end
  }

  handleSave = ->(updated) {
    setPost(updated)
    setEditing(false)
  }

  return <p>Post deleted. <a href="/posts">Back to posts</a></p> if deleted

  if editing
    <PostForm post={post} onSave={handleSave} onCancel={-> { setEditing(false) }} />
  else
    <article>
      <h1>{post.title}</h1>
      <div class="content">{post.body}</div>
      <div class="actions">
        <button onClick={-> { setEditing(true) }}>Edit</button>
        <button onClick={handleDelete} class="danger">Delete</button>
      </div>
    </article>
  end
end

export default PostDetail
```

### ISR Implementation

**src/lib/isr.js:**
```javascript
// In-memory cache with stale-while-revalidate semantics
const cache = new Map();

export async function withRevalidate(key, ttlSeconds, fetcher) {
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

export function invalidate(key) {
  cache.delete(key);
}
```

**Usage in PostList.jsx.rb:**
```ruby
import { useState, useEffect } from 'preact/hooks'
import { withRevalidate } from '../lib/isr'
import Post from '../models/Post'

def PostList()
  posts, setPosts = useState([])

  useEffect -> {
    withRevalidate('posts:all', 60, -> { Post.all }).then do |data|
      setPosts(data)
    end
  }, []

  # ... render posts
end
```

### Definition of Done

- [ ] Edit post functionality
- [ ] Delete post with confirmation
- [ ] ISR adapter with `withRevalidate(key, ttl, fetcher)`
- [ ] Cache invalidation on create/update/delete
- [ ] `# Pragma: revalidate 60` support (optional)

---

## Phase 9: Multi-Target and Documentation

### Overview

Add Juntos integration for multi-target deployment and complete documentation.

### Multi-Target Support

**Dockerfile (multi-target):**
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
ARG DATABASE=dexie
ARG TARGET=browser

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
| `docker build -t astro-blog .` | IndexedDB | Browser | Static hosting / CDN |
| `docker build --build-arg DATABASE=sqlite --build-arg TARGET=node -t astro-blog .` | SQLite | Node.js | Self-hosted server |
| `docker build --build-arg DATABASE=turso --build-arg TARGET=cloudflare -t astro-blog .` | Turso | Cloudflare | Edge deployment |

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
| **[Astro Blog](/docs/juntos/demos/astro-blog)** | Astro islands, ActiveRecord with IndexedDB/SQLite, authoring + publishing |
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
- Astro Blog demo with Preact islands
- In-memory ISR for browser and Node.js targets
- `# Pragma: revalidate` support

### Definition of Done

- [ ] Juntos CLI works with Astro projects
- [ ] Multi-target Dockerfile
- [ ] ISR documentation page
- [ ] Astro Blog demo documentation page
- [ ] Cross-references in existing docs
- [ ] Roadmap updated

---

## Future Roadmap (If Demand)

These enhancements are documented but not planned for initial implementation:

| Feature | Current | Future |
|---------|---------|--------|
| Browser ISR | In-memory cache | Service Worker + Cache API |
| Node.js ISR | In-memory cache | Redis |
| Offline support | Not implemented | Service Worker |
| Additional platforms | Browser, Node.js | Electron, Tauri, Capacitor |

The architecture supports these upgrades without changing application code—only the ISR adapter implementation would change.
