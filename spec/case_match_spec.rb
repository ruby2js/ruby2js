require 'minitest/autorun'
require 'ruby2js'

describe "case/in pattern matching" do

  def to_js(string, opts={})
    _(Ruby2JS.convert(string, opts.merge(filters: [])).to_s)
  end

  describe 'literal patterns' do
    it "should match integers" do
      to_js('case x; in 1; "one"; in 2; "two"; end').
        must_include 'if ($case1 === 1)'
    end

    it "should match strings" do
      to_js('case x; in "hello"; "matched"; end').
        must_include '$case1 === "hello"'
    end

    it "should match symbols" do
      to_js('case x; in :foo; "matched"; end').
        must_include '$case1 === "foo"'
    end

    it "should match nil" do
      to_js('case x; in nil; "matched"; end').
        must_include '$case1 == null'
    end

    it "should match true and false" do
      to_js('case x; in true; "t"; in false; "f"; end').
        must_include '$case1 === true'
      to_js('case x; in true; "t"; in false; "f"; end').
        must_include '$case1 === false'
    end
  end

  describe 'variable capture' do
    it "should bind match_var" do
      result = to_js('case x; in y; puts y; end')
      result.must_include 'let y = $case1'
    end

    it "should handle wildcard without binding" do
      result = to_js('case x; in _; "any"; end')
      result.must_include 'if (true)'
      result.wont_include 'let _ ='
    end
  end

  describe 'type check patterns' do
    it "should check Integer" do
      to_js('case x; in Integer; "int"; end').
        must_include 'typeof $case1 === "number" && Number.isInteger($case1)'
    end

    it "should check String" do
      to_js('case x; in String; "str"; end').
        must_include 'typeof $case1 === "string"'
    end

    it "should check Array" do
      to_js('case x; in Array; "arr"; end').
        must_include 'Array.isArray($case1)'
    end

    it "should use instanceof for unknown constants" do
      to_js('case x; in MyClass; "mine"; end').
        must_include '$case1 instanceof MyClass'
    end
  end

  describe 'match_as (Type => var)' do
    it "should check type and bind variable" do
      result = to_js('case x; in Integer => n; n; end')
      result.must_include 'typeof $case1 === "number" && Number.isInteger($case1)'
      result.must_include 'let n = $case1'
    end
  end

  describe 'alternation (|)' do
    it "should combine conditions with ||" do
      to_js('case x; in 1 | 2 | 3; "match"; end').
        must_include '||'
    end

    it "should match true | false" do
      result = to_js('case x; in true | false; "bool"; end')
      result.must_include '$case1 === true || $case1 === false'
    end
  end

  describe 'pin operator (^)' do
    it "should test equality against pinned variable" do
      result = to_js('y = 1; case x; in ^y; "pinned"; end')
      result.must_include '$case1 === y'
    end
  end

  describe 'array patterns' do
    it "should match fixed-length array" do
      result = to_js('case x; in [1, 2]; "pair"; end')
      result.must_include 'Array.isArray($case1)'
      result.must_include '$case1.length === 2'
      result.must_include '$case1[0] === 1'
      result.must_include '$case1[1] === 2'
    end

    it "should capture array elements" do
      result = to_js('case x; in [a, b]; puts a; end')
      result.must_include 'let a = $case1[0]'
      result.must_include 'let b = $case1[1]'
    end

    it "should handle splat at end" do
      result = to_js('case x; in [first, *rest]; first; end')
      result.must_include '$case1.length >= 1'
      result.must_include 'let first = $case1[0]'
      result.must_include 'let rest = $case1.slice(1)'
    end

    it "should handle splat in middle" do
      result = to_js('case x; in [a, *mid, z]; a; end')
      result.must_include '$case1.length >= 2'
      result.must_include 'let a = $case1[0]'
      result.must_include 'let mid = $case1.slice(1, $case1.length - 1)'
      result.must_include 'let z = $case1[$case1.length - 1]'
    end

    it "should handle nested type checks in array" do
      result = to_js('case x; in [:send, nil, :puts]; "match"; end')
      result.must_include '$case1.length === 3'
      result.must_include '$case1[0] === "send"'
      result.must_include '$case1[1] == null'
      result.must_include '$case1[2] === "puts"'
    end
  end

  describe 'hash patterns' do
    it "should match implicit key pattern" do
      result = to_js('case x; in {name:}; name; end')
      result.must_include '"name" in $case1'
      result.must_include 'let name = $case1.name'
    end

    it "should match explicit key with type check" do
      result = to_js('case x; in {name: String => n, age: 42}; n; end')
      result.must_include '"name" in $case1'
      result.must_include 'typeof $case1.name === "string"'
      result.must_include '"age" in $case1'
      result.must_include '$case1.age === 42'
      result.must_include 'let n = $case1.name'
    end

    it "should check object type" do
      to_js('case x; in {a:}; a; end').
        must_include 'typeof $case1 === "object" && $case1 !== null'
    end
  end

  describe 'find patterns' do
    it "should use includes for simple literals" do
      result = to_js('case x; in [*, 42, *]; "found"; end')
      result.must_include 'Array.isArray($case1)'
      result.must_include '$case1.includes(42)'
    end

    it "should use some() for complex patterns" do
      result = to_js('case x; in [*, String, *]; "found"; end')
      result.must_include 'Array.isArray($case1)'
      result.must_include '.some('
      result.must_include 'typeof'
    end
  end

  describe 'guard clauses' do
    it "should emit guard after bindings" do
      result = to_js('case x; in Integer => n if n > 0; "positive"; end')
      # Guard must appear after the binding of n
      result.must_include 'let n = $case1'
      result.must_include 'if (n > 0)'
    end

    it "should handle unless guard" do
      result = to_js('case x; in Integer => n unless n < 0; "positive"; end')
      result.must_include 'let n = $case1'
      result.must_include 'Number.isInteger'
      # unless n < 0 becomes if n >= 0
      result.wont_include 'unless'
    end
  end

  describe 'lambda patterns' do
    it "should call lambda with target value" do
      result = to_js('case x; in -> (v) { v > 0 }; "matched"; end')
      result.must_include '($case1)'
      result.must_include '=>'
      result.wont_include '==='
    end
  end

  describe 'else clause' do
    it "should emit else branch" do
      result = to_js('case x; in 1; "one"; else; "other"; end')
      result.must_include 'else {'
      result.must_include '"other"'
    end
  end

  describe 'nested patterns' do
    it "should handle nested array in hash" do
      result = to_js('case data; in {users: [first, *]}; first; end')
      result.must_include '"users" in $case1'
      result.must_include 'Array.isArray($case1.users)'
      result.must_include 'let first = $case1.users[0]'
    end

    it "should handle deeply nested patterns" do
      result = to_js('case data; in {users: [{name: String => n}, *]}; n; end')
      result.must_include '"users" in $case1'
      result.must_include 'Array.isArray($case1.users)'
      result.must_include 'typeof $case1.users[0].name === "string"'
      result.must_include 'let n = $case1.users[0].name'
    end
  end

  describe 'match_pattern_p (in operator)' do
    it "should return boolean for x in pattern" do
      result = to_js('x in [1, 2]')
      result.must_include 'Array.isArray($case1)'
      result.must_include '$case1.length === 2'
      result.must_include 'return'
    end
  end

  describe 'multiple branches' do
    it "should chain as if/else if" do
      result = to_js('case x; in 1; "one"; in 2; "two"; in 3; "three"; end')
      result.must_include 'if ($case1 === 1)'
      result.must_include 'else if ($case1 === 2)'
      result.must_include 'else if ($case1 === 3)'
    end
  end

  describe 'expression context' do
    it "should wrap in IIFE when used as expression" do
      result = to_js('y = case x; in 1; "one"; in 2; "two"; end')
      result.must_include '(() =>'
    end
  end
end
