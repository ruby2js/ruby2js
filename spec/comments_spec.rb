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

    it "should handle comment before class" do
      js = to_js %{
        # comment before class
        class Greeter
        end
      }

      js.must_include "// comment before class"
      js.must_include "class Greeter"
    end

    it "should not duplicate comments" do
      js = Ruby2JS.convert(<<-EOF, filters: [Ruby2JS::Filter::Functions]).to_s
        #statement
        statement

        #class
        class Class
        end
      EOF

      # Count occurrences of each comment
      statement_count = js.scan("//statement").length
      class_count = js.scan("//class").length

      _(statement_count).must_equal 1, "statement comment should appear exactly once, got #{statement_count}"
      _(class_count).must_equal 1, "class comment should appear exactly once, got #{class_count}"
    end
  end

  describe 'comments with esm filter' do
    def to_js_esm(string)
      require 'ruby2js/filter/esm'
      _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::ESM, Ruby2JS::Filter::Functions]).to_s)
    end

    it "should preserve comment before export class" do
      js = to_js_esm %{
        # comment before export
        export class Exported
        end
      }

      js.must_include "// comment before export"
      js.must_include "export class Exported"
    end

    it "should preserve comment on class inside module" do
      require 'ruby2js/filter/esm'
      # Note: Class needs a body to trigger multiline output (single-line output has no place for comments)
      js = Ruby2JS.convert(<<-EOF, filters: [Ruby2JS::Filter::ESM, Ruby2JS::Filter::Functions]).to_s
        module MyModule
          # class comment
          class Greeter
            def greet
              "hello"
            end
          end
        end
      EOF

      # Comment should appear exactly once (bug was duplicating comments 3x)
      class_comment_count = js.scan("// class comment").length
      _(class_comment_count).must_equal 1, "class comment should appear exactly once, got #{class_comment_count}"
    end
  end
end
