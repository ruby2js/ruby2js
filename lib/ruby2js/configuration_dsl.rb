module Ruby2JS
  class ConfigurationDSL
    def self.load_from_file(config_file, options = {})
      new(options).tap { _1.instance_eval(File.read(config_file), config_file, 1) }
    end

    def initialize(options = {})
      @options = options
    end

    def preset(bool = true)
      @options[:preset] = bool
    end

    def filter(name)
      @options[:filters] ||= []
      @options[:filters] << name
    end

    def remove_filter(name)
      @options[:disable_filters] ||= []
      @options[:disable_filters] << name
    end

    def eslevel(level)
      @options[:eslevel] = level
    end

    def equality_comparison
      @options[:comparison] = :equality
    end

    def identity_comparison
      @options[:comparison] = :identity
    end

    def esm_modules
      @options[:module] = :esm
    end

    def cjs_modules
      @options[:module] = :cjs
    end

    def underscored_ivars
      @options[:underscored_private] = true
    end

    # Only applies for ES2022+
    def private_field_ivars
      @options[:underscored_private] = false
    end

    def logical_or
      @options[:or] = :logical
    end

    def nullish_or
      @options[:or] = :nullish
    end

    def autoimport(identifier = nil, file = nil, &block)
      if block
        @options[:autoimports] = block
        return
      elsif @options[:autoimports].is_a?(Proc)
        @options[:autoimports] = {}
      end

      @options[:autoimports] ||= {}
      @options[:autoimports][identifier] = file
    end

    def autoimport_defs(value)
      @options[:defs] = value
    end

    def autoexports(value)
      @options[:autoexports] = value
    end

    def include_method(method_name)
      @options[:include] ||= []
      @options[:include] << method_name unless @options[:include].include?(method_name)
    end

    def template_literal_tags(tags)
      @options[:template_literal_tags] = tags
    end

    def to_h
      @options
    end
  end
end
