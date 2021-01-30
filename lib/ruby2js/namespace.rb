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

    def getOwnProps(name = nil)
      @seen[active + resolve(name)] || {}
    end

    def defineProps(props)
      @seen[active].merge! props || {}
    end

    def find(name)
      name = resolve(name)
      prefix = active
      while prefix.pop
        result = @seen[prefix + name]
        return result if result
      end
      {}
    end

    def leave()
      @active.pop
    end
  end
end
