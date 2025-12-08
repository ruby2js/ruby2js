require 'minitest/autorun'
require 'ruby2js'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'
require 'tempfile'

describe "Selfhost Spec Transpilation" do
  def transpile_spec(spec_file)
    source = File.read(spec_file)

    # Add skip pragmas to external requires (minitest, ruby2js gem)
    source = source.gsub(/^(require\s+['"][^'"]*['"])/) do
      "#{$1} # Pragma: skip"
    end

    Ruby2JS.convert(source,
      eslevel: 2022,
      comparison: :identity,
      underscored_private: true,
      file: spec_file,
      filters: [
        Ruby2JS::Filter::Pragma,
        Ruby2JS::Filter::Combiner,
        Ruby2JS::Filter::Selfhost::Core,
        Ruby2JS::Filter::Selfhost::Walker,
        Ruby2JS::Filter::Selfhost::Spec,
        Ruby2JS::Filter::Functions,
        Ruby2JS::Filter::Return,
        Ruby2JS::Filter::ESM
      ]
    ).to_s
  end

  def check_syntax(js_code)
    Tempfile.create(['spec_test', '.mjs']) do |f|
      f.write(js_code)
      f.flush
      result = `node --check #{f.path} 2>&1`
      [result, $?.success?]
    end
  end

  describe "transliteration_spec.rb" do
    it "transpiles to syntactically valid JavaScript" do
      spec_file = File.expand_path('../transliteration_spec.rb', __FILE__)
      js = transpile_spec(spec_file)

      # Write to a file for inspection
      File.write('/tmp/transliteration_spec.mjs', js)

      result, success = check_syntax(js)
      if !success
        # Show first few errors
        puts "\n--- Syntax errors ---"
        puts result.lines.first(20).join
        puts "..."
        puts "\nFull output at /tmp/transliteration_spec.mjs"
      end
      _(success).must_equal true, "JavaScript syntax check failed: #{result}"
    end
  end
end
