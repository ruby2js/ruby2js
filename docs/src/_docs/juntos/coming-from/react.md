---
order: 676
title: Coming from React
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

If you know React, you'll find Ruby2JS provides a familiar component model with cleaner syntax.

{% toc %}

## What You Know → What You Write

| React (JavaScript) | Ruby2JS |
|-------------------|---------|
| `useState(0)` | `@count = 0` |
| `const [count, setCount] = useState(0)` | `count, setCount = useState(0)` |
| `useEffect(() => {}, [])` | `useEffect(-> {}, [])` |
| `{count}` (JSX) | `{count}` (JSX via `%x{}`) |
| `onClick={() => setCount(c => c + 1)}` | `onClick: -> { setCount(->(c) { c + 1 }) }` |
| `export default function Counter()` | `def Counter()` (auto-exported) |

## Quick Start

**Try it live** — edit the Ruby code and see the JavaScript output:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
def Counter(initial: 0)
  count, setCount = useState(initial)

  %x{
    <div>
      <p>Count: {count}</p>
      <button onClick={-> { setCount(count + 1) }}>
        Increment
      </button>
    </div>
  }
end
```

## Component Patterns

### Functional Components with Hooks

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
def UserProfile(user_id:)
  user, setUser = useState(nil)
  loading, setLoading = useState(true)

  useEffect -> {
    fetch("/api/users/#{user_id}")
      .then(->(r) { r.json })
      .then(->(data) {
        setUser(data)
        setLoading(false)
      })
  }, [user_id]

  return %x{<p>Loading...</p>} if loading

  %x{
    <div className="profile">
      <h1>{user.name}</h1>
      <p>{user.email}</p>
    </div>
  }
end
```

### Event Handlers

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
def Form()
  name, setName = useState("")

  handleSubmit = ->(e) {
    e.preventDefault()
    console.log("Submitted: #{name}")
  }

  %x{
    <form onSubmit={handleSubmit}>
      <input
        value={name}
        onChange={->(e) { setName(e.target.value) }}
      />
      <button type="submit">Submit</button>
    </form>
  }
end
```

### Custom Hooks

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
def useLocalStorage(key, initial_value)
  stored = localStorage.getItem(key)
  value, setValue = useState(stored ? JSON.parse(stored) : initial_value)

  useEffect -> {
    localStorage.setItem(key, JSON.stringify(value))
  }, [key, value]

  [value, setValue]
end

# Usage
def Settings()
  theme, setTheme = useLocalStorage("theme", "light")
  # ...
end
```

## Why Ruby2JS for React?

The syntax improvements are nice, but the real value is what Ruby brings beyond JSX:

### Full-Stack Ruby

Same language on frontend and backend. If you know Rails, the patterns transfer:

```ruby
# Backend model (Rails)
class Post < ApplicationRecord
  validates :title, presence: true
  has_many :comments
end

# React component (Ruby2JS)
def PostList()
  posts, setPosts = useState([])

  useEffect -> {
    Post.published.order(created_at: :desc).then { |p| setPosts(p) }
  }, []
  # ...
end
```

### Rails Ecosystem

ActiveRecord queries, validations, associations—directly in your React components:

```ruby
def PostPage()
  post = useLoaderData()  # From server: Post.find(params[:id])
  comments = post.comments.includes(:author)
  related = Post.where(category: post.category).limit(3)
  # ...
end
```

### Syntax Benefits

The syntax improvements add up across a codebase:

```ruby
# Cleaner string interpolation
"Hello, #{user.name}!"  # vs `Hello, ${user.name}!`

# Implicit returns
double = ->(n) { n * 2 }  # vs const double = (n) => n * 2

# Cleaner conditionals
return %x{<Loading />} if loading
%x{<Content data={data} />}
```

## Key Differences

### JSX Syntax

Ruby2JS uses `%x{}` blocks for JSX:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
def Example(title:, content:, value:)
  # Inline JSX
  %x{<Component prop={value} />}

  # Multi-line works naturally
  %x{
    <div>
      <h1>{title}</h1>
      <p>{content}</p>
    </div>
  }
end
```

### Auto-Export

When your file defines exactly one function or class, it's automatically exported as default:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
def MyComponent(name:)
  %x{<h1>Hello, {name}!</h1>}
end
```

### Props vs Instance Variables

In React components, use props directly. Instance variables (`@`) are for class components:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "jsx", "functions"]
}'></div>

```ruby
# Functional component (recommended)
def Greeting(name:)
  %x{<h1>Hello, {name}!</h1>}
end

# Class component (if needed)
class Counter < React::Component
  def initialize
    @count = 0  # Instance variable becomes this.state
  end
end
```

## Next Steps

- **[React Filter](/docs/filters/react)** - Full React filter documentation
- **[JSX Support](/docs/filters/jsx)** - JSX syntax details
- **[User's Guide](/docs/users-guide/introduction)** - General Ruby2JS patterns
