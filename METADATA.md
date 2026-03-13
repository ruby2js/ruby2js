# Cross-File Metadata Pipeline

Rails filters share metadata across files via the `options[:metadata]` hash. This enables type-aware view transpilation and correct async/sync decisions in tests.

## Metadata Flow

```
Ruby2JS.convert(source, metadata: metadata, ...)
                                ↑
                    Shared hash, populated by each filter
```

Filters access metadata via `@options[:metadata]`. The hash persists across multiple `convert()` calls within a build, allowing controllers to inform views.

## Metadata Structure

```ruby
metadata = {
  # Controller filter populates:
  'view_types' => {
    'events/summary' => {           # "controller_plural/action_name"
      'people_by_type' => 'map',    # ivar name (without @) => type string
      'total' => 'number',
    }
  },
  'controller_files' => {
    'EventsController' => 'events_controller.js'
  },

  # Model filter populates:
  'models' => {
    'Person' => {
      'associations' => [
        { 'name' => 'posts', 'type' => 'has_many' },
        { 'name' => 'profile', 'type' => 'has_one', 'class_name' => 'UserProfile' }
      ],
      'scopes' => ['active', 'published'],
      'enum_predicates' => ['active?', 'inactive?'],  # synchronous
      'enum_bangs' => ['active!', 'inactive!'],        # synchronous
      'instance_methods' => ['full_name'],
      'file' => '/app/models/person.rb'
    }
  },

  # Concern filter populates:
  'concerns' => {
    'Trackable' => { 'methods' => ['track_event'] }
  }
}
```

## Key Consumers

| Metadata | Consumer | Purpose |
|----------|----------|---------|
| `view_types` | ERB filter (`seed_view_types`) | Seeds pragma's `@var_types` for type-aware transformations |
| `models` | Test filter | Async/sync decisions, fixture generation, imports |
| `enum_predicates`/`enum_bangs` | Test filter | Identifies synchronous methods (no `await`) |
| `controller_files` | Test filter | Resolves controller imports |
| `concerns` | Future use | Method tracking across included modules |

## Controller Type Inference

The controller filter's `infer_ivar_type()` method (in `lib/ruby2js/filter/rails/controller.rb`) determines types from:

- **Literals**: `:hash`, `:array`, `:str`/`:dstr`, `:int`/`:float` AST node types
- **Method returns**: Lists in `IVAR_TYPE_METHODS_ARRAY`, `_HASH`, `_NUMBER`, `_STRING`
- **group_by**: Both `:send` (block_pass) and `:block` forms → `:map`
- **Block methods**: `select`, `map`, `reject`, etc. → `:array`

The `walk_body_metadata()` method walks each action body, tracking:
- `:ivasgn` nodes → records ivar types via `infer_ivar_type()`
- `:lvasgn` nodes → tracks local variable types for `@ivar = lvar` propagation
- Before-action methods (filtered by `only`/`except`) are included

## ERB Filter Consumption

The ERB filter's `seed_view_types()` maps controller metadata to pragma's `@var_types`:
- Seeds both `@var_types[:people_by_type]` and `@var_types[:@people_by_type]`
- The non-prefixed key is used for local variables (after `transform_ivars_to_locals`)
- The `@`-prefixed key is used for ivar nodes in pragma's `var_type()` lookup

## Adding a New Inferred Type

1. Add the method name to the appropriate `IVAR_TYPE_METHODS_*` constant in `controller.rb`
2. If the type needs special JS handling, add cases in `pragma.rb`'s `on_send`/`on_block`
3. Add a test in `spec/rails_controller_spec.rb` for metadata recording
4. Add a test in `spec/pragma_spec.rb` for the JS transformation
5. Update `docs/src/_docs/juntos/metadata.md` (user-facing)
