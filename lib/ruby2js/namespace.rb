# Instances of this class keep track of both classes and modules that we have
# seen before, as well as the methods and properties that are defined in each.
#
# Use cases this enables:
#
#   * detection of "open" classes and modules, i.e., redefining a class or
#     module that was previously declared in order to add or modify methods
#     or properties.
#
#   * knowing when to prefix method or property access with `this.` and
#     when to add `.bind(this)` for methods and properties that were defined
#     outside of this class.
#     
module Ruby2JS 
  class Namespace
    def initialize
      @active = [] # current scope
      @seen = {}   # history of all definitions seen previously
    end

    # convert an AST name which is represented as a set of nested 
    # s(:const, # ...) into an array of symbols that represent
    # the relative path.
    def resolve(token, result = [])
      return [] unless token&.type == :const
      resolve(token.children.first, result)
      result.push(token.children.last)
    end
    
    # return the active scope as a flat array of symbols
    def active
      @active.flatten.compact
    end

    # enter a new scope, which may be a nested subscope.  Mark the new scope
    # as seen, and return any previous definition that may have been seen
    # before.
    def enter(name)
      @active.push resolve(name)
      previous = @seen[active]
      @seen[active] ||= {}
      previous
    end

    # return the set of known properties (and methods) for either the current
    # scope or a named subscope.
    def getOwnProps(name = nil)
      @seen[active + resolve(name)]&.dup || {}
    end

    # add new props (and methods) to the current scope.
    def defineProps(props, namespace=active)
      @seen[namespace] ||= {}
      @seen[namespace].merge! props || {}
    end

    # find a named scope which may be relative to any point in the ancestry of
    # the current scope.  Return the properties for that scope.
    def find(name)
      name = resolve(name)
      prefix = active
      while prefix.pop
        result = @seen[prefix + name]
        return result if result
      end
      {}
    end

    # leave a given scope.  Note that the scope may be compound (e.g., M::N),
    # and if so, it will pop the entire resolved name.
    def leave()
      @active.pop
    end
  end
end
