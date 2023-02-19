# TODO: This feature is deprecated.
#
# Example usage:
#
#   Add:
#      gem 'ruby2js'
# to your gemfile and bundle
#  Add:
#  require "ruby2js/haml"
#   to any initializer ot config/application.rb
#
#  Use :ruby2js filter in your templates like
#
#  :ruby2js
#    alert "Hello"
#
# (Note missing brackets: ruby syntax, js sematics)
#
require "haml"
require "haml/filters"
require "haml/filters/base"

module Haml
  class Filters
    class Ruby2JS < Base
      def compile(node)
        temple = [:multi]
        temple << [:static, "<script type='text/javascript'>\n"]
        compile_ruby!( temple , node )
        temple << [:static, "\n</script>"]
        temple
      end

      #Copird from text base, added ruby2js convert
      def compile_ruby!(temple, node)
        text = node.value[:text]
        if ::Haml::Util.contains_interpolation?(node.value[:text])
          # original: Haml::Filters#compile
          text = ::Haml::Util.unescape_interpolation(text).gsub(/(\\+)n/) do |s|
            escapes = $1.size
            next s if escapes % 2 == 0
            "#{'\\' * (escapes - 1)}\n"
          end
          text.prepend("\n")

          temple << [:dynamic, "::Ruby2JS.convert(#{text} ).to_s"]
        else
          temple << [:static, ::Ruby2JS.convert(text).to_s]
        end
      end


    end
  end
end


Haml::Filters.registered[:ruby2js] ||= Haml::Filters::Ruby2JS
