require 'parser/current'
require 'ruby2js/filter/angularrb'

module Ruby2JS
  module Filter
    module AngularResource
      include SEXP

      # input: 
      #   $resource.new(args)
      #
      # output: 
      #   $resource(args)

      def on_send(node)
        return super unless @ngApp and node.children[1] == :new
        return super unless node.children[0] == s(:gvar, :$resource)
        node = super(node)
        @ngAppUses << :ngResource
        node.updated nil, [nil, :$resource, *node.children[2..-1]]
      end
    end

    DEFAULTS.push AngularResource
  end
end
