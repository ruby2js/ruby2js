# Plan: Multi-Target Store Demo

## Goal

Same code, different runtimes: browser (IndexedDB), Node (SQLite), Edge (D1).

A Rails developer's existing app can incrementally adopt islands and ISR without a rewrite.

## The Narrative

1. Developer has a Rails store - models, controllers, views
2. Most of it works fine with traditional Rails patterns
3. Some parts need more: ISR for product pages, islands for cart interactivity
4. Executive demands: "Deploy to Cloudflare. No rewrite."
5. Developer adds `app/pages/` for just those routes
6. Same models, same `@variable` syntax, same templates
7. Deploy anywhere

---

# Part 1: Syntax Decisions

## ERB + JSX Semantics

Templates use familiar ERB syntax (`<%= %>`) but with JSX rules:

| Traditional ERB | ERB + JSX Semantics |
|-----------------|---------------------|
| String interpolation | Tree structure |
| `<% if %>` can wrap partial tags | Must wrap complete elements |
| No validation | Must be well-formed |
| Helpers return strings | Components are first-class |

**Valid:**
```erb
<% if expanded %>
  <div class="expanded"><%= content %></div>
<% else %>
  <div><%= content %></div>
<% end %>
```

**Invalid** (partial tags in conditional):
```erb
<div>
<% if expanded %>
  </div><div class="expanded">
<% end %>
```

## Islands as Tags

Islands are `<ComponentName />` tags, not helper methods:

```erb
<AddToCartButton product_id=<%= @product.id %> client:load />
<ReviewList reviews=<%= @reviews %> client:visible />
<ReviewForm product_id=<%= @product.id %> client:idle />
```

The `client:` directive controls hydration:
- `client:load` - hydrate immediately
- `client:visible` - hydrate when scrolled into view
- `client:idle` - hydrate when browser is idle

## Frontmatter Uses @variables

Frontmatter adopts Rails' `@variable` convention:

```ruby
# app/pages/products/[slug].astro.rb
params :slug
revalidate 3600

@product = Product.find_by(slug: slug)
@reviews = Review.where(product_id: @product.id)

__END__
<h1><%= @product.name %></h1>
<AddToCartButton product_id=<%= @product.id %> client:load />
```

**Why:** Templates become identical between controllers and frontmatter.

## Templates Are Identical

Controller-backed view:
```erb
<%# app/views/products/show.html.erb %>
<h1><%= @product.name %></h1>
<AddToCartButton product_id=<%= @product.id %> client:load />
```

SFC page:
```erb
<%# app/pages/products/[slug].astro.rb (below __END__) %>
<h1><%= @product.name %></h1>
<AddToCartButton product_id=<%= @product.id %> client:load />
```

**Identical.** Copy/paste works.

---

# Part 2: Three Content Types

| Type | Examples | Caching | Syntax |
|------|----------|---------|--------|
| **Static** | About, Shipping policy | `prerender: true` | No DB queries |
| **Content (ISR)** | Product pages, Categories | `revalidate: 3600` | Cached, refreshed hourly |
| **Dynamic** | Shopping cart | No caching | Islands for interactivity |

---

# Part 3: File Structure

## Incremental Adoption

```
Existing Rails app
├── app/
│   ├── models/           # Unchanged - shared by all
│   │   ├── product.rb
│   │   ├── category.rb
│   │   └── cart_item.rb
│   │
│   ├── controllers/      # Unchanged - traditional routes
│   │   └── admin/
│   │       └── products_controller.rb
│   │
│   ├── views/            # Unchanged - traditional views
│   │   └── admin/
│   │       └── products/
│   │
│   ├── pages/            # NEW: SFC for routes needing ISR/islands
│   │   ├── index.astro.rb
│   │   ├── about.astro.rb
│   │   ├── products/
│   │   │   ├── index.astro.rb
│   │   │   └── [slug].astro.rb
│   │   └── cart.astro.rb
│   │
│   └── islands/          # NEW: Interactive components
│       ├── add_to_cart_button.jsx.rb
│       ├── cart.jsx.rb
│       ├── cart_count.jsx.rb
│       └── review_list.jsx.rb
│
├── config/
│   ├── routes.rb         # Takes precedence over pages/
│   └── database.yml
│
└── db/
    ├── schema.rb
    └── seeds.rb
```

## Routing Precedence

`config/routes.rb` takes precedence. Explicit delegation to pages:

