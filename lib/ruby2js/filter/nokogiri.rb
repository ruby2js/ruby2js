require 'ruby2js'
require 'set'

module Ruby2JS
  module Filter
    module Nokogiri
      include SEXP
      extend SEXP

      NOKOGIRI_SETUP = {
        jsdom: s(:casgn, nil, :JSDOM, 
          s(:attr, s(:send, nil, :require, s(:str, "jsdom")), :JSDOM))
      }

      def initialize(*args)
        @nokogiri_setup = nil
        super
      end

      def process(node)
        return super if @nokogiri_setup
        @nokogiri_setup = Set.new
        result = super

        if @nokogiri_setup.empty?
          result
        else
          s(:begin, 
            *@nokogiri_setup.to_a.map {|token| NOKOGIRI_SETUP[token]},
            result)
        end
      end

      def on_send(node)
        target, method, *args = node.children
        return super if excluded?(method)

        if target == nil
          if 
            method == :require and args.length == 1 and 
            args.first.type == :str and 
            %w(nokogiri nokogumbo).include? args.first.children.first
          then
            s(:begin)

          else
            super
          end

        elsif 
          [:HTML, :HTML5].include? method and
          target == s(:const, nil, :Nokogiri)
        then
          @nokogiri_setup << :jsdom
          S(:attr, s(:attr, s(:send, s(:const, nil, :JSDOM), :new,
            *process_all(args)), :window), :document)

        elsif 
          method == :parse and
          target.type == :const and
          target.children.first == s(:const, nil, :Nokogiri) and
          [:HTML, :HTML5].include? target.children.last
        then
          @nokogiri_setup << :jsdom
          S(:attr, s(:attr, s(:send, s(:const, nil, :JSDOM), :new,
            *process_all(args)), :window), :document)

        elsif 
          method == :at and 
          args.length == 1 and args.first.type == :str
        then
          S(:send, target, :querySelector, process(args.first))

        elsif 
          method == :search and 
          args.length == 1 and args.first.type == :str
        then
          S(:send, target, :querySelectorAll, process(args.first))

        elsif method === :parent and args.length == 0
          S(:attr, target, :parentNode)

        elsif method === :name and args.length == 0
          S(:attr, target, :nodeName)

        elsif [:text, :content].include? method and args.length == 0
          S(:attr, target, :textContent)

        elsif method == :content= and args.length == 1
          S(:send, target, :textContent=, *process_all(args))

        elsif method === :inner_html and args.length == 0
          S(:attr, target, :innerHTML)

        elsif method == :inner_html= and args.length == 1
          S(:send, target, :innerHTML=, *process_all(args))

        elsif method === :to_html and args.length == 0
          S(:attr, target, :outerHTML)

        elsif 
          [:attr, :get_attribute].include? method and 
          args.length == 1 and args.first.type == :str
        then
          S(:send, target, :getAttribute, process(args.first))

        elsif 
          [:key?, :has_attribute].include? method and 
          args.length == 1 and args.first.type == :str
        then
          S(:send, target, :hasAttribute, process(args.first))

        elsif 
          method == :set_attribute and 
          args.length == 2 and args.first.type == :str
        then
          S(:send, target, :setAttribute, *process_all(args))

        elsif 
          method == :attribute and 
          args.length == 1 and args.first.type == :str
        then
          S(:send, target, :getAttributeNode, *process_all(args))

        elsif method == :remove_attribute and args.length == 1
          S(:send, target, :removeAttribute, process(args.first))

        elsif method == :attribute_nodes and args.length == 0
          S(:attr, target, :attributes)

        elsif 
          method == :new and args.length == 2 and
          target == s(:const, s(:const, s(:const, nil, :Nokogiri), :XML), :Node)
        then
          S(:send, process(args.last), :createElement, process(args.first))

        elsif method == :create_element
          create = S(:send, target, :createElement, process(args.first))
          if args.length == 1
            create
          elsif true
            init = []
            args[1..-1].each do |arg|
              if arg.type == :hash
                init += arg.children.map do |pair|
                  s(:send, s(:gvar, :$_), :setAttribute,
                    *process_all(pair.children))
                end
              elsif arg.type == :str
                init << s(:send, s(:gvar, :$_), :content=, process(arg))
              else
                return super
              end
            end

            S(:send, s(:block, s(:send, nil, :proc), s(:args),
              s(:begin, s(:gvasgn, :$_, create), *init,
              s(:return, s(:gvar, :$_)))), :[])
          else
            super
          end

        elsif method == :create_text and args.length == 1
          create = S(:send, target, :createTextNode, process(args.first))

        elsif method == :create_comment and args.length == 1
          create = S(:send, target, :createComment, process(args.first))

        elsif method == :create_cdata and args.length == 1
          create = S(:send, target, :createCDATASection, process(args.first))

        elsif method == :add_child and args.length == 1
          S(:send, target, :appendChild, process(args.first))

        elsif 
          [:add_next_sibling, :next=, :after].include? method and
          args.length == 1
        then
          S(:send, s(:attr, target, :parentNode), :insertBefore,
            process(args.first), s(:attr, target, :nextSibling))

        elsif 
          [:add_previous_sibling, :previous=, :before].include? method and
          args.length == 1
        then
          S(:send, s(:attr, target, :parentNode), :insertBefore,
            process(args.first), target)

        elsif method == :prepend_child and args.length == 1
          S(:send, target, :insertBefore,
            process(args.first), s(:attr, target, :firstChild))

        elsif method == :next_element and args.length == 0
          S(:attr, target, :nextElement)

        elsif [:next, :next_sibling].include? method and args.length == 0
          S(:attr, target, :nextSibling)

        elsif method == :previous_element and args.length == 0
          S(:attr, target, :previousElement)

        elsif 
          [:previous, :previous_sibling].include? method and args.length == 0
        then
          S(:attr, target, :previousSibling)

        elsif method == :cdata? and args.length == 0
          S(:send, s(:attr, target, :nodeType), :===,
            s(:attr, s(:const, nil, :Node), :CDATA_SECTION_NODE))

        elsif method == :comment? and args.length == 0
          S(:send, s(:attr, target, :nodeType), :===,
            s(:attr, s(:const, nil, :Node), :COMMENT_NODE))

        elsif method == :element? and args.length == 0
          S(:send, s(:attr, target, :nodeType), :===,
            s(:attr, s(:const, nil, :Node), :ELEMENT_NODE))

        elsif method == :fragment? and args.length == 0
          S(:send, s(:attr, target, :nodeType), :===,
            s(:attr, s(:const, nil, :Node), :DOCUMENT_FRAGMENT_NODE))

        elsif method == :processing_instruction? and args.length == 0
          S(:send, s(:attr, target, :nodeType), :===,
            s(:attr, s(:const, nil, :Node), :PROCESSING_INSTRUCTION_NODE))

        elsif method == :text? and args.length == 0
          S(:send, s(:attr, target, :nodeType), :===,
            s(:attr, s(:const, nil, :Node), :TEXT_NODE))

        elsif method == :children and args.length == 0
          S(:attr, target, :childNodes)

        elsif method == :first_element_child and args.length == 0
          S(:attr, target, :firstElementChild)

        elsif method == :last_element_child and args.length == 0
          S(:attr, target, :lastElementChild)

        elsif method == :replace and args.length == 1
          S(:send, target, :replaceWith, process(args.first))

        elsif [:remove, :unlink].include? method and args.length == 0
          S(:send, target, :remove)

        elsif method == :root and args.length == 0
          S(:attr, target, :documentElement)

        elsif method == :document and args.length == 0
          S(:attr, target, :ownerDocument)

        end
      end
    end

    DEFAULTS.push Nokogiri
  end
end
