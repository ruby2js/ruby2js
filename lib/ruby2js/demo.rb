# helper methods shared between MRI CGI/server and Opal implementations
require 'ruby2js'

module Ruby2JS
  module Demo
    # Shared configuration for demo UI (Sinatra standalone and Bridgetown docs)
    def self.available_filters
      @available_filters ||= Dir[File.join(File.dirname(__FILE__), 'filter/*.rb')].map { |f|
        File.basename(f, '.rb')
      }.reject { |f| f == 'require' }.sort
    end

    def self.available_eslevels
      @available_eslevels ||= Dir[File.join(File.dirname(__FILE__), 'es20*.rb')].map { |f|
        File.basename(f, '.rb').sub('es', '')
      }.sort
    end

    def self.available_options
      @available_options ||= {
        'autoexports' => true,
        'autoimports' => true,
        'defs' => true,
        'exclude' => true,
        'filepath' => true,
        'identity' => false,
        'include' => true,
        'include-all' => false,
        'include-only' => true,
        'ivars' => true,
        'nullish' => false,
        'nullish_to_s' => false,
        'truthy' => true,
        'strict' => false,
        'template_literal_tags' => true,
        'underscored_private' => false,
        'sourcemap' => false,
        'ast' => false,
        'filtered-ast' => false,
        'show-comments' => false,
        'filter-trace' => false
      }
    end

    def self.default_ruby
      'puts "Hello world!"'
    end
    # convert {"[:foo, :Bar]" => "wee"} to {[:foo, :Bar] => "wee"}
    def self.parse_stringified_symbol_keys(mapping_hash)
      updated_mappings = {}

      mapping_hash.each do |k, v|
        next updated_mappings[k] = v unless k.is_a?(String) && k.start_with?("[:")
      
        new_k = k.tr("[]", "").split(",").map! {|str| str.strip.delete_prefix(":").to_sym }.map(&:to_sym)
        updated_mappings[new_k] = v
      end

      updated_mappings
    end

    # convert {"Foo" => "[:bar, :Baz]"} to {"Foo" => [:bar, :Baz]}
    def self.parse_stringified_symbol_values(mapping_hash)
      updated_mappings = {}

      mapping_hash.each do |k, v|
        next updated_mappings[k] = v unless v.is_a?(String) && v.start_with?("[:")
      
        new_v = v.tr("[]", "").split(",").map! {|str| str.strip.delete_prefix(":").to_sym }.map(&:to_sym)
        updated_mappings[k] = new_v
      end

      updated_mappings
    end

    def self.parse_autoimports(mappings)
      autoimports = {}

      mappings = mappings.gsub(/\s+|"|'/, '')

      while mappings and not mappings.empty?
        if mappings =~ /^(\w+):([^,]+)(,(.*))?$/
          # symbol: module
          autoimports[$1.to_sym] = $2
          mappings = $4
        elsif mappings =~ /^\[([\w,]+)\]:([^,]+)(,(.*))?$/
          # [symbol, symbol]: module
          mname, mappings = $2, $4
          autoimports[$1.split(/,/).map(&:to_sym)] = mname
        elsif mappings =~ /^(\w+)(,(.*))?$/
          # symbol
          autoimports[$1.to_sym] = $1
          mappings = $3
        elsif not mappings.empty?
          $load_error = "unsupported autoimports mapping: #{mappings}"
          mappings = ''
        end
      end

      # if nothing is listed, provide a mapping for everything
      autoimports = proc {|name| name.to_s} if autoimports.empty?

      autoimports
    end

    def self.parse_defs(mappings)
      defs = {}

      mappings = mappings.gsub(/\s+|"|'/, '')

      while mappings =~ /^(\w+):\[(:?@?\w+(,:?@?\w+)*)\](,(.*))?$/
        mappings = $5
        defs[$1.to_sym] = $2.gsub(':', '').split(',').map(&:to_sym)
      end

      if mappings and not mappings.empty?
        $load_error = "unsupported defs: #{mappings}"
      end

      defs
    end
  end
end
