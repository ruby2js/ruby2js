gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Functions do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Functions]).to_s
  end
  
  describe 'conversions' do
    it "should handle everything separately" do
      js = to_js <<-EOF
        #statement
        statement

        #class
        class Class
        end

        #subclass
        class Subclass < Class
        end

        class Constructor
          #constructor
          def initialize
            @constructor = 1
          end
        end

        class Method
          #method
          def method()
            return @foo
          end
        end

        class Attribute
          #attribute
          def attribute
            @attribute
          end
        end

        class Setter
          #setter
          def setter=(n)
            @setter = n
          end
        end

        class ClassMethod
          #classmethod
          def self.classmethod()
            return @@classmethod
          end
        end

        class ClassAttribute
          #classattribute
          def self.classattribute
            @@classattribute
          end
        end

        class ClassSetter
          #classsetter
          def self.classsetter=(n)
            @@classsetter = n
          end
        end
      EOF

      js.must_include "//statement\nvar statement;"
      js.must_include "//class\nfunction Class() {};"
      js.must_include "//subclass\nfunction Subclass() {\n  " +
        "Class.call(this)\n};"
      js.must_include "//constructor\nfunction Constructor() {"
      js.must_include "//method\nMethod.prototype.method = function() {"
      js.must_include "//attribute\n  get attribute() {"
      js.must_include "//setter\n  set setter(n) {"
      js.must_include "//classmethod\nClassMethod.classmethod = function() {"
      js.must_include "//classattribute\nObject.defineProperty(\n  " +
        "ClassAttribute,\n  \"classattribute\""
      js.must_include "//classsetter\nObject.defineProperty(\n  " +
        "ClassSetter,\n  \"classsetter\"" 
    end

    it "should handle everything together" do
      js = to_js <<-EOF
        #statement
        statement

        #subclass
        class Subclass < Class
          #constructor
          def initialize
            super
          end

          #method
          def method()
            @method = 1
          end

          #attribute
          def attribute
            @attribute
          end

          #setter
          def setter=(n)
            @setter = n
          end

          #classmethod
          def self.classmethod()
            return @@classmethod
          end

          #classattribute
          def self.classattribute
            @@classattribute
          end

          #classsetter
          def self.classsetter=(n)
            @@classsetter = n
          end
        end
      EOF

      js.must_include "//statement\nvar statement;"
      js.must_include "//subclass\n//constructor\nfunction Subclass() {\n  " +
        "Class.call(this)\n};"
      js.must_include "//method\nSubclass.prototype.method = function() {"
      js.must_include "//attribute\n  attribute: {"
      js.must_include "//setter\n  setter: {"
      js.must_include "//classmethod\nSubclass.classmethod = function() {"
      js.must_include "//classattribute\n  classattribute: {"
      js.must_include "//classsetter\n  classsetter: {"
    end
  end
end
