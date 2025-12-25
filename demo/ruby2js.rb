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

# support running directly from a git clone
$:.unshift File.absolute_path('../../lib', __FILE__)
require 'ruby2js/demo'
require 'cgi'
require 'pathname'
require 'json'

def parse_request(env=ENV)
  # autoregister filters
  filters = Ruby2JS::Filter.autoregister($:.first)

  # web/CGI query string support
  selected = env['PATH_INFO'].to_s.split('/')
  env['QUERY_STRING'].to_s.split('&').each do |opt|
    key, value = opt.split('=', 2)
    if key == 'ruby'
      @ruby = CGI.unescape(value)
    elsif key == 'filter'
      selected = CGI.unescape(value).split(',')
    elsif value
      ARGV.push("--#{key}=#{CGI.unescape(value)}")
    else
      ARGV.push("--#{key}")
    end
  end

  # extract options from the argument list
  options = {}
  @live = ARGV.delete('--live')
  @port = nil

  require 'optparse'

  opts = OptionParser.new
  opts.banner = "Usage: #$0 [options] [file]"

  opts.on('--preset', "use sane defaults (modern eslevel & common filters)") {options[:preset] = true}

  unless env['QUERY_STRING']
    opts.on('-C', '--config [FILE]', "configuration file to use (default is config/ruby2js.rb)") {|filename|
      options[:config_file] = filename
    }
  end

  opts.on('--autoexports [default]', "add export statements for top level constants") {|option|
    options[:autoexports] = option ? option.to_sym : true
  }

  opts.on('--autoimports=mappings', "automatic import mappings, without quotes") {|mappings|
    options[:autoimports] = Ruby2JS::Demo.parse_autoimports(mappings)
  }

  opts.on('--defs=mappings', "class and module definitions") {|mappings|
    options[:defs] = Ruby2JS::Demo.parse_defs(mappings)
  }

  opts.on('--equality', "double equal comparison operators") {options[:comparison] = :equality}

  # autoregister eslevels
  Dir["#{$:.first}/ruby2js/es20*.rb"].sort.each do |file|
    eslevel = File.basename(file, '.rb')
    filters[eslevel] = file

    opts.on("--#{eslevel}", "ECMAScript level #{eslevel}") do
      @eslevel = eslevel[/\d+/]
      options[:eslevel] = @eslevel.to_i
    end
  end

  opts.on('--exclude METHOD,...', "exclude METHOD(s) from filters", Array) {|methods|
    options[:exclude] ||= []; options[:exclude].push(*methods.map(&:to_sym))
  }

  opts.on('-f', '--filter NAME,...', "process using NAME filter(s)", Array) do |names|
    selected.push(*names)
  end

  opts.on('--filepath [PATH]', "supply a path if stdin is related to a source file") do |filepath|
    options[:file] = filepath
  end

  opts.on('--identity', "triple equal comparison operators") {options[:comparison] = :identity}

  opts.on('--import_from_skypack', "use Skypack for internal functions import statements") do
    options[:import_from_skypack] = true
  end

  opts.on('--include METHOD,...', "have filters process METHOD(s)", Array) {|methods|
    options[:include] ||= []; options[:include].push(*methods.map(&:to_sym))
  }

  opts.on('--include-all', "have filters include all methods") do
    options[:include_all] = true
  end

  opts.on('--include-only METHOD,...', "have filters only process METHOD(s)", Array) {|methods|
    options[:include_only] ||= []; options[:include_only].push(*methods.map(&:to_sym))
  }

  opts.on('--ivars @name:value,...', "set ivars") {|ivars|
    options[:ivars] ||= {}
    options[:ivars].merge! ivars.split(/(?:^|,)\s*(@\w+):/)[1..-1].each_slice(2).
      map {|name, value| [name.to_sym, value]}.to_h
  }

  opts.on('--logical', "use '||' for 'or' operators") {options[:or] = :logical}

  opts.on('--nullish', "use '??' for 'or' operators") {options[:or] = :nullish}

  opts.on('--nullish_to_s', "nil-safe string coercion (to_s, String(), interpolation)") {options[:nullish_to_s] = true}

  opts.on('--truthy MODE', "truthy semantics: 'ruby' or 'js'") {|mode| options[:truthy] = mode.to_sym}

  opts.on('--require_recursive', "import all symbols defined by processing the require recursively") {options[:require_recursive] = true}

  opts.on('--strict', "strict mode") {options[:strict] = true}

  opts.on('--template_literal_tags tag,...', "process TAGS as template literals", Array) {|tags|
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

  # shameless hack.  Instead of repeating the available options, extract them
  # from the OptionParser.  Exclude default options and es20xx options.
  options_available = opts.instance_variable_get(:@stack).last.list.
    select {|opt| opt.long.first}.  # only options with long form
    map {|opt| [opt.long.first[2..-1], opt.arg != nil]}.
    reject {|name, arg| %w{equality logical}.include?(name) || name =~ /es20\d\d/}.to_h

  opts.separator('')

  opts.on('--port n', Integer, 'start a webserver') do |n|
    @port = n
  end

  begin
    opts.parse!
  rescue Exception => $load_error
    raise unless defined? env and env['SERVER_PORT']
  end

  # load selected filters
  options[:filters] = Ruby2JS::Filter.require_filters(selected)

  return options, selected, options_available
end

options = parse_request.first

if not @port and not @live
  # Helper to format AST as s-expression
  def format_ast(ast, indent = '')
    return 'nil' if ast.nil?
    return ast.inspect unless ast.respond_to?(:type)

    type = ast.type
    children = ast.children

    if children.empty?
      "s(:#{type})"
    elsif children.none? { |c| c.respond_to?(:type) }
      # All children are primitives - single line
      "s(:#{type}, #{children.map(&:inspect).join(', ')})"
    else
      # Has nested nodes - multi-line
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

  # command line support
  if @inline_code
    source = @inline_code
  elsif ARGV.length > 0
    options[:file] = ARGV.first
    source = File.read(ARGV.first)
  else
    source = $stdin.read
  end

  # Helper to format comments map for debugging
  def dump_comments_map(comments_hash)
    return "(no comments)" if comments_hash.nil? || comments_hash.empty?

    lines = []
    comments_hash.each do |node, comment_list|
      next if node == :_raw || comment_list.nil? || comment_list.empty?

      # Format the node
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

      # Format comments
      comment_texts = comment_list.map { |c| c.respond_to?(:text) ? c.text : c.to_s }
      lines << "  #{node_desc}"
      comment_texts.each { |t| lines << "    => #{t.inspect}" }
    end

    lines.empty? ? "(all comments empty)" : lines.join("\n")
  end

  if @output_ast
    # Output raw parsed AST
    ast, _comments = Ruby2JS.parse(source, options[:file])
    puts format_ast(ast)
  elsif @output_filtered_ast
    # Output AST after filters applied
    conv = Ruby2JS.convert(source, options)
    puts format_ast(conv.ast)
  elsif @filter_trace
    # Show AST after each filter
    require 'ruby2js/filter'

    ast, comments = Ruby2JS.parse(source, options[:file])
    puts "=== Parsed AST ==="
    puts format_ast(ast)
    puts

    # Apply filters one at a time
    if options[:filters] && !options[:filters].empty?
      options[:filters].each do |filter|
        filter_name = filter.to_s.split('::').last

        # Create a converter with just this filter
        single_filter_opts = options.merge(filters: [filter])
        conv = Ruby2JS.convert(source, single_filter_opts)

        puts "=== After #{filter_name} filter ==="
        puts format_ast(conv.ast)
        puts
      end
    end

    # Final output
    conv = Ruby2JS.convert(source, options)
    puts "=== JavaScript Output ==="
    puts conv.to_s
  elsif @show_comments
    # Show comments map after filtering
    conv = Ruby2JS.convert(source, options)

    puts "=== Comments Map ==="
    puts dump_comments_map(conv.comments_hash)
    puts
    puts "=== JavaScript Output ==="
    puts conv.to_s
  elsif @provide_sourcemap
    conv = Ruby2JS.convert(source, options)
    puts(
      {
        code: conv.to_s,
        sourcemap: conv.sourcemap,
      }.to_json
    )
  else
    conv = Ruby2JS.convert(source, options)
    puts conv.to_s
  end  

else
  # Web server mode using Rack
  require 'rack'
  require 'rackup/handler/webrick'

  # Helper to generate AST HTML
  def walk_ast(ast, indent='', tail='', last=true)
    return '' unless ast

    loc_class = ast.loc ? 'loc' : 'unloc'
    html = %(<div class="#{loc_class}">)
    html << CGI.escapeHTML(indent)
    html << '<span class="hidden">s(:</span>'
    html << CGI.escapeHTML(ast.type.to_s)
    html << '<span class="hidden">,</span>' unless ast.children.empty?

    if ast.children.any? { |child| Parser::AST::Node === child }
      ast.children.each_with_index do |child, index|
        ctail = index == ast.children.length - 1 ? ')' + tail : ''
        if Parser::AST::Node === child
          html << walk_ast(child, "  #{indent}", ctail, last && !ctail.empty?)
        else
          html << '<div>'
          html << CGI.escapeHTML("#{indent}  #{child.inspect}")
          html << %(<span class="hidden">#{CGI.escapeHTML(ctail)}#{',' unless last && !ctail.empty?}</span>)
          html << ' ' if last && !ctail.empty?
          html << '</div>'
        end
      end
    else
      ast.children.each_with_index do |child, index|
        html << ' ' << CGI.escapeHTML(child.inspect)
        html << '<span class="hidden">,</span>' unless index == ast.children.length - 1
      end
      html << %(<span class="hidden">)#{CGI.escapeHTML(tail)}#{',' unless last}</span>)
      html << ' ' if last
    end
    html << '</div>'
    html
  end

  RUBY2JS_LOGO = <<~'SVG'
    <svg width="100%" height="100%" viewBox="0 0 278 239" version="1.1" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:serif="http://www.serif.com/" style="fill-rule:evenodd;clip-rule:evenodd;stroke-linecap:round;stroke-linejoin:round;stroke-miterlimit:10;">
      <g transform="matrix(0.97805,-0.208368,0.208368,0.97805,-63.5964,16.8613)">
        <path d="M43.591,115.341L92.572,45.15L275.649,45.276L322,113.639L183.044,261.9L43.591,115.341Z" style="fill:rgb(201,38,19);"/>
        <g id="Layer1" transform="matrix(0.762386,0,0,0.762386,-83.8231,-163.857)">
          <g transform="matrix(1,0,0,1,1,0)">
            <path d="M253,412.902L323.007,416.982L335.779,302.024L433.521,467.281L346.795,556.198L253,412.902Z" style="fill:url(#_Linear1);"/>
          </g>
          <g transform="matrix(1,0,0,1,90,0)">
            <path d="M260.802,410.567L312.405,427.307L345.625,407.012L286.376,341.482L301.912,316.368L348.735,322.338L402.088,408.236L360.798,450.037L317.951,497.607L260.802,410.567Z" style="fill:url(#_Linear2);"/>
          </g>
        </g>
        <g transform="matrix(1,0,0,1,-71.912,-102.1)">
          <path d="M133.132,219.333L241.936,335.629L190.73,219.333L133.132,219.333ZM205.287,219.333L255.212,345.305L306.383,219.333L205.287,219.333ZM374.878,219.333L320.94,219.333L267.853,335.345L374.878,219.333ZM211.57,207.009L302.227,207.009L256.899,159.664L211.57,207.009ZM334.854,155.614L268.834,155.614L314.068,202.862L334.854,155.614ZM176.816,155.614L198.271,204.385L244.966,155.614L176.816,155.614ZM375.017,207.009L345.969,163.438L326.802,207.009L375.017,207.009ZM137.348,207.009L184.868,207.009L166.129,164.411L137.348,207.009ZM163.588,147L348.228,147L393.912,215.526L254.956,364L116,217.43L163.588,147Z" style="fill:none;fill-rule:nonzero;stroke:rgb(255,248,195);stroke-width:5px;"/>
        </g>
        <g transform="matrix(0.76326,0,0,0.76326,-88.595,-169.24)">
          <g opacity="0.44">
            <g id="j" transform="matrix(0.46717,0,0,0.46717,186.613,178.904)">
              <path d="M165.65,526.474L213.863,497.296C223.164,513.788 231.625,527.74 251.92,527.74C271.374,527.74 283.639,520.13 283.639,490.53L283.639,289.23L342.842,289.23L342.842,491.368C342.842,552.688 306.899,580.599 254.457,580.599C207.096,580.599 179.605,556.07 165.65,526.469" style="fill:rgb(48,9,5);fill-rule:nonzero;"/>
            </g>
            <g id="s" transform="matrix(0.46717,0,0,0.46717,185.613,178.904)">
              <path d="M375,520.13L423.206,492.219C435.896,512.943 452.389,528.166 481.568,528.166C506.099,528.166 521.741,515.901 521.741,498.985C521.741,478.686 505.673,471.496 478.606,459.659L463.809,453.311C421.094,435.13 392.759,412.294 392.759,364.084C392.759,319.68 426.59,285.846 479.454,285.846C517.091,285.846 544.156,298.957 563.608,333.212L517.511,362.814C507.361,344.631 496.369,337.442 479.454,337.442C462.115,337.442 451.119,348.437 451.119,362.814C451.119,380.576 462.115,387.766 487.486,398.762L502.286,405.105C552.611,426.674 580.946,448.662 580.946,498.139C580.946,551.426 539.08,580.604 482.836,580.604C427.86,580.604 392.336,554.386 375,520.13" style="fill:rgb(47,9,5);fill-rule:nonzero;"/>
            </g>
          </g>
        </g>
        <g transform="matrix(0.76326,0,0,0.76326,-91.6699,-173.159)">
          <g id="j1" serif:id="j" transform="matrix(0.46717,0,0,0.46717,186.613,178.904)">
            <path d="M165.65,526.474L213.863,497.296C223.164,513.788 231.625,527.74 251.92,527.74C271.374,527.74 283.639,520.13 283.639,490.53L283.639,289.23L342.842,289.23L342.842,491.368C342.842,552.688 306.899,580.599 254.457,580.599C207.096,580.599 179.605,556.07 165.65,526.469" style="fill:rgb(247,223,30);fill-rule:nonzero;"/>
          </g>
          <g id="s1" serif:id="s" transform="matrix(0.46717,0,0,0.46717,185.613,178.904)">
            <path d="M375,520.13L423.206,492.219C435.896,512.943 452.389,528.166 481.568,528.166C506.099,528.166 521.741,515.901 521.741,498.985C521.741,478.686 505.673,471.496 478.606,459.659L463.809,453.311C421.094,435.13 392.759,412.294 392.759,364.084C392.759,319.68 426.59,285.846 479.454,285.846C517.091,285.846 544.156,298.957 563.608,333.212L517.511,362.814C507.361,344.631 496.369,337.442 479.454,337.442C462.115,337.442 451.119,348.437 451.119,362.814C451.119,380.576 462.115,387.766 487.486,398.762L502.286,405.105C552.611,426.674 580.946,448.662 580.946,498.139C580.946,551.426 539.08,580.604 482.836,580.604C427.86,580.604 392.336,554.386 375,520.13" style="fill:rgb(247,223,30);fill-rule:nonzero;"/>
          </g>
        </g>
      </g>
      <defs>
        <linearGradient id="_Linear1" x1="0" y1="0" x2="1" y2="0" gradientUnits="userSpaceOnUse" gradientTransform="matrix(110.514,-65.1883,65.1883,110.514,284.818,460.929)">
          <stop offset="0" style="stop-color:rgb(97,18,10);stop-opacity:1"/>
          <stop offset="1" style="stop-color:rgb(184,34,18);stop-opacity:1"/>
        </linearGradient>
        <linearGradient id="_Linear2" x1="0" y1="0" x2="1" y2="0" gradientUnits="userSpaceOnUse" gradientTransform="matrix(102.484,-65.5763,65.5763,102.484,288.352,453.55)">
          <stop offset="0" style="stop-color:rgb(97,18,10);stop-opacity:1"/>
          <stop offset="1" style="stop-color:rgb(184,34,18);stop-opacity:1"/>
        </linearGradient>
      </defs>
    </svg>
  SVG

  CSS = <<~'CSS'
    :root {
      --primary: #242341;
      --primary-dark: #1a1a30;
      --red: #c92514;
      --red-dark: #460f0e;
      --yellow: #ffd725;
      --grey: #888;
      --grey-light: #c9c8b8;
      --grey-lighter: #e6e1d7;
      --white-ter: #f6f6f6;
      --ruby-bg: #ffeeee;
      --ruby-active: #ffdddd;
      --js-bg: #ffffcc;
      --js-active: #ffffdd;
      --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen-Sans, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
      --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    }

    * { box-sizing: border-box; }

    html { font-size: 18px; }

    body {
      margin: 0;
      font-family: var(--font-sans);
      font-size: 1rem;
      font-weight: 400;
      line-height: 1.5;
      color: #212529;
      background-color: var(--white-ter);
    }

    /* Header */
    .header {
      background-color: var(--primary);
      padding: 1rem 2rem;
      display: flex;
      align-items: center;
      gap: 1rem;
    }

    .header a {
      color: white;
      text-decoration: none;
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 1.5rem;
      font-weight: 700;
    }

    .header svg {
      height: 3rem;
      width: 3rem;
    }

    /* Main container */
    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 1.5rem 2rem;
    }

    /* Section titles */
    h1, h2 {
      color: var(--primary);
      font-weight: 700;
      margin: 0 0 1rem 0;
    }

    h1 { font-size: 1.5rem; }
    h2 { font-size: 1.25rem; margin-top: 1.5rem; }

    /* Ruby textarea */
    textarea.ruby {
      width: 100%;
      height: 12rem;
      padding: 0.75rem;
      font-family: var(--font-mono);
      font-size: 0.9rem;
      background-color: var(--ruby-bg);
      border: 1px solid var(--grey-light);
      border-radius: 4px;
      resize: vertical;
    }

    textarea.ruby:focus {
      outline: none;
      border-color: var(--red);
      box-shadow: 0 0 0 3px rgba(201, 37, 20, 0.15);
    }

    /* Options bar */
    .options {
      display: flex;
      gap: 1rem;
      align-items: center;
      flex-wrap: wrap;
      margin: 1rem 0;
      padding: 1rem;
      background: white;
      border-radius: 4px;
      box-shadow: 0 2px 3px rgba(62, 62, 62, 0.1), 0 0 0 1px rgba(62, 62, 62, 0.1);
    }

    /* Buttons */
    .btn {
      display: inline-flex;
      align-items: center;
      padding: 0.5rem 1rem;
      font-size: 0.9rem;
      font-weight: 500;
      border-radius: 4px;
      border: 1px solid transparent;
      cursor: pointer;
      transition: all 0.15s ease;
    }

    .btn-primary {
      color: white;
      background-color: var(--red);
      border-color: var(--red);
    }

    .btn-primary:hover {
      background-color: var(--red-dark);
      border-color: var(--red-dark);
    }

    .btn-secondary {
      color: var(--primary);
      background-color: white;
      border-color: var(--grey-light);
    }

    .btn-secondary:hover {
      background-color: var(--grey-lighter);
    }

    /* Checkboxes */
    .checkbox-label {
      display: inline-flex;
      align-items: center;
      gap: 0.35rem;
      cursor: pointer;
      font-size: 0.9rem;
    }

    .checkbox-label input[type="checkbox"] {
      width: 1rem;
      height: 1rem;
      accent-color: var(--red);
    }

    /* Select */
    select {
      padding: 0.4rem 0.6rem;
      font-size: 0.9rem;
      border: 1px solid var(--grey-light);
      border-radius: 4px;
      background: white;
      cursor: pointer;
    }

    select:focus {
      outline: none;
      border-color: var(--red);
    }

    /* Dropdown */
    .dropdown {
      position: relative;
      display: none;
    }

    .dropdown-content {
      display: none;
      position: absolute;
      top: 100%;
      left: 0;
      background: white;
      min-width: 200px;
      max-height: 300px;
      overflow-y: auto;
      border-radius: 4px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
      padding: 0.5rem;
      z-index: 100;
    }

    .dropdown-content div {
      padding: 0.4rem 0.6rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 0.85rem;
    }

    .dropdown-content div:hover {
      background-color: var(--white-ter);
      border-radius: 3px;
    }

    /* Output sections */
    .output-section {
      background: white;
      border-radius: 4px;
      padding: 1rem;
      margin-top: 1rem;
      box-shadow: 0 2px 3px rgba(62, 62, 62, 0.1), 0 0 0 1px rgba(62, 62, 62, 0.1);
    }

    .output-section h2 {
      margin-top: 0;
      padding-bottom: 0.5rem;
      border-bottom: 1px solid var(--grey-lighter);
    }

    pre {
      margin: 0;
      padding: 1rem;
      font-family: var(--font-mono);
      font-size: 0.85rem;
      line-height: 1.5;
      overflow-x: auto;
      border-radius: 4px;
    }

    pre.js {
      background-color: var(--js-bg);
    }

    /* AST output */
    #parsed pre, #filtered pre {
      background-color: white;
      border: 1px solid var(--grey-lighter);
    }

    .unloc { background-color: #fff3cd; }
    .loc { background-color: white; }
    .loc span.hidden, .unloc span.hidden { font-size: 0; }

    /* Exception */
    .exception {
      background-color: #fff3cd;
      margin: 1rem 0;
      padding: 1rem;
      border: 2px solid var(--red);
      border-radius: 4px;
      color: var(--red-dark);
    }

    /* Footer link */
    .footer-link {
      text-align: center;
      margin-top: 2rem;
      padding: 1rem;
      background: white;
      border-radius: 4px;
    }

    .footer-link a {
      color: var(--red-dark);
      text-decoration: none;
      font-weight: 500;
    }

    .footer-link a:hover {
      text-decoration: underline;
    }
  CSS

  DEMO_JS = <<~'JS'
    // determine base URL and what filters and options are selected
    let base = new URL(document.getElementsByTagName('base')[0].href).pathname;
    let filters = new Set(window.location.pathname.slice(base.length).split('/'));
    filters.delete('');
    let options = {};
    for (let match of window.location.search.matchAll(/(\w+)(=([^&]*))?/g)) {
      options[match[1]] = match[3] && decodeURIComponent(match[3]);
    };
    if (options.filter) options.filter.split(',').forEach(option => filters.add(option));

    function updateLocation(force = false) {
      let location = new URL(base, window.location);
      location.pathname += Array.from(filters).join('/');

      let search = [];
      for (let [key, value] of Object.entries(options)) {
        search.push(value === undefined ? key : `${key}=${encodeURIComponent(value)}`);
      };

      location.search = search.length === 0 ? "" : `${search.join('&')}`;
      if (!force && window.location.toString() == location.toString()) return;

      history.replaceState({}, null, location.toString());

      if (document.getElementById('js').style.display === 'none') return;

      // fetch updated results
      let ruby = document.querySelector('textarea[name=ruby]').textContent;
      let ast = document.getElementById('ast').checked;
      let headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }

      fetch(location,
        {method: 'POST', headers, body: JSON.stringify({ ruby, ast })}
      ).then(response => {
        return response.json();
      }).
      then(json => {
        document.querySelector('#js pre').textContent = json.js || json.exception;

        let parsed = document.querySelector('#parsed');
        if (json.parsed) parsed.querySelector('pre').outerHTML = json.parsed;
        parsed.style.display = json.parsed ? "block" : "none";

        let filtered = document.querySelector('#filtered');
        if (json.filtered) filtered.querySelector('pre').outerHTML = json.filtered;
        filtered.style.display = json.filtered ? "block" : "none";
      }).
      catch(console.error);
    }

    // show dropdowns (they only appear if JS is enabled)
    let dropdowns = document.querySelectorAll('.dropdown');
    for (let dropdown of dropdowns) {
      dropdown.style.display = 'inline-block';
      let content = dropdown.querySelector('.dropdown-content');
      content.style.opacity = 0;
      content.style.display = 'none';

      // toggle dropdown
      dropdown.querySelector('button').addEventListener('click', event => {
        event.preventDefault();
        content.style.transition = '0s';
        content.style.display = 'block';
        content.style.zIndex = 1;
        content.style.opacity = 1 - content.style.opacity;
      });

      // make dropdown disappear when mouse moves away
      let focus = false;
      dropdown.addEventListener('mouseover', () => {focus = true});
      dropdown.addEventListener('mouseout', event => {
        if (content.style.opacity === 0) return;
        focus = false;
        setTimeout( () => {
          if (!focus) {
            content.style.transition = '0.5s';
            content.style.opacity = 0;
            setTimeout( () => { content.style.zIndex = -1; }, 500);
          }
        }, 500)
      })
    };

    // add/remove eslevel options
    document.getElementById('eslevel').addEventListener('change', event => {
      let value = event.target.value;
      if (value !== "default") options['es' + value] = undefined;
      for (let option of event.target.querySelectorAll('option')) {
        if (option.value === 'default' || option.value === value) continue;
        delete options['es' + option.value];
      };
      updateLocation();
    });

    // add/remove filters based on checkbox
    let dropdown = document.getElementById('filters');
    for (let filter of dropdown.querySelectorAll('input[type=checkbox]')) {
      filter.addEventListener('click', event => {
        let name = event.target.name;
        if (!filters.delete(name)) filters.add(name);
        updateLocation();
      });
    }

    // add/remove options based on checkbox
    dropdown = document.getElementById('options');
    for (let option of dropdown.querySelectorAll('input[type=checkbox]')) {
      option.addEventListener('click', event => {
        let name = event.target.name;

        if (name in options) {
          delete options[name];
        } else if (option.dataset.args) {
          options[name] = prompt(name);
        } else {
          options[name] = undefined;
        };

        updateLocation();
      })
    };

    // allow update of option
    for (let span of document.querySelectorAll('input[data-args] + span')) {
      span.addEventListener('click', event => {
        let name = span.previousElementSibling.name;
        options[name] = prompt(name, decodeURIComponent(options[name] || ''));
        span.previousElementSibling.checked = true;
        updateLocation();
      })
    }

    // refresh on "Show AST" change
    document.getElementById('ast').addEventListener('click', updateLocation);
  JS

  def render_page(env)
    options, selected, options_available = parse_request(env)

    base = env['REQUEST_URI'].to_s.split('?').first
    base = base[0..-env['PATH_INFO'].length] if env['PATH_INFO'] && !env['PATH_INFO'].empty?
    base += '/' unless base.end_with?('/')

    ruby_code = @ruby || 'puts "Hello world!"'

    # Build eslevel options
    eslevel_options = '<option selected>default</option>'
    Dir["#{$:.first}/ruby2js/es20*.rb"].sort.each do |file|
      eslevel = File.basename(file, '.rb').sub('es', '')
      sel = @eslevel == eslevel ? ' selected' : ''
      eslevel_options << %(<option value="#{eslevel}"#{sel}>#{eslevel}</option>)
    end

    # Build filter checkboxes
    filter_items = ''
    Dir["#{$:.first}/ruby2js/filter/*.rb"].sort.each do |file|
      filter = File.basename(file, '.rb')
      next if filter == 'require'
      checked = selected.include?(filter) ? ' checked' : ''
      filter_items << %(<div><input type="checkbox" name="#{filter}"#{checked}><span>#{filter}</span></div>)
    end

    # Build option checkboxes
    option_items = ''
    checked_opts = options.dup
    checked_opts[:identity] = options[:comparison] == :identity
    checked_opts[:nullish] = options[:or] == :nullish
    options_available.each do |option, has_args|
      next if %w[preset filter].include?(option) || option.start_with?('require_')
      show_args = option == 'truthy' ? false : has_args
      checked = checked_opts[option.to_sym] ? ' checked' : ''
      data_args = show_args ? ' data-args="true"' : ''
      option_items << %(<div><input type="checkbox" name="#{option}"#{checked}#{data_args}><span>#{option}</span></div>)
    end

    # Build output sections
    parsed_html = ''
    filtered_html = ''
    js_output = ''
    js_display = 'none'

    if @ruby
      begin
        parsed_ast = Ruby2JS.parse(@ruby).first if @ast
        converted = Ruby2JS.convert(@ruby, options)
        js_output = CGI.escapeHTML(converted.to_s)
        js_display = 'block'

        if @ast && parsed_ast
          parsed_html = %(<div id="parsed" class="output-section" style="display: block"><h2>AST</h2><pre>#{walk_ast(parsed_ast)}</pre></div>)
          if converted.ast != parsed_ast
            filtered_html = %(<div id="filtered" class="output-section" style="display: block"><h2>Filtered AST</h2><pre>#{walk_ast(converted.ast)}</pre></div>)
          else
            filtered_html = '<div id="filtered" class="output-section" style="display: none"><h2>Filtered AST</h2><pre></pre></div>'
          end
        else
          parsed_html = '<div id="parsed" class="output-section" style="display: none"><h2>AST</h2><pre></pre></div>'
          filtered_html = '<div id="filtered" class="output-section" style="display: none"><h2>Filtered AST</h2><pre></pre></div>'
        end
      rescue => e
        js_output = CGI.escapeHTML("Error: #{e.message}")
        js_display = 'block'
        parsed_html = '<div id="parsed" class="output-section" style="display: none"><h2>AST</h2><pre></pre></div>'
        filtered_html = '<div id="filtered" class="output-section" style="display: none"><h2>Filtered AST</h2><pre></pre></div>'
      end
    else
      parsed_html = '<div id="parsed" class="output-section" style="display: none"><h2>AST</h2><pre></pre></div>'
      filtered_html = '<div id="filtered" class="output-section" style="display: none"><h2>Filtered AST</h2><pre></pre></div>'
    end

    preset_checked = (options[:preset] != false) ? ' checked' : ''
    ast_checked = @ast ? ' checked' : ''

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>Ruby2JS Demo</title>
        <base href="#{CGI.escapeHTML(base)}">
        <style>#{CSS}</style>
      </head>
      <body>
        <header class="header">
          <a href="https://www.ruby2js.com/docs/">
            #{RUBY2JS_LOGO}
            <span>Ruby2JS</span>
          </a>
        </header>

        <div class="container">
          <h1>Ruby</h1>

          <form method="post">
            <textarea class="ruby" name="ruby" placeholder="Enter Ruby code here...">#{CGI.escapeHTML(ruby_code)}</textarea>

            <div class="options">
              <input class="btn btn-primary" type="submit" value="Convert">

              <label class="checkbox-label">
                <input type="checkbox" id="preset" name="preset"#{preset_checked}>
                Use Preset
              </label>

              <label for="eslevel">ESLevel:</label>
              <select name="eslevel" id="eslevel">
                #{eslevel_options}
              </select>

              <label class="checkbox-label">
                <input type="checkbox" id="ast" name="ast"#{ast_checked}>
                Show AST
              </label>

              <div class="dropdown" id="filters">
                <button class="btn btn-secondary" type="button">Filters ▾</button>
                <div class="dropdown-content">
                  #{filter_items}
                </div>
              </div>

              <div class="dropdown" id="options">
                <button class="btn btn-secondary" type="button">Options ▾</button>
                <div class="dropdown-content">
                  #{option_items}
                </div>
              </div>
            </div>
          </form>

          <script>#{DEMO_JS}</script>

          #{parsed_html}
          #{filtered_html}

          <div id="js" class="output-section" style="display: #{js_display}">
            <h2>JavaScript</h2>
            <pre class="js">#{js_output}</pre>
          </div>

          <div class="footer-link">
            <a href="https://www.ruby2js.com/docs/">View Documentation →</a>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

  def handle_json(env)
    options = parse_request(env).first

    response = {}
    begin
      converted = Ruby2JS.convert(@ruby, options)
      response[:js] = converted.to_s

      if @ast
        parsed = Ruby2JS.parse(@ruby).first
        response[:parsed] = "<pre>#{walk_ast(parsed)}</pre>"

        if converted.ast != parsed
          response[:filtered] = "<pre>#{walk_ast(converted.ast)}</pre>"
        end
      end
    rescue => e
      response[:exception] = e.message
    end

    response.to_json
  end

  app = proc do |env|
    # Parse query string and form data
    request = Rack::Request.new(env)

    # Reset instance variables for each request
    @ruby = nil
    @ast = nil
    @eslevel = nil

    # Handle form POST
    if request.post?
      if request.content_type&.include?('application/json')
        body = JSON.parse(request.body.read) rescue {}
        @ruby = body['ruby']
        @ast = body['ast']
      else
        @ruby = request.params['ruby']
        @ast = request.params['ast']
      end
    end

    # Parse query params
    request.params.each do |key, value|
      case key
      when 'ruby' then @ruby ||= value
      when 'ast' then @ast ||= value
      when 'eslevel' then @eslevel = value
      end
    end

    # JSON API request
    if request.post? && request.content_type&.include?('application/json')
      [200, {'Content-Type' => 'application/json; charset=utf-8'}, [handle_json(env)]]
    else
      [200, {'Content-Type' => 'text/html; charset=utf-8'}, [render_page(env)]]
    end
  end

  # Start the server
  puts "Starting Ruby2JS demo server on http://localhost:#{@port}/"

  # Open browser in background
  Thread.new do
    sleep 1
    link = "http://localhost:#{@port}/"
    if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      system "start #{link}"
    elsif RbConfig::CONFIG['host_os'] =~ /darwin/
      system "open #{link}"
    elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
      if ENV['WSLENV'] && !`which wslview 2>/dev/null`.empty?
        system "wslview #{link}"
      else
        system "xdg-open #{link}"
      end
    end
  end

  Rackup::Handler::WEBrick.run(app, Port: @port, Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO))
end
