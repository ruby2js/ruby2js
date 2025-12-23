# Phlex Unification Plan

Unify view component handling around Phlex as the canonical Ruby representation, with bidirectional support for React interop and browser-side rendering.

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

| JSX | Phlex Ruby | pnode |
|-----|------------|-------|
| `<div class="x"/>` | `div(class: "x")` | `s(:pnode, :div, s(:hash, ...))` |
| `<br/>` | `br` | `s(:pnode, :br, s(:hash))` |
| `<Card title="x"/>` | `render Card.new(title: "x")` | `s(:pnode, :Card, s(:hash, ...))` |
| `<my-widget/>` | `tag("my-widget")` | `s(:pnode, "my-widget", s(:hash))` |
| `<><h1/><h2/></>` | (fragment) | `s(:pnode, nil, s(:hash), ...)` |
| `text content` | `plain "text content"` | `s(:pnode_text, s(:str, "..."))` |
| `{expression}` | `plain expression` | `s(:pnode_text, s(:lvar, ...))` |

### Attribute Mapping

| JSX | Phlex |
|-----|-------|
| `class="x"` | `class: "x"` |
| `className="x"` | `class: "x"` |
| `htmlFor="x"` | `for: "x"` |
| `onClick={h}` | `onclick: h` |
| `data-id="x"` | `data_id: "x"` or `data: {id: "x"}` |
| `{...props}` | `**props` |

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

| Phlex Ruby | React Output |
|------------|--------------|
| `div(class: "x") { }` | `<div className="x"></div>` |
| `render Card.new(title: x)` | `<Card title={x}/>` |
| `tag("my-widget")` | `<my-widget/>` |
| `plain text` | `{text}` |
| `br` | `<br/>` |

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

### Phase 1: pnode Infrastructure

1. [ ] Define pnode structure in converter
2. [ ] Add pnode handler to serializer (for debugging/inspection)
3. [ ] Add pnode_text node type
4. [ ] Write unit tests for pnode creation and handling

### Phase 2: jsx.rb Rewrite

1. [ ] Update jsx.rb to output pnodes instead of wunderbar strings
2. [ ] Add HTML_ELEMENTS list (import from phlex.rb)
3. [ ] Handle uppercase vs lowercase detection
4. [ ] Handle custom elements (hyphenated names)
5. [ ] Handle fragments
6. [ ] Handle spread attributes (`{...props}`)
7. [ ] Update jsx_spec.rb tests

### Phase 3: Phlex Filter Enhancement

1. [ ] Add `on_pnode` handler
2. [ ] Add `on_pnode_text` handler
3. [ ] Implement component composition (`render Component.new`)
4. [ ] Implement custom elements (`tag("name")`)
5. [ ] Handle fragments
6. [ ] Update phlex_spec.rb tests

### Phase 4: React Filter Migration

1. [ ] Add `on_pnode` handler alongside existing wunderbar support
2. [ ] Add attribute normalization (class → className, etc.)
3. [ ] Handle component detection (uppercase tag)
4. [ ] Handle custom elements
5. [ ] Handle fragments (React.Fragment or <>)
6. [ ] Deprecation warnings for wunderbar patterns
7. [ ] Update react_spec.rb tests

### Phase 5: Vue Filter Migration

1. [ ] Add `on_pnode` handler
2. [ ] Attribute handling for Vue (class, style bindings)
3. [ ] Component handling
4. [ ] Update vue_spec.rb tests

### Phase 6: Wunderbar Removal

1. [ ] Remove wunderbar pattern matching from react filter
2. [ ] Remove wunderbar pattern matching from vue filter
3. [ ] Update all documentation
4. [ ] Update demo examples
5. [ ] Add migration guide

### Phase 7: Selfhost Compatibility

1. [ ] Ensure jsx.rb transpiles to JavaScript
2. [ ] Ensure pnode handling works in selfhost converter
3. [ ] Update phlex.js filter for selfhost
4. [ ] Update react.js filter for selfhost
5. [ ] Run selfhost tests

## Phlex Feature Support Matrix

| Feature | Phlex Filter | React Filter | Notes |
|---------|--------------|--------------|-------|
| HTML elements | ✅ | ✅ | |
| Void elements | ✅ | ✅ | br, img, etc. |
| Attributes (static) | ✅ | ✅ | |
| Attributes (dynamic) | ✅ | ✅ | |
| Boolean attributes | ✅ | ✅ | |
| Data attributes | ✅ | ✅ | `data_foo` or `data: {foo:}` |
| Nested elements | ✅ | ✅ | |
| Text content | ✅ | ✅ | `plain` |
| Raw HTML | ✅ | ⚠️ | `unsafe_raw` (dangerouslySetInnerHTML) |
| Components | Phase 3 | Phase 4 | `render Component.new` |
| Custom elements | Phase 3 | Phase 4 | `tag("name")` |
| Fragments | Phase 3 | Phase 4 | |
| Slots | Future | N/A | Phlex-specific |
| Conditionals | ✅ | ✅ | if/unless |
| Loops | ✅ | ✅ | each/map |
| Event handlers | Passthrough | ✅ | onclick, etc. |

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
