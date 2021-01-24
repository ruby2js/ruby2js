module Ruby2JS 
  class Namespace
    def initialize
      @active = []
      @seen = {}
    end

    def resolve(token, result = [])
      return [] unless token&.type == :const
      resolve(token.children.first, result)
      result.push(token.children.last)
    end
    
    def active
      @active.flatten.compact
    end

    def enter(name)
      @active.push resolve(name)
      previous = @seen[active]
      @seen[active] ||= {}
      previous
    end

    def find(name)
      @seen[active + resolve(name)]
    end

    def leave()
      @active.pop
    end
  end
end
