# Ruby2JS Self-hosted CLI
#
# This file provides command-line functionality for the bundled ruby2js.mjs.
# It is included in the bundle and only runs when the module is executed directly.
#
# Usage:
#   node ruby2js.mjs [options] [file]
#   echo "puts 'hello'" | node ruby2js.mjs [options]

# Dynamic imports for Node.js-only modules (these will only be loaded when CLI runs)
fs = nil
fileURLToPath = nil

if typeof(window) == 'undefined'
  fs = await import('fs')
  fileURLToPath = (await import('url')).fileURLToPath
end

# ============================================================================
# AST Formatting and Inspection
# ============================================================================

# Format Prism AST node for display (verbose mode shows all properties)
def format_prism_node(node, indent = '', options = {}, seen = nil)
  verbose = options[:verbose] || false
  show_loc = options[:showLoc] || false
  seen ||= []

  return "#{indent}null" if node.nil? || node == undefined
  return "#{indent}#{JSON.stringify(node)}" unless node.is_a?(Object)

  # Detect circular references
  if seen.include?(node)
    return "#{indent}[Circular]"
  end
  seen.push(node)

  if Array.isArray(node)
    return "#{indent}[]" if node.length == 0
    items = node.map { |item| format_prism_node(item, indent + '  ', options, seen) }
    return "#{indent}[\n#{items.join(",\n")}\n#{indent}]"
  end

  # Check if it's a Prism node (has constructor with name)
  type = node.constructor&.name || 'Object'

  # Skip location objects for brevity unless showLoc is true
  if !show_loc && (type.end_with?('Location') || type == 'Location')
    if node.startOffset != undefined
      return "#{indent}<#{type} #{node.startOffset}-#{node.startOffset + (node.length || 0)}>"
    end
    return "#{indent}<#{type}>"
  end

  # For AST nodes, show type and relevant properties
  props = []
  Object.entries(node).each do |key, value|
    # Skip internal properties unless verbose
    next if !verbose && key.start_with?('_')
    # Skip location properties unless showLoc
    next if !show_loc && (key == 'location' || key.end_with?('Loc'))
    next if value.nil? || value == undefined

    formatted = format_prism_node(value, indent + '  ', options, seen)
    if formatted.include?("\n")
      props.push("#{indent}  #{key}:\n#{formatted}")
    else
      props.push("#{indent}  #{key}: #{formatted.trim()}")
    end
  end

  return "#{indent}(#{type})" if props.length == 0
  "#{indent}(#{type}\n#{props.join("\n")}\n#{indent})"
end

# Inspect a single Prism node - show ALL properties with types
def inspect_prism_node(node)
  if !node || !(node.is_a?(Object))
    return "Value: #{JSON.stringify(node)} (#{typeof(node)})"
  end

  type = node.constructor&.name || 'Object'
  lines = ["Node Type: #{type}", '']

  # Get all own properties
  all_props = Object.getOwnPropertyNames(node)
  # Also get prototype methods that look like getters
  proto = Object.getPrototypeOf(node)
  proto_props = if proto
    Object.getOwnPropertyNames(proto).filter do |p|
      next false if p == 'constructor' || p.start_with?('_')
      desc = Object.getOwnPropertyDescriptor(proto, p)
      desc && (desc.get || desc.value.is_a?(Function))
    end
  else
    []
  end

  lines.push('Own Properties:')
  all_props.sort.each do |key|
    value = node[key]
    value_type = if value.nil? then 'null'
    elsif value == undefined then 'undefined'
    elsif Array.isArray(value) then "Array[#{value.length}]"
    elsif value.is_a?(Object) then value.constructor&.name || 'Object'
    else typeof(value)
    end
    preview = if value.is_a?(String) then "\"#{value[0, 50]}\""
    elsif value.is_a?(Boolean) || value.is_a?(Number) then value.to_s
    else value_type
    end
    lines.push("  #{key}: #{preview} (#{value_type})")
  end

  if proto_props.length > 0
    lines.push('')
    lines.push('Prototype Methods/Getters:')
    proto_props.sort.each do |key|
      begin
        desc = Object.getOwnPropertyDescriptor(proto, key)
        if desc.get
          value = node[key]
          value_type = if value.nil? then 'null'
          elsif value == undefined then 'undefined'
          elsif Array.isArray(value) then "Array[#{value.length}]"
          elsif value.is_a?(Object) then value.constructor&.name || 'Object'
          else typeof(value)
          end
          preview = if value.is_a?(String) then "\"#{value[0, 50]}\""
          elsif value.is_a?(Boolean) || value.is_a?(Number) then value.to_s
          else value_type
          end
          lines.push("  #{key}: #{preview} (#{value_type}) [getter]")
        elsif desc.value.is_a?(Function)
          lines.push("  #{key}() [method]")
        end
      rescue => e
        lines.push("  #{key}: <error: #{e.message}>")
      end
    end
  end

  lines.join("\n")
