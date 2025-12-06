gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Functions do
  
  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Functions]).to_s)
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

      js.must_include "//statement\nlet statement;"
      js.must_include "//class\nclass Class {"
      js.must_include "//subclass\nclass Subclass extends Class {"
      js.must_include "//constructor\n  constructor() {"
      js.must_include "//method\n  method() {"
      js.must_include "//attribute\n  get attribute() {"
      js.must_include "//setter\n  set setter(n) {"
      js.must_include "//classmethod\n  static classmethod() {"
      js.must_include "//classattribute\n  static get classattribute() {"
      js.must_include "//classsetter\n  static set classsetter(n) {" 
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

      js.must_include "//statement\nlet statement;"
      js.must_include "//subclass\nclass Subclass extends Class {"
      js.must_include "//constructor\n  constructor() {"
      js.must_include "//method\n  method() {"
      js.must_include "//attribute\n  get attribute() {"
      js.must_include "//setter\n  set setter(n) {"
      js.must_include "//classmethod\n  static classmethod() {"
      js.must_include "//classattribute\n  static get classattribute() {"
      js.must_include "//classsetter\n  static set classsetter(n) {"
    end

    it "should handle =begin...=end" do
      js = to_js %{
        =begin
        comment
        =end
        statement
      }.gsub(/^\s+/, '')

      js.must_equal "/*\ncomment\n*/\nlet statement"
    end

    it "should handle =begin...*/...=end" do
      js = to_js %{
        =begin
        /* comment */
        =end
        statement
      }.gsub(/^\s+/, '')

      js.must_equal "//\n///* comment */\n//\nlet statement"
    end
  end
end
