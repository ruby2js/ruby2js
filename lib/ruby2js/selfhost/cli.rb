# Ruby2JS Self-hosted CLI
#
# This file provides command-line functionality for the bundled ruby2js.mjs.
# It is included in the bundle and only runs when the module is executed directly.
#
# Usage:
#   node ruby2js.mjs [options] [file]
#   echo "puts 'hello'" | node ruby2js.mjs [options]

import "*", as: :fs, from: 'fs'
import [fileURLToPath], from: 'url'

# ============================================================================
# AST Formatting and Inspection
# ============================================================================

# Format Prism AST node for display (verbose mode shows all properties)
def format_prism_node(node, indent = '', options = {})
  verbose = options[:verbose] || false
  show_loc = options[:showLoc] || false

  return "#{indent}null" if node.nil? || node == undefined
  return "#{indent}#{JSON.stringify(node)}" unless node.is_a?(Object)

  if Array.isArray(node)
    return "#{indent}[]" if node.length == 0
    items = node.map { |item| format_prism_node(item, indent + '  ', options) }
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

    formatted = format_prism_node(value, indent + '  ', options)
    if formatted.include?("\n")
      props.push("#{indent}  #{key}:\n#{formatted}")
    else
      props.push("#{indent}  #{key}: #{formatted.trim}")
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
  eslevel = 2020
  file = nil
  search_pattern = nil
  inspect_path = nil
  verbose = false
  show_loc = false

  i = 0
  while i < args.length
    arg = args[i]

    if arg == '--ast'
      output_mode = 'prism-ast'
    elsif arg == '--walker-ast'
      output_mode = 'walker-ast'
    elsif arg == '--js'
      output_mode = 'js'
    elsif arg.start_with?('--eslevel=')
      eslevel = parseInt(arg.split('=')[1], 10)
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
    elsif arg == '--inspect' || arg == '-i'
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
          echo "puts 'hello'" | node ruby2js.mjs [options]

        Output Modes:
          --js              Output JavaScript (default)
          --ast             Output raw Prism AST
          --walker-ast      Output AST after walker (Parser-compatible s-expression)
          --find=PATTERN    Find nodes matching PATTERN (regex) in Prism AST
          --inspect=PATH    Inspect node at PATH (e.g., "root.statements.body[0]")

        Options:
          --eslevel=NNNN    Set ECMAScript level (default: 2020)
          --verbose, -v     Show all properties including internal ones
          --loc             Show location information
          --help, -h        Show this help

        Examples:
          # Convert Ruby to JavaScript
          echo "puts 'hello'" | node ruby2js.mjs

          # View Prism AST
          echo "self.p ||= 1" | node ruby2js.mjs --ast

          # View walker output (s-expression)
          echo "self.p ||= 1" | node ruby2js.mjs --walker-ast

          # Find all nodes containing "Write" in type name
          echo "self.p ||= 1" | node ruby2js.mjs --find=Write

          # Inspect a specific node to see all its properties
          echo "self.p ||= 1" | node ruby2js.mjs --inspect=root.statements.body[0]

          # Verbose AST output (shows internal properties)
          echo "@a = 1" | node ruby2js.mjs --ast --verbose
      HELP
      process.exit(0)
    elsif !arg.start_with?('-')
      file = arg
    end

    i += 1
  end

  # Read source
  source = nil
  if file
    source = fs.readFileSync(file, 'utf-8')
  elsif process.stdin.isTTY
    console.error('Error: No input. Provide a file or pipe Ruby code via stdin.')
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
      walker = Ruby2JS::PrismWalker.new(source, file)
      ast = walker.visit(parse_result.value)
      console.log(format_ast(ast))

    else
      # Full conversion to JavaScript
      walker = Ruby2JS::PrismWalker.new(source, file)
      ast = walker.visit(parse_result.value)

      # Use walker's source buffer for comment association
      source_buffer = walker.source_buffer

      # Wrap and associate comments with AST nodes
      wrapped_comments = (parse_result.comments || []).map do |c|
        PrismComment.new(c, source, source_buffer)
      end
      comments = associateComments(ast, wrapped_comments)

      converter = Ruby2JS::Converter.new(ast, comments, {})
      converter.eslevel = eslevel
      converter.underscored_private = true
      converter.namespace = Ruby2JS::Namespace.new

      converter.convert
      console.log(converter.to_s!)
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
if process.argv[1] == fileURLToPath(import.meta.url)
  run_cli()
end
