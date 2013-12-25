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

        node.children[1..-2].each do |child|
          code = s(:sendw, code, :when, child.children.first,
            AngularRB.hash(child.children[1..-1]))
        end

        if node.children.last
          code = s(:sendw, code, :otherwise, 
            AngularRB.hash(node.children[-1..-1]))
        end

        s(:send, @ngApp, :config, s(:array, s(:str, rp.to_s), s(:block, 
            s(:send, nil, :proc), s(:args, s(:arg, rp)), code)))
      end
    end

    DEFAULTS.push AngularRoute
  end
end
