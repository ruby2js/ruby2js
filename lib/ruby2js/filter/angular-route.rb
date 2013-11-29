require 'parser/current'
require 'ruby2js/filter/angularrb'

module Ruby2JS
  module Filter
    module AngularRoute
      include SEXP

      # input: 
      #   case $routeProvider
      #   when '/path'
      #     templateUrl = 'partials/path.html'
      #   else
      #     redirectTo '/path'
      #   end
      #
      # output: 
      #   AppName.config(["$routeProvider", function($routeProvider) {
      #     $routeProvider.when("/path", {templateUrl: 'partials/path.html'}).
      #     otherwise({redirectTo: "/path"}))

      def on_case(node)
        rp = :$routeProvider
        return super unless @ngApp and node.children.first == s(:gvar, rp)
        @ngAppUses << :ngRoute
        code = s(:lvar, rp)

        hash = proc do |pairs|
          if pairs.length == 1 and pairs.first.type == :begin
            pairs = pairs.first.children
          end
          s(:hash, *pairs.map {|pair| 
            if pair.type == :send
              s(:pair, s(:sym, pair.children[1]), pair.children[2])
            else
              s(:pair, s(:sym, pair.children[0]), pair.children[1])
            end
          })
        end

        node.children[1..-2].each do |child|
          code = s(:send, code, :when, child.children.first,
            hash[child.children[1..-1]])
        end

        if node.children.last
          code = s(:send, code, :otherwise, 
            hash[node.children[-1..-1]])
        end

        s(:send, s(:lvar, @ngApp), :config, s(:array, s(:str, rp.to_s),
          s(:block, 
            s(:send, nil, :proc), s(:args, s(:arg, rp)), code)))
      end
    end

    DEFAULTS.push AngularRoute
  end
end