end

# Find nodes matching a type pattern in Prism AST
def find_prism_nodes(node, pattern, results = [], path = 'root')
  return results if !node || !(node.is_a?(Object))

  type = node.constructor&.name || ''
  regex = Regexp.new(pattern, 'i')

  if regex.test(type)
    results.push({ path: path, type: type, node: node })
  end

  # Recurse into arrays
  if Array.isArray(node)
    node.each_with_index { |child, i| find_prism_nodes(child, pattern, results, "#{path}[#{i}]") }
  else
    # Recurse into object properties
    Object.entries(node).each do |key, value|
      next if key.start_with?('_') || key == 'location'
      if value && value.is_a?(Object)
        find_prism_nodes(value, pattern, results, "#{path}.#{key}")
      end
    end
  end

  results
end

# Format Ruby2JS AST node (Parser-compatible format)
def format_ast(node, indent = '')
  return 'nil' if node.nil? || node == undefined
  return JSON.stringify(node) unless node.is_a?(Object) && node.type

  type = node.type
  children = node.children || []

  return "s(:#{type})" if children.length == 0

  # Check if any children are AST nodes
  has_node_children = children.any? { |c| c && c.is_a?(Object) && c.type }

  if !has_node_children
    # All primitives - single line
    return "s(:#{type}, #{children.map { |c| JSON.stringify(c) }.join(', ')})"
  end

  # Multi-line format
  lines = ["s(:#{type},"]
  children.each_with_index do |child, i|
    comma = i < children.length - 1 ? ',' : ''
    if child && child.is_a?(Object) && child.type
      formatted = format_ast(child, indent + '  ')
      lines.push("#{indent}  #{formatted}#{comma}")
    else
      lines.push("#{indent}  #{JSON.stringify(child)}#{comma}")
    end
  end
  lines.push("#{indent})")
  lines.join("\n")
end

# ============================================================================
# Main CLI Function
# ============================================================================

