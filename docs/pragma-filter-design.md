# Pragma Filter Design Summary

## Architecture

1. **Opt-in filter** - loaded via `require 'ruby2js/filter/pragma'`, zero impact to non-users

2. **Two-phase approach**:
   - **Phase 1**: Scan all comments for `# Pragma: <name>` patterns, build a hash of `line_number => Set<pragma_symbols>`
   - **Phase 2**: Walk AST looking for shapes that match pragma transformations; check if the top node's line has a matching pragma

3. **Line-based matching** - avoids Parser's comment association quirks (comments often attach to inner nodes, not the statement)

## Transformation Strategies (in order of preference)

1. **Use existing converters** - e.g., `:deff` already forces function syntax over arrow functions
2. **Introduce synthetic node types** - e.g., `:nullish_asgn` for `??=` when no existing handler fits
3. **Other alternatives** - instance variables or markers when neither above works

## Known Use Cases

- `# Pragma: ??` - convert `||`/`||=` to `??`/`??=` (nullish semantics)
- `# Pragma: noes2015` - force traditional `function` instead of arrow function (for correct `this` binding in jQuery/DOM callbacks)

## Key Code Pattern

```ruby
def scan_pragmas
  @comments.values.flatten.each do |comment|
    if comment.text =~ /#\s*Pragma:\s*(\S+)/i
      @pragmas[comment.loc.line] ||= Set.new
      @pragmas[comment.loc.line] << PRAGMAS[$1]
    end
  end
end

def on_or_asgn(node)
  return process(s(:nullish_asgn, ...)) if pragma?(node.loc.line, :nullish)
  super
end
```
