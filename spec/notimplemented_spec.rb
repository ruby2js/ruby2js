require 'minitest/autorun'
require 'ruby2js'

describe 'not implemented' do
  # see https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md

  def todo(string)
    _(proc { Ruby2JS.convert(string, filters: []) }).
      must_raise NotImplementedError
  end

  # Ranges are now implemented - see range_spec.rb
  # for loops and case statements handle ranges specially
  # standalone ranges convert to new $Range(...)

  # class visibility modifiers are now implemented
  # see es2022_spec.rb and converter_spec.rb for tests

  it "pattern matching" do
    todo("case x; in {a:}; a; end")  # case_match
    todo("x in [a, b]")              # match_pattern_p (in operator)
  end

  it "flip-flops" do
    todo("if a..b; end")
  end

  it "implicit matches" do
    todo("if /a/; end")
  end

  it "regular expression back-references" do
    todo("$&")
    todo("$`")
    todo("$'")
    todo("$+")
  end

end
