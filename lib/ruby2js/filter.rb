#
# Manage a list of methods to be included or excluded.  This allows fine
# grained control over filters.
#

module Ruby2JS
  module Filter

    #
    # module level defaults
    #

    @@included = nil
    @@excluded = []

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
        @excluded.include? method
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
