#
# Manage a list of methods to be included or excluded.  This allows fine
# grained control over filters.
#

module Ruby2JS
  module Filter
    PRESET_FILTERS = [:esm, :functions, :pragma, :return]

    def self.registered_filters
      @@registered_filters ||= {}
    end

    def self.autoregister(lib_dir = File.expand_path("..", __dir__))
      Dir["#{lib_dir}/ruby2js/filter/*.rb"].sort.each do |file|
        filter = File.basename(file, '.rb')
        registered_filters[filter] = file
      end

      registered_filters
    end

    # TODO: better document this code path
    def self.require_filters(filters)
      mods = []
      filters.each do |name|
        if name.is_a?(Module)
          mods << name
          next
        end

        name = name.to_s

        if registered_filters[name].is_a?(Module)
          mods << registered_filters[name]
          next
        end

        begin
          if registered_filters.include? name
            mods_before = mods.length
            defaults_before = Ruby2JS::Filter::DEFAULTS.dup
            require registered_filters[name]

            # Check if filter added itself to DEFAULTS
            new_defaults = Ruby2JS::Filter::DEFAULTS - defaults_before
            if new_defaults.any?
              new_defaults.each { |mod| mods << mod }
            else
              # Also check existing DEFAULTS (file may have been required earlier)
              Ruby2JS::Filter::DEFAULTS.each do |mod|
                method = mod.instance_method(mod.instance_methods.first)
                if registered_filters[name] == method.source_location.first
                  mods << mod
                end
              end
            end

            # Fallback: Filter didn't register with DEFAULTS, try const_get
            if mods.length == mods_before
              mod_name = name.split('/').map { |part|
                part.split('_').map(&:capitalize).join
              }.join('::')
              begin
                mod = Ruby2JS::Filter.const_get(mod_name)
                mods << mod if mod.is_a?(Module)
              rescue NameError
                # Module not found by that name
              end
            end
          elsif not name.empty? and name =~ /^[-\w\/]+$/
            # Try to require unregistered filter by name
            # Supports both "selfhost/walker" and "selfhost_walker" (underscores converted to slashes)
            require_name = "ruby2js/filter/#{name.tr('_', '/')}"
            defaults_before = Ruby2JS::Filter::DEFAULTS.dup
            require require_name
            # Add any new modules that were registered
            new_defaults = Ruby2JS::Filter::DEFAULTS - defaults_before
            if new_defaults.any?
              new_defaults.each { |mod| mods << mod }
            else
              # Filter didn't register with DEFAULTS, try to find module by name
              # Convert "selfhost/converter" to Selfhost::Converter
              mod_name = name.split('/').map { |part|
                part.split('_').map(&:capitalize).join
              }.join('::')
              begin
                mod = Ruby2JS::Filter.const_get(mod_name)
                mods << mod if mod.is_a?(Module)
              rescue NameError
                # Module not found by that name
              end
            end
          end
        rescue LoadError
          $load_error = "UNKNOWN filter: #{name}"
        rescue Exception => $load_error
        end
      end

      mods
    end

    #
    # module level defaults
    #

    @@included = nil
    @@excluded = []

    def self.included_methods
      @@included&.dup
    end

    def self.excluded_methods
      @@excluded&.dup
    end

    # indicate that the specified methods are not to be processed
    def self.exclude(*methods)
      if @@included
        @@included -= methods.flatten
      else
        @@excluded += methods.flatten
      end
    end

    # indicate that all methods are to be processed
    def self.include_all
      @@included = nil
      @@excluded = []
    end

    # indicate that only the specified methods are to be processed
    def self.include_only(*methods)
      @@included = methods.flatten
    end

    # indicate that the specified methods are to be processed
    def self.include(*methods)
      if @@included
        @@included += methods.flatten
      else
        @@excluded -= methods.flatten
      end
    end

    #
    # instance level overrides
    #

    # determine if a method is NOT to be processed
    def excluded?(method)
      if @included
        not @included.include? method
      else
        return true if @exclude_methods.flatten.include? method
        @excluded&.include? method
      end
    end

    # indicate that all methods are to be processed
    def include_all
      @included = nil
      @excluded = []
    end

    # indicate that only the specified methods are to be processed
    def include_only(*methods)
      @included = methods.flatten
    end

    # indicate that the specified methods are to be processed
    def include(*methods)
      if @included
        @included += methods.flatten
      else
        @excluded -= methods.flatten
      end
    end

    # indicate that the specified methods are not to be processed
    def exclude(*methods)
      if @included
        @included -= methods.flatten
      else
        @excluded += methods.flatten
      end
    end
  end
end
