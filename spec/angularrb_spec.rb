gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/angularrb'
require 'ruby2js/filter/angular-route'
require 'ruby2js/filter/angular-resource'

describe Ruby2JS::Filter::AngularRB do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::AngularRB,
      Ruby2JS::Filter::AngularRoute, Ruby2JS::Filter::AngularResource])
  end
  
  # ************************************************************ 
  #                            module
  # ************************************************************ 

  describe 'module' do
    it "should convert empty modules" do
      to_js( 'module Angular::X; end' ).
        must_equal 'angular.module("X", [])'
    end

    it "should convert modules with a use statement" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          use :PhonecatFilters
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", ["PhonecatFilters"])
      JS

      to_js( ruby ).must_equal js
    end

    it "should convert modules with multiple controllers" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller(:foo) {}
          controller(:bar) {}
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        (function() {
          var PhonecatApp = angular.module("PhonecatApp", []);
          PhonecatApp.controller("foo", function() {  });
          PhonecatApp.controller("bar", function() {  })
        })()
      JS

      to_js( ruby ).must_equal js
    end
  end
  
  # ************************************************************ 
  #                         controllers
  # ************************************************************ 

  describe 'controllers' do
    it "should convert apps with a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            $scope.orderProp = 'age'
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope) {
            $scope.orderProp = "age"
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should map instance variables to $scope within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            @orderProp = 'age'
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope) {
            $scope.orderProp = "age"
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should support operator assignments using instance variables" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            @orderProp ||= 'age'
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope) {
            $scope.orderProp = $scope.orderProp || "age"
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should map instance methods to $scope within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            def save()
              $http.post '/data', @data
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($http, $scope) {
            $scope.save = function() {
              $http.post("/data", $scope.data)
            }
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should properties to $scope within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            def prop 
              @prop
            end

            def prop=(prop)
              @prop=prop
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope) {
            Object.defineProperty(
              $scope,
              "prop",

              {
                enumerable: true,
                configurable: true,

                get: function() {
                  return $scope.prop
                },

                set: function(prop) {
                  $scope.prop = prop
                }
              }
            )
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should map watch to $scope.$watch within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            watch 'list' do
              @orderProp = 'age'
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope) {
            $scope.$watch("list", function() { $scope.orderProp = "age" })
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should allow you to watch expressions" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            watch @value do |value|
              @orderProp = value
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope) {
            $scope.$watch(
              function() {
                return $scope.value
              },

              function(value) {
                $scope.orderProp = value
              }
            )
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should map on to $scope.$on within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            on :update do
              @orderProp = 'age'
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope) {
            $scope.$on("update", function() { $scope.orderProp = "age" })
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should map broadcast! to $rootScope.$broadcast within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            broadcast! :update
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($rootScope) {
            $rootScope.$broadcast("update")
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should map timeout to $timeout within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            timeout 500 do
              update()
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($timeout) {
            $timeout(function() { update() }, 500)
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should map interval to $interval within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            interval 5000 do
              update()
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($interval) {
            $interval(function() { update() }, 5000)
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should map filter to $filter within a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            f = filter(:f)
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($filter) {
            var f = $filter("f")
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should allow modules to be reopend to add a controller" do
      ruby = <<-RUBY
        Angular::PhonecatApp.controller :PhoneListCtrl do 
          $scope.orderProp = 'age'
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp").controller(
          "PhoneListCtrl",

          function($scope) {
            $scope.orderProp = "age"
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "factory references should imply use" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            $scope.phones = Phone.list()
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope, Phone) {
            $scope.phones = Phone.list()
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "reference to builtins shouldn't imply use" do
      ruby = <<-'RUBY'
        module Angular::PhonecatApp 
          controller :PhoneListCtrl do 
            $scope.phone_pattern = Regexp.new('\d{3}-\d{3}-\d{4}')
          end
        end
      RUBY

      js = <<-'JS'.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).controller(
          "PhoneListCtrl",

          function($scope) {
            $scope.phone_pattern = /\d{3}-\d{3}-\d{4}/
          }
        )
      JS

      to_js( ruby ).must_equal js
    end
  end
  
  # ************************************************************ 
  #                            filter
  # ************************************************************ 

  describe 'filter' do
    it "should convert apps with a filter" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          filter :pnl do |input|
            return $sce.trustAsHTML(input < 0 ? "loss" : "<em>profit</em>")
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).filter(
          "pnl",

          function($sce) {
            return function(input) {
              return $sce.trustAsHTML((input < 0 ? "loss" : "<em>profit</em>"))
            }
          }
        )
      JS

      to_js( ruby ).must_equal js
    end
  end
  
  # ************************************************************ 
  #                            route
  # ************************************************************ 

  describe 'route' do
    it "should convert apps with a route" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          case $routeProvider
          when '/phones'
            controller = :PhoneListCtrl
          else
            redirectTo '/phones'
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", ["ngRoute"]).config([
          "$routeProvider",

          function($routeProvider) {
            $routeProvider.when("/phones", {controller: "PhoneListCtrl"}).otherwise({redirectTo: "/phones"})
          }
        ])
      JS

      to_js( ruby ).must_equal js
    end
  end

  # ************************************************************ 
  #                            filter
  # ************************************************************ 

  describe 'factory' do
    it "should convert apps with a factory" do
      ruby = <<-RUBY
        module Angular::Service
          factory :Phone do
            return $resource.new 'phone/:phoneId.json'
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("Service", ["ngResource"]).factory(
          "Phone",

          [
            "$resource",

            function($resource) {
              return $resource("phone/:phoneId.json")
            }
          ]
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should convert apps with a factory defined as a class" do
      ruby = <<-RUBY
        module Angular::Service
          class Phone
            def self.name
              "XYZZY"
            end
            def self.reset()
              return "PLUGH"
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("Service", []).factory(
          "Phone",

          function() {
            function Phone() {};

            Object.defineProperty(
              Phone,
              "name",

              {
                enumerable: true,
                configurable: true,

                get: function() {
                  return "XYZZY"
                }
              }
            );

            Phone.reset = function() {
              return "PLUGH"
            };

            return Phone
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should handle class inheritance" do
      ruby = <<-RUBY
        module Angular::Service
          class A; end
          class B < A; end
        end
      RUBY

      to_js( ruby ).must_match /Service.factory\(\s+"B",\s+function\(A\) {/
    end
  end

  # ************************************************************ 
  #                          directives
  # ************************************************************ 

  describe 'directives' do
    it "should convert apps with a directive -- short form" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          directive :my_signature do 
            template '--signature'
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).directive(
          "my_signature",

          function() {
            return {template: "--signature"}
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should convert directives with a link/interpolate" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          directive :name1 do
            def link(scope, elem, attrs)
              elem.attr('name2', interpolate(attrs.name1))
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).directive(
          "name1",

          function($interpolate) {
            return {link: function(scope, elem, attrs) {
              elem.attr("name2", $interpolate(attrs.name1)(scope))
            }}
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should convert directives with a link/compile" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          directive :name1 do
            def link(scope, elem, attrs)
              compile(elem)
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).directive(
          "name1",

          function($compile) {
            return {link: function(scope, elem, attrs) {
              $compile(elem)(scope)
            }}
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should convert directives with a link/watch" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          directive :name1 do
            def link(scope, elem, attrs)
              watch @value1 do
                @value2 = @value1
              end
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).directive(
          "name1",

          function() {
            return {link: function(scope, elem, attrs) {
              scope.$watch(
                function() {
                  return scope.value1
                },

                function() {
                  scope.value2 = scope.value1
                }
              )
            }}
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should convert directives with a link/observe" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          directive :name1 do
            def link(scope, elem, attrs)
              observe attrs.name1 do |value|
                elem.attr('name2', value)
              end
            end
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).directive(
          "name1",

          function() {
            return {link: function(scope, elem, attrs) {
              attrs.$observe(
                \"name1\",

                function(value) {
                  elem.attr(\"name2\", value)
                }
              )
            }}
          }
        )
      JS

      to_js( ruby ).must_equal js
    end

    it "should convert apps with a directive -- long form" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          directive :my_signature do 
            return {template: '--signature'}
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).directive(
          "my_signature",

          function() {
            return {template: "--signature"}
          }
        )
      JS

      to_js( ruby ).must_equal js
    end
  end

  # ************************************************************
  #                            config
  # ************************************************************ 

  describe 'config' do
    it "should convert apps with config -- long form" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          config :$locationServices do 
            html5mode = true
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).config([
          "$locationServices",

          function($locationServices) {
            $locationServices.html5mode = true
          }
        ])
      JS

      to_js( ruby ).must_equal js
    end

    it "should convert apps with config -- short form" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          $locationServices.html5mode = true
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        angular.module("PhonecatApp", []).config([
          "$locationServices",

          function($locationServices) {
            $locationServices.html5mode = true
          }
        ])
      JS

      to_js( ruby ).must_equal js
    end
  end

  # ************************************************************ 
  #                           defaults
  # ************************************************************ 

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include AngularRB" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::AngularRB
    end

    it "should include AngularRoute" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::AngularRoute
    end

    it "should include AngularResource" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::AngularResource
    end
  end
end
