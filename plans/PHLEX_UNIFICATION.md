# Phlex Unification Plan

Unify view component handling around Phlex as the canonical Ruby representation, with bidirectional support for React interop and browser-side rendering.

## Blog Post Series Context

This is **Post 4** in a four-part series demonstrating Ruby2JS/Juntos capabilities:

| Post | Plan | Theme | Key Proof |
|------|------|-------|-----------|
| 1 | — | Patterns | Rails conventions transpile to JS |
| 2 | [HOTWIRE_TURBO.md](./HOTWIRE_TURBO.md) | Frameworks | Ruby becomes valid Stimulus/Turbo JS |
| 3 | [VITE_RUBY2JS.md](./VITE_RUBY2JS.md) | Tooling | Ruby as first-class frontend language |
| **4** | **PHLEX_UNIFICATION.md** | **Portability** | **Same Ruby → Phlex JS or React** |

**Builds on Post 3:** Vite serves Ruby files with HMR. Now the same Phlex component outputs to either Phlex JS (lightweight) or React (ecosystem).

**This post proves:** "Write once, target both"—choose your runtime without rewriting components.

**Dependencies:**
- [VITE_RUBY2JS.md](./VITE_RUBY2JS.md) — React preset uses Vite plugin infrastructure
- [VERCEL_TARGET.md](./VERCEL_TARGET.md) — `use_server`/`use_client` for RSC support

---

## Vision

```
                    ┌─────────────────────────────────────┐
                    │         JSX (authoring)             │
                    │   <Card title="Hi">content</Card>   │
                    └─────────────┬───────────────────────┘
                                  ↓ jsx.rb
                    ┌─────────────────────────────────────┐
                    │    Phlex Ruby (canonical form)      │
                    │  div { }, render Component.new      │
                    └─────────────┬───────────────────────┘
                                  ↓
                    ┌─────────────────────────────────────┐
                    │      pnode (synthetic AST)          │
                    │  s(:pnode, :div, attrs, children)   │
                    └──────┬──────────────────┬───────────┘
                           ↓                  ↓
                    ┌──────────────┐   ┌──────────────┐
                    │ phlex filter │   │ react filter │
                    └──────┬───────┘   └──────┬───────┘
                           ↓                  ↓
                    ┌──────────────┐   ┌──────────────┐
                    │  Phlex JS    │   │  React JS    │
                    │(HTML strings)│   │(virtual DOM) │
                    └──────────────┘   └──────────────┘
```

**Benefits:**

1. **Write once, target both** — Same Phlex Ruby produces Phlex JS or React JS
2. **Migration flexibility** — Start with React, switch to lighter Phlex when reactivity isn't needed
3. **Server/client parity** — Phlex Ruby runs on server (native) or browser (transpiled)
4. **Familiar JSX** — Optional authoring syntax for those who prefer it
5. **Idiomatic Phlex** — Full support for Phlex patterns, not a subset

## Stimulus as the Reactivity Layer

Phlex renders static HTML. For interactivity without React, Stimulus controllers provide a lightweight solution:

```ruby
# Phlex component with Stimulus hooks
class Counter < Phlex::HTML
  def view_template
    div(data_controller: "counter") do
      span(data_counter_target: "display") { "0" }
      button(data_action: "click->counter#increment") { "+" }
    end
  end
end
```

```ruby
# Stimulus controller (transpiled to JS by Ruby2JS)
class CounterController < Stimulus::Controller
  def connect
    @count = 0
  end

  def increment
    @count += 1
    displayTarget.textContent = @count.to_s
  end
end
```

| Concern       | Handled By                |
| ------------- | ------------------------- |
| Initial HTML  | Phlex (server or browser) |
| Event binding | Stimulus (data-action)    |
| State         | Stimulus controller       |
| DOM updates   | Stimulus targets          |

**Phlex + Stimulus vs React:**
- React: state change → virtual DOM diff → patch DOM
- Stimulus: event → controller method → direct DOM update

Stimulus is lighter but requires explicit DOM manipulation. React is heavier but declarative. The choice depends on complexity needs.

## Migration Scenarios

### Scenario 1: Legacy React → Modern Phlex

**Starting point:** Webpacker (deprecated), React/JSX components, large bundle

**End goal:** Modern tooling (esbuild/vite), Phlex + Stimulus, smaller footprint

#### Step 1: Categorize Components