```ruby
# config/routes.rb

# Traditional Rails - controller handles these
namespace :admin do
  resources :products
end

# Delegate to SFC pages
page '/'
page '/about'
page '/products'
page '/products/:slug'
page '/cart'

# Or mount entire directory
mount_pages '/store'  # Everything under /store/* uses app/pages/store/
```

---

# Part 4: Common Infrastructure

## Database Adapters (existing)

| Adapter | Runtime | Storage |
|---------|---------|---------|
| `dexie` | Browser | IndexedDB |
| `better_sqlite3` | Node | SQLite file |
| `d1` | Cloudflare | D1 database |

Same models work with any adapter.

## ISR Adapter

One in-memory implementation for Browser and Node:

```javascript
const cache = new Map();

export class ISRCache {
  static async serve(request, renderFn, { revalidate = 60 } = {}) {
    const key = typeof request === 'string' ? request : request.url;
    const cached = cache.get(key);
    const now = Date.now();

    if (cached && now < cached.staleAt) {
      return cached.data;
    }

    if (cached) {
      renderFn().then(data => {
        cache.set(key, { data, staleAt: now + revalidate * 1000 });
      });
      return cached.data;
    }

    const data = await renderFn();
    cache.set(key, { data, staleAt: now + revalidate * 1000 });
    return data;
  }

  static revalidate(key) {
    cache.delete(key);
  }
}
```

**Why same for Browser and Node:** The browser *is* a JavaScript runtime. Same architecture, just serving one user instead of thousands.

---

# Part 5: Example Pages

## Static Page (prerender)

```ruby
# app/pages/about.astro.rb
prerender true

__END__
<h1>About Our Store</h1>
<p>We sell quality products...</p>
```

No database, no ISR. Built once at deploy time.

## Content Page (ISR)

```ruby
# app/pages/products/[slug].astro.rb
params :slug
revalidate 3600

@product = Product.find_by(slug: slug)
@reviews = Review.where(product_id: @product.id).limit(5)

__END__
<h1><%= @product.name %></h1>
<p><%= @product.description %></p>
<p class="price">$<%= @product.price %></p>

<% if @product.in_stock? %>
  <AddToCartButton product_id=<%= @product.id %> client:load />
<% else %>
  <p class="out-of-stock">Out of Stock</p>
<% end %>

<h2>Reviews</h2>
<ReviewList reviews=<%= @reviews %> client:visible />
<ReviewForm product_id=<%= @product.id %> client:idle />
```

Cached for 1 hour. Three islands with different hydration strategies.

## Dynamic Page (cart)

```ruby
# app/pages/cart.astro.rb

__END__
<h1>Your Cart</h1>
<Cart client:load />
```

No caching. The entire cart is an island - fully interactive.

---

# Part 6: Islands

## Island Definition

```ruby
# app/islands/add_to_cart_button.jsx.rb
props :product_id

def AddToCartButton
  adding, setAdding = useState(false)

  handleClick = -> {
    setAdding(true)
    CartItem.create(product_id: product_id, quantity: 1).then {
      window.dispatchEvent(CustomEvent.new('cart-updated'))
      setAdding(false)
    }
  }

  %x{
    <button onClick={handleClick} disabled={adding}>
      {adding ? 'Adding...' : 'Add to Cart'}
    </button>
  }
end
```

## Island with Complex State

```ruby
# app/islands/cart.jsx.rb

def Cart
  items, setItems = useState([])
  loading, setLoading = useState(true)

  loadCart = -> {
    CartItem.includes(:product).all.then do |data|
      setItems(data)
      setLoading(false)
    end
  }

  useEffect -> { loadCart.() }, []

  useEffect -> {
    handler = -> { loadCart.() }
    window.addEventListener('cart-updated', handler)
    -> { window.removeEventListener('cart-updated', handler) }
  }, []

  removeItem = ->(id) {
    CartItem.destroy(id).then { loadCart.() }
  }

  updateQuantity = ->(id, qty) {
    CartItem.update(id, quantity: qty).then { loadCart.() }
  }

  total = items.reduce(0) { |sum, item| sum + (item.product.price * item.quantity) }

  return %x{<p>Loading cart...</p>} if loading

  %x{
    <div class="cart">
      {items.length === 0 ? (
        <p>Your cart is empty</p>
      ) : (
        <>
          <ul>
            {items.map(item => (
              <li key={item.id}>
                {item.product.name} × {item.quantity}
                <span>${(item.product.price * item.quantity).toFixed(2)}</span>
                <button onClick={() => updateQuantity(item.id, item.quantity + 1)}>+</button>
                <button onClick={() => updateQuantity(item.id, item.quantity - 1)}>−</button>
                <button onClick={() => removeItem(item.id)}>Remove</button>
              </li>
            ))}
          </ul>
          <p class="total">Total: ${total.toFixed(2)}</p>
        </>
      )}
    </div>
  }
end
```

