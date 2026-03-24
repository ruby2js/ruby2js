require 'minitest/autorun'
require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/selfhost/app_filter'

describe "Selfhost App Filter" do

  def transpile(source)
    Ruby2JS.convert(source,
      eslevel: 2022,
      filters: [
        Ruby2JS::Filter::Selfhost::AppFilter,
        Ruby2JS::Filter::Functions,
        Ruby2JS::Filter::Return,
        Ruby2JS::Filter::ESM
      ]
    ).to_s
  end

  describe 'basic filter generation' do
    it "generates a filter class from DSL" do
      source = <<~RUBY
        filter :MyFilter do
          rewrite 'puts(_1)', to: 'console.log(_1)'
        end
      RUBY
      js = transpile(source)
      _(js).must_include 'class MyFilter extends Filter.Processor'
      _(js).must_include 'registerFilter("MyFilter"'
      _(js).must_include 'export default MyFilter'
    end

    it "generates import from ruby2js" do
      source = <<~RUBY
        filter :MyFilter do
          rewrite 'puts(_1)', to: 'console.log(_1)'
        end
      RUBY
      js = transpile(source)
      _(js).must_include 'import'
      _(js).must_include 'ruby2js'
    end

    it "generates on_send method with pattern matching" do
      source = <<~RUBY
        filter :MyFilter do
          rewrite 'puts(_1)', to: 'console.log(_1)'
        end
      RUBY
      js = transpile(source)
      _(js).must_include 'on_send(node)'
    end

    it "copies SEXP to prototype" do
      source = <<~RUBY
        filter :MyFilter do
          rewrite 'puts(_1)', to: 'console.log(_1)'
        end
      RUBY
      js = transpile(source)
      _(js).must_include 'Object.defineProperties'
      _(js).must_include 'SEXP'
    end
  end

  describe 'rewrite expansion' do
    it "generates type check for pattern" do
      source = <<~RUBY
        filter :MyFilter do
          rewrite 'puts(_1)', to: '"stubbed"'
        end
      RUBY
      js = transpile(source)
      # Should check node.type === "send"
      _(js).must_include '"send"'
    end

    it "generates method name check" do
      source = <<~RUBY
        filter :MyFilter do
          rewrite 'puts(_1)', to: '"stubbed"'
        end
      RUBY
      js = transpile(source)
      # Should check for :puts method name
      _(js).must_include '"puts"'
    end

    it "handles constant chain patterns" do
      source = <<~RUBY
        filter :MyFilter do
          rewrite 'RQRCode::QRCode.new(_1)', to: '"stub"'
        end
      RUBY
      js = transpile(source)
      _(js).must_include '"QRCode"'
      _(js).must_include '"RQRCode"'
    end
  end

  describe 'JavaScript validity' do
    it "produces valid JavaScript" do
      source = <<~RUBY
        filter :TestFilter do
          rewrite 'puts(_1)', to: 'console.log(_1)'
        end
      RUBY
      js = transpile(source)

      # Write to temp file and check with node
      require 'tempfile'
      Tempfile.create(['filter_test', '.mjs']) do |f|
        # Stub the import so node --check doesn't fail on missing module
        stubbed = js.gsub(/^import .* from "ruby2js"/,
          'const Filter = {Processor: class{}}; const SEXP = {}; function s(){} function registerFilter(){}')
        f.write(stubbed)
        f.flush
        result = system("node --check #{f.path} 2>/dev/null")
        _(result).must_equal true
      end
    end
  end

  describe 'multiple rewrites' do
    it "generates multiple pattern checks" do
      source = <<~RUBY
        filter :MyFilter do
          rewrite 'puts(_1)', to: 'console.log(_1)'
          rewrite 'p(_1)', to: 'console.log(_1)'
        end
      RUBY
      js = transpile(source)
      _(js).must_include '"puts"'
      _(js).must_include '"p"'
    end
  end
end
