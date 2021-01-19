module Ruby2JS
  class Converter

    # (begin
    #   (...)
    #   (...))

    handle :begin do |*statements|
      state = @state
      props = false

      if state == :expression and statements.empty?
        puts 'null'
        return
      end

      statements.map! do |statement|
        case statement and statement.type
        when :defs, :defp
          props = true
          @ast = statement
          transform_defs(*statement.children)
        when :prop
          props = true
          statement
        else
          statement
        end
      end

      if props
        combine_properties(statements) if props
        statements.compact!
      end

      parse_all(*statements, state: state, join: @sep)
    end

    def combine_properties(body)
      (0...body.length-1).each do |i|
        next unless body[i] and body[i].type == :prop
        (i+1...body.length).each do |j|
          break unless body[j] and body[j].type == :prop

          if body[i].children[0] == body[j].children[0]
            # relocate property comment to first method
            [body[i], body[j]].each do |node|
              unless @comments[node].empty?
                node.children[1].values.first.each do |key, value| 
                  if [:get, :set].include? key and Parser::AST::Node === value
                    @comments[value] = @comments[node]
                    break
                  end
                end
              end
            end

            # merge properties
            merge = Hash[(body[i].children[1].to_a+body[j].children[1].to_a).
              group_by {|name, value| name.to_s}.map {|name, values|
              [name, values.map(&:last).reduce(:merge)]}]
            body[j] = s(:prop, body[j].children[0], merge)
            body[i] = nil
            break
          end
        end
      end
    end
  end
end
