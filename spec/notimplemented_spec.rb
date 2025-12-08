require 'minitest/autorun'
require 'ruby2js'

describe 'not implemented' do
  # see https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md

  def todo(string)
    _(proc { Ruby2JS.convert(string, filters: []) }).
      must_raise NotImplementedError
  end

  it "range inclusive" do
    # NOTE: for loops and filter/functions will handle the special case of array indexes
    # NOTE: filter/rubyjs implements this
    # NOTE: .to_a is implemented in send

    todo( '1..2' )
  end

  it "range exclusive" do
    # NOTE: for loops and filter/functions will handle the special case of array indexes
    # NOTE: filter/rubyjs implements this
    todo( '1...2' )
  end

  it "class visibility modifiers" do
    todo( 'class C; public; end' )
    todo( 'class C; private; end' )
    todo( 'class C; protected; end' )
  end

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
