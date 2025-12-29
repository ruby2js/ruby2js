#!/usr/bin/env ruby
#
# Interactive demo of conversions from Ruby to JS.
#
# Installation
# ----
#
#   Want to run a standalone server?
#     $ ruby ruby2js.rb --port=8080
#
#   Want to run from the command line?
#     $ ruby ruby2js.rb [options] [file]
#
#       try --help for a list of supported options
#
#   Subcommands for Rails-like apps:
#     $ ruby2js dev [options]     # Start development server
#     $ ruby2js server [options]  # Start production server
#     $ ruby2js build [options]   # Build for deployment

# support running directly from a git clone
$:.unshift File.absolute_path('../../lib', __FILE__)

# Check for subcommands before loading the full demo
SUBCOMMANDS = %w[dev server build install].freeze

if SUBCOMMANDS.include?(ARGV.first)
  subcommand = ARGV.shift
  require "ruby2js/cli/#{subcommand}"
  Ruby2JS::CLI.const_get(subcommand.capitalize).run(ARGV)
  exit
end

require 'ruby2js/demo'
require 'json'

# Parse command line arguments
@port = nil
@inline_code = nil
@output_ast = false
@output_filtered_ast = false
@filter_trace = false
@show_comments = false
@provide_sourcemap = false

options = {}
selected = []

require 'optparse'

opts = OptionParser.new
opts.banner = "Usage: #$0 [options] [file]"

opts.on('--preset', "use sane defaults (modern eslevel & common filters)") { options[:preset] = true }

opts.on('-C', '--config [FILE]', "configuration file to use (default is config/ruby2js.rb)") { |filename|
  options[:config_file] = filename
}

opts.on('--autoexports [default]', "add export statements for top level constants") { |option|
  options[:autoexports] = option ? option.to_sym : true
}

opts.on('--autoimports=mappings', "automatic import mappings, without quotes") { |mappings|
  options[:autoimports] = Ruby2JS::Demo.parse_autoimports(mappings)
}

opts.on('--defs=mappings', "class and module definitions") { |mappings|
  options[:defs] = Ruby2JS::Demo.parse_defs(mappings)
}

opts.on('--equality', "double equal comparison operators") { options[:comparison] = :equality }

# autoregister eslevels
Dir["#{$:.first}/ruby2js/es20*.rb"].sort.each do |file|
  eslevel = File.basename(file, '.rb')
  opts.on("--#{eslevel}", "ECMAScript level #{eslevel}") do
    options[:eslevel] = eslevel[/\d+/].to_i
  end
end

opts.on('--exclude METHOD,...', "exclude METHOD(s) from filters", Array) { |methods|
  options[:exclude] ||= []; options[:exclude].push(*methods.map(&:to_sym))
}

opts.on('-f', '--filter NAME,...', "process using NAME filter(s)", Array) do |names|
  selected.push(*names)
end

opts.on('--filepath [PATH]', "supply a path if stdin is related to a source file") do |filepath|
  options[:file] = filepath
end

opts.on('--identity', "triple equal comparison operators") { options[:comparison] = :identity }

opts.on('--import_from_skypack', "use Skypack for internal functions import statements") do
  options[:import_from_skypack] = true
end

opts.on('--include METHOD,...', "have filters process METHOD(s)", Array) { |methods|
  options[:include] ||= []; options[:include].push(*methods.map(&:to_sym))
}

opts.on('--include-all', "have filters include all methods") do
  options[:include_all] = true
end

opts.on('--include-only METHOD,...', "have filters only process METHOD(s)", Array) { |methods|
  options[:include_only] ||= []; options[:include_only].push(*methods.map(&:to_sym))
}

opts.on('--ivars @name:value,...', "set ivars") { |ivars|
  options[:ivars] ||= {}
  options[:ivars].merge! ivars.split(/(?:^|,)\s*(@\w+):/)[1..-1].each_slice(2).
    map { |name, value| [name.to_sym, value] }.to_h
}

opts.on('--logical', "use '||' for 'or' operators") { options[:or] = :logical }

opts.on('--nullish', "use '??' for 'or' operators") { options[:or] = :nullish }

opts.on('--nullish_to_s', "nil-safe string coercion (to_s, String(), interpolation)") { options[:nullish_to_s] = true }

opts.on('--truthy MODE', "truthy semantics: 'ruby' or 'js'") { |mode| options[:truthy] = mode.to_sym }

opts.on('--require_recursive', "import all symbols defined by processing the require recursively") { options[:require_recursive] = true }

opts.on('--strict', "strict mode") { options[:strict] = true }

opts.on('--template_literal_tags tag,...', "process TAGS as template literals", Array) { |tags|
  options[:template_literal_tags] ||= []; options[:template_literal_tags].push(*tags.map(&:to_sym))
}