async def run_cli
  # Initialize Prism parser
  prism_parse = await initPrism()

  args = process.argv[2..-1] || []
  output_mode = 'js'
  options = { eslevel: 2020 }
  file = nil
  inline_code = nil
  search_pattern = nil
  inspect_path = nil
  verbose = false
  show_loc = false

  i = 0
  while i < args.length
    arg = args[i]

    if arg == '--ast'
      output_mode = 'walker-ast'
    elsif arg == '--prism-ast'
      output_mode = 'prism-ast'
    elsif arg == '--js'
      output_mode = 'js'
    elsif arg == '-e'
      i += 1
      inline_code = args[i]
    elsif arg.start_with?('--eslevel=')
      options[:eslevel] = parseInt(arg.split('=')[1], 10)
    elsif arg == '--es2015'
      options[:eslevel] = 2015
    elsif arg == '--es2016'
      options[:eslevel] = 2016
    elsif arg == '--es2017'
      options[:eslevel] = 2017
    elsif arg == '--es2018'
      options[:eslevel] = 2018
    elsif arg == '--es2019'
      options[:eslevel] = 2019
    elsif arg == '--es2020'
      options[:eslevel] = 2020
    elsif arg == '--es2021'
      options[:eslevel] = 2021
    elsif arg == '--es2022'
      options[:eslevel] = 2022
    elsif arg == '--identity'
      options[:comparison] = :identity
    elsif arg == '--equality'
      options[:comparison] = :equality
    elsif arg == '--underscored_private'
      options[:underscored_private] = true
    elsif arg == '--strict'
      options[:strict] = true
    elsif arg == '--nullish'
      options[:or] = :nullish
    elsif arg == '--verbose' || arg == '-v'
      verbose = true
    elsif arg == '--loc'
      show_loc = true
    elsif arg == '--find' || arg == '-f'
      i += 1
      search_pattern = args[i]
      output_mode = 'find'
    elsif arg.start_with?('--find=')
      search_pattern = arg.split('=')[1]
      output_mode = 'find'
    elsif arg == '--inspect'
      i += 1
      inspect_path = args[i] || 'root'
      output_mode = 'inspect'
    elsif arg.start_with?('--inspect=')
      inspect_path = arg.split('=')[1]
      output_mode = 'inspect'
    elsif arg == '--help' || arg == '-h'
      console.log(<<~HELP)
        Ruby2JS JavaScript CLI - uses selfhosted converter

        Usage:
          node ruby2js.mjs [options] [file]
          node ruby2js.mjs -e "puts 'hello'"
          echo "puts 'hello'" | node ruby2js.mjs [options]

        Output Modes:
          --js              Output JavaScript (default)
          --ast             Output AST (Parser-compatible s-expression format)
          --prism-ast       Output raw Prism AST (verbose object format)
          --find=PATTERN    Find nodes matching PATTERN (regex) in Prism AST
          --inspect=PATH    Inspect node at PATH (e.g., "root.statements.body[0]")

        Conversion Options:
          -e CODE           Evaluate inline Ruby code
          --eslevel=NNNN    Set ECMAScript level (default: 2020)
          --es2015 .. --es2022  Set ECMAScript level
          --identity        Use === for == comparisons
          --equality        Use == for == comparisons
          --underscored_private  Prefix private properties with underscore (@foo -> _foo)
          --strict          Add "use strict" to output
          --nullish         Use ?? for 'or' operator

        Debug Options:
          --verbose, -v     Show all AST properties including internal ones
          --loc             Show location information in AST output
          --help, -h        Show this help

        Examples:
          # Convert Ruby to JavaScript
          node ruby2js.mjs -e "puts 'hello'"
          echo "puts 'hello'" | node ruby2js.mjs

          # Use specific ES level
          node ruby2js.mjs --es2022 -e "class Foo; @x = 1; end"

          # View AST (s-expression format)
          node ruby2js.mjs --ast -e "self.p ||= 1"

          # View raw Prism AST
          node ruby2js.mjs --prism-ast -e "@a = 1"

          # Find nodes in Prism AST
          node ruby2js.mjs --find=Write -e "self.p ||= 1"
      HELP
      process.exit(0)
    elsif !arg.start_with?('-')
      file = arg
    end

    i += 1
  end

  # Read source
  source = nil
  if inline_code
    source = inline_code
  elsif file
    source = fs.readFileSync(file, 'utf-8')
    options[:file] = file
  elsif process.stdin.isTTY
    console.error('Error: No input. Provide a file, use -e CODE, or pipe Ruby code via stdin.')
    console.error('Use --help for usage information.')
    process.exit(1)
  else
    source = fs.readFileSync(0, 'utf-8')
  end

  begin
    # Parse with Prism
    parse_result = prism_parse(source)

    if parse_result.errors && parse_result.errors.length > 0
      console.error('Parse error:', parse_result.errors[0].message)
      process.exit(1)
    end

    walker = nil
    ast = nil

    case output_mode
    when 'prism-ast'
      console.log(format_prism_node(parse_result.value, '', { verbose: verbose, showLoc: show_loc }))

    when 'find'
      matches = find_prism_nodes(parse_result.value, search_pattern)
      if matches.length == 0
        console.log("No nodes matching \"#{search_pattern}\" found.")
      else
        console.log("Found #{matches.length} node(s) matching \"#{search_pattern}\":\n")
        matches.each do |match|
          console.log("--- #{match.path} (#{match.type}) ---")
          console.log(inspect_prism_node(match.node))
          console.log('')
        end
      end

    when 'inspect'
      # Navigate to the specified path
      node = parse_result.value
      parts = inspect_path.split(/\.|\[|\]/).filter { |p| p != '' }

      parts.shift if parts[0] == 'root'

      parts.each do |part|
        if node.nil? || node == undefined
          console.error("Path \"#{inspect_path}\" not found (stopped at null/undefined)")
          process.exit(1)
        end
        if /^\d+$/.test(part)
          node = node[parseInt(part, 10)]
        else
          node = node[part]
        end
      end

      console.log("Inspecting: #{inspect_path}\n")
      console.log(inspect_prism_node(node))

    when 'walker-ast'
      walker = Ruby2JS::PrismWalker.new(source, options[:file])
      ast = walker.visit(parse_result.value)
      console.log(format_ast(ast))

    else
      # Full conversion to JavaScript using the convert() function
      console.log(convert(source, options))
    end

  rescue => e
    console.error('Error:', e.message)
    console.error(e.stack) if process.env.DEBUG
    process.exit(1)
  end
end

# ============================================================================
# Main entry point guard
# ============================================================================

# Check if this module is being run directly (not imported)
# In Node.js, compare process.argv[1] with the module URL
# Only run in Node.js environment (where process exists)
if typeof(window) == 'undefined' && process.argv[1] == fileURLToPath(import.meta.url)
  run_cli()
end
