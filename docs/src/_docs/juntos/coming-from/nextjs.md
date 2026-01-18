---
order: 679
title: Coming from Next.js
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

# Coming from Next.js

If you know Next.js, you'll find Ruby2JS provides similar file-based routing and React components—with Ruby syntax.

{% toc %}

## What You Know → What You Write

| Next.js | Ruby2JS |
|---------|---------|
| `pages/index.js` | `app/pages/index.jsx.rb` |
| `pages/posts/[id].js` | `app/pages/posts/[id].jsx.rb` |
| `pages/blog/[...slug].js` | `app/pages/blog/[...slug].jsx.rb` |
| `getStaticProps` | `# Pragma: revalidate 60` |
| `useRouter()` | `router = useRouter()` |
| `router.push('/path')` | `router.push('/path')` |

## Quick Start

**1. File-based routing works the same:**

```
app/pages/
  index.jsx.rb          → /
  about.jsx.rb          → /about
  posts/
    index.jsx.rb        → /posts
    [id].jsx.rb         → /posts/:id
    [...slug].jsx.rb    → /posts/*slug
```

**2. Create a page:**

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
# app/pages/posts/[id].jsx.rb
export default
def PostPage()
  router = useRouter()
  id = router.query[:id]
  post, setPost = useState(nil)

  useEffect -> {
    fetch("/api/posts/#{id}")
      .then(->(r) { r.json })
      .then(->(data) { setPost(data) })
  }, [id]

  return %x{<p>Loading...</p>} unless post

  %x{
    <article>
      <h1>{post.title}</h1>
      <div dangerouslySetInnerHTML={{ __html: post.body }} />
    </article>
  }
end
```

**3. The generated React component:**

```jsx
export default function PostPage() {
  const router = useRouter();
  const id = router.query.id;
  const [post, setPost] = useState(null);

  useEffect(() => {
    fetch(`/api/posts/${id}`)
      .then(r => r.json())
      .then(data => setPost(data));
  }, [id]);

  if (!post) return <p>Loading...</p>;

  return (
    <article>
      <h1>{post.title}</h1>
      <div dangerouslySetInnerHTML={{ __html: post.body }} />
    </article>
  );
}
```

## Routing Patterns

### Dynamic Routes

```ruby
# app/pages/users/[id].jsx.rb
export default
def UserProfile()
  router = useRouter()
  id = router.query[:id]
  # ...
end

# app/pages/posts/[...slug].jsx.rb (catch-all)
export default
def BlogPost()
  router = useRouter()
  slug = router.query[:slug]  # Array of path segments
  # ...
end
```

### Navigation

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
def Navigation()
  router = useRouter()

  go_to_post = ->(id) {
    router.push("/posts/#{id}")
  }

  go_back = -> {
    router.back()
  }

  %x{
    <nav>
      <button onClick={go_back}>Back</button>
      <button onClick={-> { go_to_post(123) }}>View Post</button>
    </nav>
  }
end
```

### Link Component

```ruby
import { Link } from 'next/link'

def Header()
  %x{
    <header>
      <Link href="/">Home</Link>
      <Link href="/about">About</Link>
      <Link href="/posts/123">Post 123</Link>
    </header>
  }
end
```

## Data Fetching

### Client-Side Fetching

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
export default
def Dashboard()
  data, setData = useState(nil)
  loading, setLoading = useState(true)

  useEffect -> {
    fetch('/api/dashboard')
      .then(->(r) { r.json })
      .then(->(d) {
        setData(d)
        setLoading(false)
      })
  }, []

  return %x{<p>Loading...</p>} if loading

  %x{
    <div>
      <h1>Dashboard</h1>
      <p>Welcome, {data.user.name}</p>
    </div>
  }
end
```

### ISR (Incremental Static Regeneration)

Use pragmas to enable ISR:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
# Pragma: revalidate 60

export default
def PostsList()
  # This page will be regenerated every 60 seconds
  posts, setPosts = useState([])

  useEffect -> {
    fetch('/api/posts')
      .then(->(r) { r.json })
      .then(->(data) { setPosts(data) })
  }, []

  %x{
    <ul>
      {posts.map { |post| <li key={post.id}>{post.title}</li> }}
    </ul>
  }
end
```

## API Routes

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions"]
}'></div>

```ruby
# app/api/posts.rb
export default
def handler(req, res)
  if req.method == 'GET'
    posts = Post.all
    res.status(200).json(posts)
  elsif req.method == 'POST'
    post = Post.create(req.body)
    res.status(201).json(post)
  else
    res.status(405).end()
  end
end
```

## Why Ruby2JS for Next.js?

Next.js gives you file-based routing and React. Ruby2JS adds the Rails ecosystem:

### Full-Stack Ruby

Same language in your pages, API routes, and backend. Rails patterns everywhere:

```ruby
# Backend model (Rails)
class Post < ApplicationRecord
  validates :title, presence: true
  scope :published, -> { where(published: true) }
end

# API route (Ruby2JS)
export default
def handler(req, res)
  posts = Post.published.order(created_at: :desc)
  res.status(200).json(posts)
end
```

### Built-in ORM

ActiveRecord in your API routes—no separate ORM to learn:

```ruby
# app/api/posts/[id].rb
export default
def handler(req, res)
  post = Post.find(req.query[:id])

  case req.method
  when 'GET'
    res.json(post.as_json(include: :comments))
  when 'PUT'
    post.update(req.body)
    res.json(post)
  when 'DELETE'
    post.destroy
    res.status(204).end()
  end
end
```

### Rails Ecosystem

Validations, associations, scopes—the full ActiveRecord toolkit:

```ruby
@post = Post.find(id)
@comments = @post.comments.includes(:author).order(created_at: :desc)
@related = Post.where(category: @post.category).published.limit(3)
```

### Syntax Benefits

Cleaner Ruby syntax throughout:

```ruby
# Conditionals
return %x{<Loading />} if loading

# String interpolation
"/posts/#{post[:id]}"

# Blocks
posts.select { |p| p[:published] }.map { |p| %x{<Post {...p} />} }
```

## Key Differences

### JSX Syntax

Ruby2JS uses `%x{}` for JSX:

```ruby
# Multi-line JSX
%x{
  <div className="container">
    <Header />
    <main>{children}</main>
    <Footer />
  </div>
}

# Inline JSX
%x{<Button onClick={handleClick}>Click Me</Button>}
```

### File Extensions

Use `.jsx.rb` for React/Next.js pages:

```
pages/           →  app/pages/
  index.js       →    index.jsx.rb
  about.js       →    about.jsx.rb
  posts/[id].js  →    posts/[id].jsx.rb
```

### Query Parameters

Access via router object:

```ruby
router = useRouter()
id = router.query[:id]
page = router.query[:page] || 1
```

## Layout Pattern

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
# app/layouts/default.jsx.rb
def Layout(children:)
  %x{
    <div className="layout">
      <Header />
      <main>{children}</main>
      <Footer />
    </div>
  }
end

# app/pages/index.jsx.rb
export default
def HomePage()
  %x{
    <Layout>
      <h1>Welcome</h1>
      <p>This is the home page.</p>
    </Layout>
  }
end
```

## Next Steps

- **[React Filter](/docs/filters/react)** - Full React filter documentation
- **[File-Based Routing](/docs/juntos/routing)** - Route discovery and configuration
- **[ISR Caching](/docs/juntos/isr)** - Incremental Static Regeneration
- **[User's Guide](/docs/users-guide/introduction)** - General Ruby2JS patterns