| Category            | Example                    | Migration Target        |
| ------------------- | -------------------------- | ----------------------- |
| Presentational      | `<Card>`, `<Avatar>`       | Phlex (trivial)         |
| Simple interaction  | Toggle, dropdown           | Phlex + Stimulus        |
| Form handling       | Input validation           | Phlex + Stimulus        |
| Complex state       | Shopping cart, live search | Keep React or use Turbo |
| Ecosystem dependent | Rich text editor, charts   | Keep React wrapper      |

#### Step 2: Convert Presentational Components

```jsx
// Before: React
function Card({ title, children }) {
  return (
    <div className="card">
      <h2>{title}</h2>
      {children}
    </div>
  );
}
```

```ruby
# After: Phlex
class Card < Phlex::HTML
  def initialize(title:)
    @title = title
  end

  def view_template(&block)
    div(class: "card") do
      h2 { @title }
      yield if block_given?
    end
  end
end
```

#### Step 3: Replace React State with Stimulus

```jsx
// Before: React with useState
function Counter() {
  const [count, setCount] = useState(0);
  return (
    <div>
      <span>{count}</span>
      <button onClick={() => setCount(c => c + 1)}>+</button>
    </div>
  );
}
```

```ruby
# After: Phlex + Stimulus
class Counter < Phlex::HTML
  def view_template
    div(data_controller: "counter") do
      span(data_counter_target: "display") { "0" }
      button(data_action: "click->counter#increment") { "+" }
    end
  end
end

class CounterController < Stimulus::Controller
  def connect
    @count = 0
  end

  def increment
    @count += 1
    displayTarget.textContent = @count.to_s
  end
end
```

#### Step 4: Complex State Options

For components where Stimulus feels awkward:

**Option A: Turbo Frames** (server-driven updates)
```ruby
turbo_frame_tag "cart" do
  render CartComponent.new(items: @cart.items)
end
```

**Option B: Keep React Island** (hybrid approach)
```ruby
# Phlex wrapper for React component
div(data_react_component: "ShoppingCart", data_props: items.to_json)
```

#### Step 5: Remove Legacy Stack

Once migration complete:
- Remove Webpacker
- Remove react, react-dom dependencies
- Simpler build with Ruby2JS + esbuild

---

### Scenario 2: Phlex Prototype → React

**Starting point:** Phlex components, Stimulus for interactivity, works for prototype

**Discovered needs:** Complex state, frequent re-renders, React ecosystem (UI libraries), team prefers React

#### Key Advantage: Same Source, Different Target

The same Phlex Ruby transpiles to either target with no changes:

```ruby
# This Phlex Ruby...
class Card < Phlex::HTML
  def initialize(title:)
    @title = title
  end

  def view_template
    div(class: "card") do
      h2 { @title }
      yield if block_given?
    end
  end
end
```

```javascript
// ...outputs Phlex JS (string concat):
class Card {
  render({ title }, children) {
    let _phlex_out = "";
    _phlex_out += `<div class="card">`;
    _phlex_out += `<h2>${title}</h2>`;
    _phlex_out += children?.() || "";
    _phlex_out += `</div>`;
    return _phlex_out;
  }
}

// ...OR React JS (same source!):
function Card({ title, children }) {
  return (
    <div className="card">
      <h2>{title}</h2>
      {children}
    </div>
  );
}
```

#### Step 1: Add React State Incrementally

```ruby
# Add React hooks to Phlex component
class Counter < Phlex::HTML
  def view_template
    count, setCount = useState(0)

    div do
      span { count }
      button(onclick: -> { setCount.(count + 1) }) { "+" }
    end
  end
end
```

Transpiles to:
```javascript
function Counter() {
  const [count, setCount] = useState(0);
  return (
    <div>
      <span>{count}</span>
      <button onClick={() => setCount(count + 1)}>+</button>
    </div>
  );
}
```

#### Step 2: Replace Stimulus with React Patterns

| Stimulus                  | React Equivalent        |
| ------------------------- | ----------------------- |
| `data-controller`         | Component               |
| `data-target`             | useRef or JSX reference |
| `data-action`             | onClick/onChange props  |
| Controller instance state | useState/useReducer     |
| connect/disconnect        | useEffect cleanup       |

#### Step 3: Switch Build Target

```ruby
# Same Ruby source, different output
Ruby2JS.convert(source, filters: [:phlex])  # → Phlex JS (strings)
Ruby2JS.convert(source, filters: [:react])  # → React JS (virtual DOM)
```

---

### The Ruby2JS Advantage

Both migrations are **incremental and reversible** because:

1. **Same source language** — Ruby throughout
2. **Same authoring syntax** — Phlex patterns (or JSX via jsx.rb)
3. **Build-time target selection** — Switch output with a config flag
4. **No rewrite required** — Mechanical transformation, not manual conversion

## Breaking Change: Wunderbar Removal

Wunderbar (`_div`, `_Component`) will be removed in favor of Phlex patterns. This affects:

- `lib/ruby2js/jsx.rb` — Output changes from wunderbar to Phlex
- `lib/ruby2js/filter/react.rb` — Must recognize Phlex patterns instead of wunderbar
- `lib/ruby2js/filter/vue.rb` — Same changes as react filter
- Documentation and examples

**Migration:** Users with wunderbar-style code will need to update to Phlex syntax.

## pnode: The Synthetic AST Node

A new `pnode` (Phlex node) provides a clean contract between jsx.rb and the filters:

```ruby
# HTML element (lowercase symbol)
s(:pnode, :div, s(:hash, s(:pair, s(:sym, :class), s(:str, "card"))),
  s(:pnode, :h1, s(:hash), s(:pnode_text, "Title")))

# Component (uppercase symbol)
s(:pnode, :Card, s(:hash, s(:pair, s(:sym, :title), s(:str, "Hi"))),
  s(:pnode_text, "content"))

# Custom element (string)
s(:pnode, "my-widget", s(:hash, s(:pair, s(:sym, :data_id), s(:lvar, :id))),
  s(:pnode, :span, s(:hash), s(:pnode_text, "inner")))

# Fragment (nil tag)
s(:pnode, nil, s(:hash),
  s(:pnode, :h1, s(:hash)),
  s(:pnode, :h2, s(:hash)))

# Text content
s(:pnode_text, s(:str, "static text"))
s(:pnode_text, s(:lvar, :dynamic_var))
```

### Tag Type Detection

```ruby
case tag
when nil
  # Fragment
when Symbol
  if tag.to_s[0] =~ /[A-Z]/
    # Component: Card, MyWidget
  else
    # HTML element: div, span, br
  end
when String
  # Custom element: "my-widget", "custom-tag"
end
```

### Why pnode?

Without synthetic nodes, filters must pattern-match method calls:

```ruby
# Fragile: could match unrelated code
def on_send(node)
  target, method, *args = node.children
  return super unless target.nil?

  if HTML_ELEMENTS.include?(method)      # div(), span()
    # ...
  elsif method.to_s[0] =~ /[A-Z]/        # Could be constant, not component
    # ...
  elsif method == :tag                    # tag("custom")
    # ...
  elsif method == :render                 # render Component.new
    # ...
```

With pnode, intent is explicit:

```ruby
def on_pnode(node)
  tag, attrs, *children = node.children
  # Clear semantics, no ambiguity
end
```

## JSX to Phlex Conversion

### Element Mapping

| JSX                 | Phlex Ruby                    | pnode                              |
| ------------------- | ----------------------------- | ---------------------------------- |
| `<div class="x"/>`  | `div(class: "x")`             | `s(:pnode, :div, s(:hash, ...))`   |
| `<br/>`             | `br`                          | `s(:pnode, :br, s(:hash))`         |
| `<Card title="x"/>` | `render Card.new(title: "x")` | `s(:pnode, :Card, s(:hash, ...))`  |
| `<my-widget/>`      | `tag("my-widget")`            | `s(:pnode, "my-widget", s(:hash))` |
| `<><h1/><h2/></>`   | (fragment)                    | `s(:pnode, nil, s(:hash), ...)`    |
| `text content`      | `plain "text content"`        | `s(:pnode_text, s(:str, "..."))`   |
| `{expression}`      | `plain expression`            | `s(:pnode_text, s(:lvar, ...))`    |

### Attribute Mapping

| JSX             | Phlex                               |
| --------------- | ----------------------------------- |
| `class="x"`     | `class: "x"`                        |
| `className="x"` | `class: "x"`                        |
| `htmlFor="x"`   | `for: "x"`                          |
| `onClick={h}`   | `onclick: h`                        |
| `data-id="x"`   | `data_id: "x"` or `data: {id: "x"}` |
| `{...props}`    | `**props`                           |

### Children and Blocks

```jsx
// JSX
<div>
  <h1>Title</h1>
  <p>{content}</p>
</div>
```

```ruby
# Phlex Ruby
div do
  h1 { "Title" }
  p { content }
end
```