---

# Part 7: Models

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :price, numericality: { greater_than: 0 }
  validates :inventory, numericality: { greater_than_or_equal_to: 0 }

  belongs_to :category, optional: true

  before_save :generate_slug

  def generate_slug
    self.slug ||= name.parameterize
  end

  def in_stock?
    inventory > 0
  end
end

# app/models/category.rb
class Category < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  has_many :products
end

# app/models/cart_item.rb
class CartItem < ApplicationRecord
  validates :quantity, numericality: { greater_than: 0 }
  belongs_to :product
end
```

Same models work everywhere - browser, Node, Cloudflare.

---

# Part 8: Seed Data

```ruby
# db/seeds.rb
categories = {
  electronics: Category.create!(name: "Electronics", slug: "electronics"),
  clothing: Category.create!(name: "Clothing", slug: "clothing"),
  home: Category.create!(name: "Home & Garden", slug: "home-garden")
}

[
  { name: "Wireless Headphones", price: 79.99, inventory: 23,
    category: :electronics, image: "https://picsum.photos/seed/headphones/400/300" },
  { name: "Bluetooth Speaker", price: 49.99, inventory: 15,
    category: :electronics, image: "https://picsum.photos/seed/speaker/400/300" },
  { name: "Cotton T-Shirt", price: 24.99, inventory: 50,
    category: :clothing, image: "https://picsum.photos/seed/tshirt/400/300" },
  { name: "Ceramic Plant Pot", price: 19.99, inventory: 40,
    category: :home, image: "https://picsum.photos/seed/plantpot/400/300" },
].each do |attrs|
  cat = categories[attrs.delete(:category)]
  Product.create!(attrs.merge(category: cat))
end
```

Placeholder images from picsum.photos - no binary assets needed.

---

# Part 9: Configuration

```bash
# Development (laptop)
JUNTOS_DATABASE=better_sqlite3 JUNTOS_TARGET=node bin/juntos dev

# Demo (GitHub Pages)
JUNTOS_DATABASE=dexie JUNTOS_TARGET=browser bin/juntos build

# Production (Cloudflare)
JUNTOS_DATABASE=d1 JUNTOS_TARGET=cloudflare bin/juntos build
```

---

# Part 10: Dockerfile

```dockerfile
ARG DATABASE=dexie
ARG TARGET=browser

ENV JUNTOS_DATABASE=${DATABASE}
ENV JUNTOS_TARGET=${TARGET}

RUN bin/juntos build

CMD if [ "${TARGET}" = "browser" ]; then \
      serve -s dist; \
    else \
      node dist/server.mjs; \
    fi
```

---

# Part 11: Migration Path

**What the Rails developer does:**

1. Keep existing Rails app (models, admin controllers, etc.)
2. Add `app/pages/` for customer-facing routes needing ISR/islands
3. Add `app/islands/` for interactive components
4. Copy controller logic to frontmatter (change `params[:slug]` to `slug` via `params :slug`)
5. Views work unchanged (same `@variable` syntax, same ERB)
6. Deploy with different target

**What stays the same:**
- Models (100%)
- Admin/backend (100%)
- Template syntax (100%)

**What changes:**
- Controller → frontmatter (minimal: add `params :slug`, `revalidate`)
- Helper-based components → island tags (better, not harder)

---

# Success Criteria

**Syntax:**
- ERB + JSX semantics work as specified
- Islands as `<Component client:load />` tags
- `@variables` in frontmatter match controllers
- Templates copy/paste between controllers and pages

**Infrastructure:**
- Database adapters work across targets
- ISR: One implementation for Browser + Node
- Cloudflare adapter for production scale

**Demo:**
- Three content types clearly demonstrated (static, ISR, dynamic)
- Same source builds for browser, Node, Cloudflare
- Incremental adoption path is clear

---

# The Story

> "I have a Rails store. The product pages need ISR, the cart needs real interactivity.
>
> I added `app/pages/` for those routes. Same models, same templates, same `@product`.
>
> Now it runs on Cloudflare. No rewrite. Same code."