opts.on('--underscored_private', "prefix private properties with an underscore") do
  options[:underscored_private] = true
end

opts.on("--sourcemap", "Provide a JSON object with the code and sourcemap") do
  @provide_sourcemap = true
end

opts.on("--ast", "Output the parsed AST instead of JavaScript") do
  @output_ast = true
end

opts.on("--filtered-ast", "Output the filtered AST instead of JavaScript") do
  @output_filtered_ast = true
end

opts.on("--show-comments", "Show the comments map after filtering") do
  @show_comments = true
end

opts.on("--filter-trace", "Show AST after each filter is applied") do
  @filter_trace = true
end

opts.on("-e CODE", "Evaluate inline Ruby code") do |code|
  @inline_code = code
end

opts.separator('')

opts.on('--port n', Integer, 'start a webserver') do |n|
  @port = n
end

opts.parse!

# Load selected filters
options[:filters] = Ruby2JS::Filter.require_filters(selected)

if @port
  # Web server mode - use Sinatra app
  require_relative 'app'
  Ruby2JSDemo.set :port, @port
  Ruby2JSDemo.run!
else
  # Command line mode

  # Helper to format AST as s-expression
  def format_ast(ast, indent = '')
    return 'nil' if ast.nil?
    return ast.inspect unless ast.respond_to?(:type)

    type = ast.type
    children = ast.children

    if children.empty?
      "s(:#{type})"
    elsif children.none? { |c| c.respond_to?(:type) }
      "s(:#{type}, #{children.map(&:inspect).join(', ')})"
    else
      lines = ["s(:#{type},"]
      children.each_with_index do |child, i|
        comma = i < children.length - 1 ? ',' : ''
        if child.respond_to?(:type)
          lines << format_ast(child, indent + '  ').lines.map.with_index { |line, j|
            j == 0 ? "#{indent}  #{line.chomp}#{comma}" : "#{indent}  #{line.chomp}"
          }.join("\n")
        else
          lines << "#{indent}  #{child.inspect}#{comma}"
        end
      end
      lines << "#{indent})"
      lines.join("\n")
    end
  end

  # Helper to format comments map for debugging
  def dump_comments_map(comments_hash)
    return "(no comments)" if comments_hash.nil? || comments_hash.empty?

    lines = []
    comments_hash.each do |node, comment_list|
      next if node == :_raw || comment_list.nil? || comment_list.empty?

      node_desc = if node.respond_to?(:type)
        loc_info = ""
        if node.loc && node.loc.respond_to?(:expression) && node.loc.expression
          loc = node.loc.expression
          loc_info = " @#{loc.begin_pos}-#{loc.end_pos}"
        end
        "s(:#{node.type}, ...)#{loc_info}"
      else
        node.inspect[0, 50]
      end

      comment_texts = comment_list.map { |c| c.respond_to?(:text) ? c.text : c.to_s }
      lines << "  #{node_desc}"
      comment_texts.each { |t| lines << "    => #{t.inspect}" }
    end

    lines.empty? ? "(all comments empty)" : lines.join("\n")
  end

  # Get source code
  if @inline_code
    source = @inline_code
  elsif ARGV.length > 0
    options[:file] = ARGV.first
    source = File.read(ARGV.first)
  else
    source = $stdin.read
  end

  if @output_ast
    ast, _comments = Ruby2JS.parse(source, options[:file])
    puts format_ast(ast)
  elsif @output_filtered_ast
    conv = Ruby2JS.convert(source, options)
    puts format_ast(conv.ast)
  elsif @filter_trace
    require 'ruby2js/filter'

    ast, comments = Ruby2JS.parse(source, options[:file])
    puts "=== Parsed AST ==="
    puts format_ast(ast)
    puts

    if options[:filters] && !options[:filters].empty?
      options[:filters].each do |filter|
        filter_name = filter.to_s.split('::').last

        single_filter_opts = options.merge(filters: [filter])
        conv = Ruby2JS.convert(source, single_filter_opts)

        puts "=== After #{filter_name} filter ==="
        puts format_ast(conv.ast)
        puts
      end
    end

    conv = Ruby2JS.convert(source, options)
    puts "=== JavaScript Output ==="
    puts conv.to_s
  elsif @show_comments
    conv = Ruby2JS.convert(source, options)

    puts "=== Comments Map ==="
    puts dump_comments_map(conv.comments_hash)
    puts
    puts "=== JavaScript Output ==="
    puts conv.to_s
  elsif @provide_sourcemap
    conv = Ruby2JS.convert(source, options)
    puts({ code: conv.to_s, sourcemap: conv.sourcemap }.to_json)
  else
    conv = Ruby2JS.convert(source, options)
    puts conv.to_s
  end
end