```ruby
# pnode
s(:pnode, :div, s(:hash),
  s(:pnode, :h1, s(:hash), s(:pnode_text, s(:str, "Title"))),
  s(:pnode, :p, s(:hash), s(:pnode_text, s(:lvar, :content))))
```

## Phlex Filter Updates

### Current State

The phlex filter already handles:
- HTML5 elements (void and standard)
- Static and dynamic attributes
- Nested elements
- Loops and conditionals
- Instance variables as parameters
- Special methods: `plain`, `unsafe_raw`, `whitespace`, `comment`, `doctype`

### Required Additions

1. **Component composition** (`render Component.new`)
2. **Custom elements** (`tag("name")`)
3. **pnode consumption** (in addition to direct Phlex Ruby)
4. **Slots** (Phlex's content projection)
5. **Yield for blocks**

### Component Composition

```ruby
# Phlex Ruby
render Card.new(title: "Hi") do
  plain "content"
end
```

```javascript
// Generated JS (Phlex target)
_phlex_out += Card.render({ title: "Hi" }, () => {
  _phlex_out += "content";
});
```

### Custom Elements

```ruby
# Phlex Ruby
tag("my-widget", class: "x") do
  span { "inner" }
end
```

```javascript
// Generated JS
_phlex_out += `<my-widget class="x">`;
_phlex_out += `<span>inner</span>`;
_phlex_out += `</my-widget>`;
```

## React Filter Updates

### Current State

The react filter handles wunderbar patterns (`_div`, `_Component`). It must be updated to recognize Phlex patterns.

### Phlex to React Mapping

| Phlex Ruby                  | React Output                |
| --------------------------- | --------------------------- |
| `div(class: "x") { }`       | `<div className="x"></div>` |
| `render Card.new(title: x)` | `<Card title={x}/>`         |
| `tag("my-widget")`          | `<my-widget/>`              |
| `plain text`                | `{text}`                    |
| `br`                        | `<br/>`                     |

### Attribute Normalization

Phlex uses HTML attribute names; React uses camelCase:

```ruby
# In react filter
PHLEX_TO_REACT_ATTRS = {
  'class' => 'className',
  'for' => 'htmlFor',
  'onclick' => 'onClick',
  'onchange' => 'onChange',
  # ... etc
}
```

### Event Handlers

Phlex traditionally doesn't have event handlers (server-side). For React target, they pass through:

```ruby
# Phlex Ruby (with events for React target)
button(onclick: handler) { "Click" }
```

```javascript
// React output
<button onClick={handler}>Click</button>
```

## Implementation Phases

### Phase 1: pnode Infrastructure (~1 day)

1. [ ] Define pnode structure in converter
2. [ ] Add pnode handler to serializer (for debugging/inspection)
3. [ ] Add pnode_text node type
4. [ ] Write unit tests for pnode creation and handling

### Phase 2: jsx.rb Rewrite (~2 days)

1. [ ] Update jsx.rb to output pnodes instead of wunderbar strings
2. [ ] Add HTML_ELEMENTS list (import from phlex.rb)
3. [ ] Handle uppercase vs lowercase detection
4. [ ] Handle custom elements (hyphenated names)
5. [ ] Handle fragments
6. [ ] Handle spread attributes (`{...props}`)
7. [ ] Update jsx_spec.rb tests

### Phase 3: Phlex Filter Enhancement (~2 days)

1. [ ] Add `on_pnode` handler
2. [ ] Add `on_pnode_text` handler
3. [ ] Implement component composition (`render Component.new`)
4. [ ] Implement custom elements (`tag("name")`)
5. [ ] Handle fragments
6. [ ] Update phlex_spec.rb tests

### Phase 4: React Filter Migration (~2 days)

1. [ ] Add `on_pnode` handler alongside existing wunderbar support
2. [ ] Add attribute normalization (class → className, etc.)
3. [ ] Handle component detection (uppercase tag)
4. [ ] Handle custom elements
5. [ ] Handle fragments (React.Fragment or <>)
6. [ ] Deprecation warnings for wunderbar patterns
7. [ ] Update react_spec.rb tests

### Phase 5: Vue Filter Migration (~1 day)

1. [ ] Add `on_pnode` handler
2. [ ] Attribute handling for Vue (class, style bindings)
3. [ ] Component handling
4. [ ] Update vue_spec.rb tests

### Phase 6: Wunderbar Removal (~1 day)

1. [ ] Remove wunderbar pattern matching from react filter
2. [ ] Remove wunderbar pattern matching from vue filter
3. [ ] Update all documentation
4. [ ] Update demo examples
5. [ ] Add migration guide

### Phase 7: Selfhost Compatibility (~2 days)

1. [ ] Ensure jsx.rb transpiles to JavaScript
2. [ ] Ensure pnode handling works in selfhost converter
3. [ ] Update phlex.js filter for selfhost
4. [ ] Update react.js filter for selfhost
5. [ ] Run selfhost tests

**Total: ~11 days**

## Phlex Feature Support Matrix

| Feature              | Phlex Filter | React Filter | Notes                                  |
| -------------------- | ------------ | ------------ | -------------------------------------- |
| HTML elements        | ✅            | ✅            |                                        |
| Void elements        | ✅            | ✅            | br, img, etc.                          |
| Attributes (static)  | ✅            | ✅            |                                        |
| Attributes (dynamic) | ✅            | ✅            |                                        |
| Boolean attributes   | ✅            | ✅            |                                        |
| Data attributes      | ✅            | ✅            | `data_foo` or `data: {foo:}`           |
| Nested elements      | ✅            | ✅            |                                        |
| Text content         | ✅            | ✅            | `plain`                                |
| Raw HTML             | ✅            | ⚠️           | `unsafe_raw` (dangerouslySetInnerHTML) |
| Components           | Phase 3      | Phase 4      | `render Component.new`                 |
| Custom elements      | Phase 3      | Phase 4      | `tag("name")`                          |
| Fragments            | Phase 3      | Phase 4      |                                        |
| Slots                | Future       | N/A          | Phlex-specific                         |
| Conditionals         | ✅            | ✅            | if/unless                              |
| Loops                | ✅            | ✅            | each/map                               |
| Event handlers       | Passthrough  | ✅            | onclick, etc.                          |

## Example: Full Component

### Input (JSX)

```jsx
<Card title={title} className="featured">
  <h1>{title}</h1>
  <p>{description}</p>
  {items.map(item => (
    <ListItem key={item.id} item={item} onClick={handleClick}/>
  ))}
  <custom-footer data-year="2024"/>
</Card>
```

### Intermediate (Phlex Ruby)

```ruby
render Card.new(title: title, class: "featured") do
  h1 { title }
  p { description }
  items.each do |item|
    render ListItem.new(key: item.id, item: item, onclick: handleClick)
  end
  tag("custom-footer", data_year: "2024")
end
```

### Output (Phlex JS)

```javascript
_phlex_out += Card.render({ title, class: "featured" }, () => {
  _phlex_out += `<h1>${String(title)}</h1>`;
  _phlex_out += `<p>${String(description)}</p>`;
  for (let item of items) {
    _phlex_out += ListItem.render({ key: item.id, item, onclick: handleClick });
  }
  _phlex_out += `<custom-footer data-year="2024"></custom-footer>`;
});
```

### Output (React JS)

```javascript
<Card title={title} className="featured">
  <h1>{title}</h1>
  <p>{description}</p>
  {items.map(item => (
    <ListItem key={item.id} item={item} onClick={handleClick}/>
  ))}
  <custom-footer data-year="2024"/>
</Card>
```

## Success Criteria

1. [ ] JSX parses to pnodes correctly (all jsx_spec tests pass)
2. [ ] Phlex Ruby parses to pnodes correctly
3. [ ] pnodes render to Phlex JS (string concatenation)
4. [ ] pnodes render to React JS (JSX/createElement)
5. [ ] Components work in both targets
6. [ ] Custom elements work in both targets
7. [ ] All existing phlex_spec tests pass
8. [ ] All existing react_spec tests pass (with updated syntax)
9. [ ] Selfhost transpilation works for all new code
10. [ ] Documentation updated with migration guide

## Open Questions

1. **Slots**: How should Phlex slots map to React? (children vs render props)
2. **Streaming**: Phlex supports streaming; relevant for browser target?
3. **SVG**: Phlex::SVG has different element set; how to handle in pnode?
4. **Preact**: Should preact filter also be updated, or deprecated?
5. **Event naming**: Normalize to lowercase (Phlex) or camelCase (React) in pnode?

## References

- [Phlex documentation](https://www.phlex.fun/)
- [React JSX documentation](https://react.dev/learn/writing-markup-with-jsx)
- Existing filters: `lib/ruby2js/filter/phlex.rb`, `lib/ruby2js/filter/react.rb`
- JSX parser: `lib/ruby2js/jsx.rb`
