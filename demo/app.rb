#!/usr/bin/env ruby
#
# Sinatra-based demo for Ruby2JS
#
# Usage:
#   ruby demo/app.rb              # starts server on port 4567
#   ruby demo/app.rb -p 8080      # starts server on port 8080

require 'sinatra/base'
require 'json'

# Support running directly from a git clone
$:.unshift File.expand_path('../lib', __dir__)
require 'ruby2js'
require 'ruby2js/demo'

class Ruby2JSDemo < Sinatra::Base
  set :views, File.expand_path('views', __dir__)
  set :public_folder, File.expand_path('public', __dir__)

  # Use shared configuration from Ruby2JS::Demo
  configure do
    set :available_filters, Ruby2JS::Demo.available_filters
    set :available_eslevels, Ruby2JS::Demo.available_eslevels
    set :available_options, Ruby2JS::Demo.available_options
  end

  helpers do
    def ruby2js_logo
      <<~SVG
        <svg width="100%" height="100%" viewBox="0 0 278 239" xmlns="http://www.w3.org/2000/svg" style="fill-rule:evenodd;clip-rule:evenodd;stroke-linecap:round;stroke-linejoin:round;stroke-miterlimit:10;">
          <g transform="matrix(0.97805,-0.208368,0.208368,0.97805,-63.5964,16.8613)">
            <path d="M43.591,115.341L92.572,45.15L275.649,45.276L322,113.639L183.044,261.9L43.591,115.341Z" style="fill:#c92613;"/>
            <g transform="matrix(0.762386,0,0,0.762386,-83.8231,-163.857)">
              <g transform="matrix(1,0,0,1,1,0)">
                <path d="M253,412.902L323.007,416.982L335.779,302.024L433.521,467.281L346.795,556.198L253,412.902Z" style="fill:url(#_Linear1);"/>
              </g>
              <g transform="matrix(1,0,0,1,90,0)">
                <path d="M260.802,410.567L312.405,427.307L345.625,407.012L286.376,341.482L301.912,316.368L348.735,322.338L402.088,408.236L360.798,450.037L317.951,497.607L260.802,410.567Z" style="fill:url(#_Linear2);"/>
              </g>
            </g>
            <g transform="matrix(1,0,0,1,-71.912,-102.1)">
              <path d="M133.132,219.333L241.936,335.629L190.73,219.333L133.132,219.333ZM205.287,219.333L255.212,345.305L306.383,219.333L205.287,219.333ZM374.878,219.333L320.94,219.333L267.853,335.345L374.878,219.333ZM211.57,207.009L302.227,207.009L256.899,159.664L211.57,207.009ZM334.854,155.614L268.834,155.614L314.068,202.862L334.854,155.614ZM176.816,155.614L198.271,204.385L244.966,155.614L176.816,155.614ZM375.017,207.009L345.969,163.438L326.802,207.009L375.017,207.009ZM137.348,207.009L184.868,207.009L166.129,164.411L137.348,207.009ZM163.588,147L348.228,147L393.912,215.526L254.956,364L116,217.43L163.588,147Z" style="fill:none;stroke:#fff8c3;stroke-width:5px;"/>
            </g>
            <g transform="matrix(0.76326,0,0,0.76326,-88.595,-169.24)">
              <g opacity="0.44">
                <g transform="matrix(0.46717,0,0,0.46717,186.613,178.904)">
                  <path d="M165.65,526.474L213.863,497.296C223.164,513.788 231.625,527.74 251.92,527.74C271.374,527.74 283.639,520.13 283.639,490.53L283.639,289.23L342.842,289.23L342.842,491.368C342.842,552.688 306.899,580.599 254.457,580.599C207.096,580.599 179.605,556.07 165.65,526.469" style="fill:#300905;"/>
                </g>
                <g transform="matrix(0.46717,0,0,0.46717,185.613,178.904)">
                  <path d="M375,520.13L423.206,492.219C435.896,512.943 452.389,528.166 481.568,528.166C506.099,528.166 521.741,515.901 521.741,498.985C521.741,478.686 505.673,471.496 478.606,459.659L463.809,453.311C421.094,435.13 392.759,412.294 392.759,364.084C392.759,319.68 426.59,285.846 479.454,285.846C517.091,285.846 544.156,298.957 563.608,333.212L517.511,362.814C507.361,344.631 496.369,337.442 479.454,337.442C462.115,337.442 451.119,348.437 451.119,362.814C451.119,380.576 462.115,387.766 487.486,398.762L502.286,405.105C552.611,426.674 580.946,448.662 580.946,498.139C580.946,551.426 539.08,580.604 482.836,580.604C427.86,580.604 392.336,554.386 375,520.13" style="fill:#2f0905;"/>
                </g>
              </g>
            </g>
            <g transform="matrix(0.76326,0,0,0.76326,-91.6699,-173.159)">
              <g transform="matrix(0.46717,0,0,0.46717,186.613,178.904)">
                <path d="M165.65,526.474L213.863,497.296C223.164,513.788 231.625,527.74 251.92,527.74C271.374,527.74 283.639,520.13 283.639,490.53L283.639,289.23L342.842,289.23L342.842,491.368C342.842,552.688 306.899,580.599 254.457,580.599C207.096,580.599 179.605,556.07 165.65,526.469" style="fill:#f7df1e;"/>
              </g>
              <g transform="matrix(0.46717,0,0,0.46717,185.613,178.904)">
                <path d="M375,520.13L423.206,492.219C435.896,512.943 452.389,528.166 481.568,528.166C506.099,528.166 521.741,515.901 521.741,498.985C521.741,478.686 505.673,471.496 478.606,459.659L463.809,453.311C421.094,435.13 392.759,412.294 392.759,364.084C392.759,319.68 426.59,285.846 479.454,285.846C517.091,285.846 544.156,298.957 563.608,333.212L517.511,362.814C507.361,344.631 496.369,337.442 479.454,337.442C462.115,337.442 451.119,348.437 451.119,362.814C451.119,380.576 462.115,387.766 487.486,398.762L502.286,405.105C552.611,426.674 580.946,448.662 580.946,498.139C580.946,551.426 539.08,580.604 482.836,580.604C427.86,580.604 392.336,554.386 375,520.13" style="fill:#f7df1e;"/>
              </g>
            </g>
          </g>
          <defs>
            <linearGradient id="_Linear1" x1="0" y1="0" x2="1" y2="0" gradientUnits="userSpaceOnUse" gradientTransform="matrix(110.514,-65.1883,65.1883,110.514,284.818,460.929)">
              <stop offset="0" style="stop-color:#61120a;"/>
              <stop offset="1" style="stop-color:#b82212;"/>
            </linearGradient>
            <linearGradient id="_Linear2" x1="0" y1="0" x2="1" y2="0" gradientUnits="userSpaceOnUse" gradientTransform="matrix(102.484,-65.5763,65.5763,102.484,288.352,453.55)">
              <stop offset="0" style="stop-color:#61120a;"/>
              <stop offset="1" style="stop-color:#b82212;"/>
            </linearGradient>
          </defs>
        </svg>
      SVG
    end

    def walk_ast(ast, indent = '', tail = '', last = true)
      return '' unless ast

      loc_class = ast.loc ? 'loc' : 'unloc'
      html = "<div class=\"#{loc_class}\">"
      html << indent
      html << '<span class="hidden">s(:</span>'
      html << ast.type.to_s
      html << '<span class="hidden">,</span>' unless ast.children.empty?

      if ast.children.any? { |child| child.is_a?(Parser::AST::Node) }
        ast.children.each_with_index do |child, index|
          ctail = index == ast.children.length - 1 ? ')' + tail : ''
          if child.is_a?(Parser::AST::Node)
            html << walk_ast(child, "  #{indent}", ctail, last && !ctail.empty?)
          else
            html << "<div>#{indent}  #{child.inspect}"
            html << "<span class=\"hidden\">#{ctail}#{last && !ctail.empty? ? '' : ','}</span>"
            html << ' ' if last && !ctail.empty?
            html << '</div>'
          end
        end
      else
        ast.children.each_with_index do |child, index|
          html << " #{child.inspect}"
          html << '<span class="hidden">,</span>' unless index == ast.children.length - 1
        end
        html << "<span class=\"hidden\">)#{tail}#{last ? '' : ','}</span>"
        html << ' ' if last
      end

      html << '</div>'
      html
    end

    def parse_options(params, path_info)
      options = {}
      selected = path_info.to_s.split('/').reject(&:empty?)

      # Also check form params for filter checkboxes
      settings.available_filters.each do |filter|
        if params[filter] == 'on' || params[filter] == 'true'
          selected << filter unless selected.include?(filter)
        end
      end

      # Handle preset
      if params['preset'] == 'on' || params['preset'] == 'true' || params['preset'] == true
        options[:preset] = true
      end

      # Handle eslevel
      if params['eslevel'] && params['eslevel'] != 'default'
        options[:eslevel] = params['eslevel'].to_i
      end

      # Handle other options from query string or params
      settings.available_options.each do |opt, has_args|
        if params[opt]
          if has_args && params[opt].is_a?(String) && !params[opt].empty?
            options[opt.to_sym] = params[opt]
          else
            options[opt.to_sym] = true
          end
        end
      end

      # Handle comparison options
      options[:comparison] = :identity if options.delete(:identity)
      options[:or] = :nullish if options.delete(:nullish)

      # Load selected filters
      options[:filters] = Ruby2JS::Filter.require_filters(selected)

      [options, selected]
    end
  end

  # Main page
  get '/*' do
    @live = false
    @ruby = params[:ruby] || Ruby2JS::Demo.default_ruby
    @eslevel = params[:eslevel]
    @ast = params[:ast] == 'on' || params[:ast] == 'true'
    @preset = params.fetch('preset', true)
    @preset = @preset == 'on' || @preset == 'true' || @preset == true

    @filter_list = settings.available_filters
    @eslevel_list = settings.available_eslevels
    @option_list = settings.available_options

    options, @selected = parse_options(params, request.path_info)
    @options_checked = options.dup
    @options_checked[:identity] = options[:comparison] == :identity
    @options_checked[:nullish] = options[:or] == :nullish

    # Do initial conversion if we have Ruby code
    if @ruby && !@ruby.empty?
      begin
        options[:preset] = @preset if @preset
        @parsed = Ruby2JS.parse(@ruby).first if @ast
        converted = Ruby2JS.convert(@ruby, options)
        @js_output = converted.to_s
        @parsed_html = walk_ast(@parsed) if @parsed
        if @ast && @parsed && converted.ast != @parsed
          @filtered_html = walk_ast(converted.ast)
        end
      rescue => e
        @error = e.message
      end
    end

    erb :demo
  end

  # Handle form submission and JSON API
  post '/*' do
    # Check if this is a JSON API request (explicit JSON content-type or Accept header)
    is_json_request = request.content_type&.include?('application/json') ||
                      (request.accept&.first&.to_s == 'application/json')

    if is_json_request
      content_type :json

      body = JSON.parse(request.body.read) rescue {}
      ruby = body['ruby'] || params[:ruby]
      show_ast = body['ast'] || params[:ast]

      options, _ = parse_options(params.merge(body), request.path_info)

      begin
        result = { js: Ruby2JS.convert(ruby, options).to_s }

        if show_ast
          parsed = Ruby2JS.parse(ruby).first
          result[:parsed] = "<pre>#{walk_ast(parsed)}</pre>"

          converted = Ruby2JS.convert(ruby, options)
          if converted.ast != parsed
            result[:filtered] = "<pre>#{walk_ast(converted.ast)}</pre>"
          end
        end

        result.to_json
      rescue => e
        { exception: e.message }.to_json
      end
    else
      # Form submission - render HTML page with results
      @live = false
      @ruby = params[:ruby] || Ruby2JS::Demo.default_ruby
      @eslevel = params[:eslevel]
      @ast = params[:ast] == 'on' || params[:ast] == 'true'
      @preset = params.fetch('preset', false)
      @preset = @preset == 'on' || @preset == 'true' || @preset == true

      @filter_list = settings.available_filters
      @eslevel_list = settings.available_eslevels
      @option_list = settings.available_options

      options, @selected = parse_options(params, request.path_info)
      @options_checked = options.dup
      @options_checked[:identity] = options[:comparison] == :identity
      @options_checked[:nullish] = options[:or] == :nullish

      # Do conversion
      if @ruby && !@ruby.empty?
        begin
          options[:preset] = @preset if @preset
          @parsed = Ruby2JS.parse(@ruby).first if @ast
          converted = Ruby2JS.convert(@ruby, options)
          @js_output = converted.to_s
          @parsed_html = walk_ast(@parsed) if @parsed
          if @ast && @parsed && converted.ast != @parsed
            @filtered_html = walk_ast(converted.ast)
          end
        rescue => e
          @error = e.message
        end
      end

      erb :demo
    end
  end

  # Run the app if executed directly
  run! if app_file == $0
end
