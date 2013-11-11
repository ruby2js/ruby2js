require 'minitest/autorun'
require 'ruby2js/filter/angularrb'

describe Ruby2JS::Filter::AngularRB do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::AngularRB])
  end
  
  describe 'module' do
    it "should convert modules" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          use :PhonecatFilters
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        const PhonecatApp = angular.module("PhonecatApp", ["PhonecatFilters"])
      JS

      to_js( ruby ).must_equal js
    end
  end
  
  describe 'controllers' do
    it "should convert apps with a controller" do
      ruby = <<-RUBY
        module Angular::PhonecatApp 
          class PhoneListCtrl < Angular::Controller 
            use :$scope

            $scope.orderProp = 'age'
          end
        end
      RUBY

      js = <<-JS.gsub!(/^ {8}/, '').chomp
        const PhonecatApp = angular.module("PhonecatApp", []);

        PhonecatApp.controller("PhoneListCtrl", function($scope) {
          $scope.orderProp = "age"
        })
      JS

      to_js( ruby ).must_equal js
    end
  end
end
