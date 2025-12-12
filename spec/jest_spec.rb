require 'minitest/autorun'
require 'ruby2js/filter/jest'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Jest do
  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Jest]).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Jest, Ruby2JS::Filter::Functions]).to_s)
  end

  describe "describe blocks" do
    it "should convert describe blocks" do
      to_js('describe "Math" do; end').must_include 'describe("Math", () => {})'
    end

    it "should convert context blocks to describe" do
      to_js('context "when positive" do; end').must_include 'describe("when positive", () => {})'
    end

    it "should handle nested describe blocks" do
      result = to_js('describe "Outer" do; describe "Inner" do; end; end')
      result.must_include 'describe("Outer"'
      result.must_include 'describe("Inner"'
    end
  end

  describe "test blocks" do
    it "should convert it blocks" do
      to_js('describe "Math" do; it "adds numbers" do; end; end').
        must_include 'it("adds numbers", () => {})'
    end

    it "should convert specify blocks to test" do
      to_js('describe "Math" do; specify "adds numbers" do; end; end').
        must_include 'test("adds numbers", () => {})'
    end

    it "should convert test blocks" do
      to_js('describe "Math" do; test "addition" do; end; end').
        must_include 'test("addition", () => {})'
    end
  end

  describe "hooks" do
    it "should convert before to beforeEach" do
      to_js('describe "Test" do; before do; setup(); end; end').
        must_include 'beforeEach(() => setup())'
    end

    it "should convert before(:each) to beforeEach" do
      to_js('describe "Test" do; before(:each) do; setup(); end; end').
        must_include 'beforeEach(() => setup())'
    end

    it "should convert before(:all) to beforeAll" do
      to_js('describe "Test" do; before(:all) do; setup(); end; end').
        must_include 'beforeAll(() => setup())'
    end

    it "should convert after to afterEach" do
      to_js('describe "Test" do; after do; cleanup(); end; end').
        must_include 'afterEach(() => cleanup())'
    end

    it "should convert after(:all) to afterAll" do
      to_js('describe "Test" do; after(:all) do; cleanup(); end; end').
        must_include 'afterAll(() => cleanup())'
    end
  end

  describe "equality matchers" do
    it "should convert eq to toBe for primitives" do
      to_js('describe "x" do; it "y" do; expect(x).to eq(1); end; end').
        must_include 'expect(x).toBe(1)'
    end

    it "should convert eq to toEqual for non-primitives" do
      to_js('describe "x" do; it "y" do; expect(x).to eq(y); end; end').
        must_include 'expect(x).toEqual(y)'
    end

    it "should convert equal to toBe" do
      to_js('describe "x" do; it "y" do; expect(x).to equal(obj); end; end').
        must_include 'expect(x).toBe(obj)'
    end

    it "should handle not_to" do
      to_js('describe "x" do; it "y" do; expect(x).not_to eq(1); end; end').
        must_include 'expect(x).not.toBe(1)'
    end

    it "should handle to_not" do
      to_js('describe "x" do; it "y" do; expect(x).to_not eq(1); end; end').
        must_include 'expect(x).not.toBe(1)'
    end
  end

  describe "truthiness matchers" do
    it "should convert be_truthy to toBeTruthy" do
      to_js('describe "x" do; it "y" do; expect(x).to be_truthy; end; end').
        must_include 'expect(x).toBeTruthy()'
    end

    it "should convert be_falsy to toBeFalsy" do
      to_js('describe "x" do; it "y" do; expect(x).to be_falsy; end; end').
        must_include 'expect(x).toBeFalsy()'
    end

    it "should convert be_nil to toBeNull" do
      to_js('describe "x" do; it "y" do; expect(x).to be_nil; end; end').
        must_include 'expect(x).toBeNull()'
    end

    it "should convert be_undefined to toBeUndefined" do
      to_js('describe "x" do; it "y" do; expect(x).to be_undefined; end; end').
        must_include 'expect(x).toBeUndefined()'
    end

    it "should convert be_defined to toBeDefined" do
      to_js('describe "x" do; it "y" do; expect(x).to be_defined; end; end').
        must_include 'expect(x).toBeDefined()'
    end
  end

  describe "collection matchers" do
    it "should convert include to toContain" do
      to_js('describe "x" do; it "y" do; expect(arr).to include(1); end; end').
        must_include 'expect(arr).toContain(1)'
    end

    it "should convert have_length to toHaveLength" do
      to_js('describe "x" do; it "y" do; expect(arr).to have_length(3); end; end').
        must_include 'expect(arr).toHaveLength(3)'
    end

    it "should convert have_key to toHaveProperty" do
      to_js('describe "x" do; it "y" do; expect(obj).to have_key(:foo); end; end').
        must_include 'expect(obj).toHaveProperty("foo")'
    end
  end

  describe "string matchers" do
    it "should convert match to toMatch" do
      to_js('describe "x" do; it "y" do; expect(str).to match(/foo/); end; end').
        must_include 'expect(str).toMatch(/foo/)'
    end
  end

  describe "comparison matchers" do
    it "should convert be_greater_than to toBeGreaterThan" do
      to_js('describe "x" do; it "y" do; expect(x).to be_greater_than(5); end; end').
        must_include 'expect(x).toBeGreaterThan(5)'
    end

    it "should convert be_less_than to toBeLessThan" do
      to_js('describe "x" do; it "y" do; expect(x).to be_less_than(5); end; end').
        must_include 'expect(x).toBeLessThan(5)'
    end

    it "should convert be_gte to toBeGreaterThanOrEqual" do
      to_js('describe "x" do; it "y" do; expect(x).to be_gte(5); end; end').
        must_include 'expect(x).toBeGreaterThanOrEqual(5)'
    end

    it "should convert be_lte to toBeLessThanOrEqual" do
      to_js('describe "x" do; it "y" do; expect(x).to be_lte(5); end; end').
        must_include 'expect(x).toBeLessThanOrEqual(5)'
    end
  end

  describe "type matchers" do
    it "should convert be_a to toBeInstanceOf" do
      to_js('describe "x" do; it "y" do; expect(x).to be_a(Array); end; end').
        must_include 'expect(x).toBeInstanceOf(Array)'
    end

    it "should convert be_kind_of to toBeInstanceOf" do
      to_js('describe "x" do; it "y" do; expect(x).to be_kind_of(String); end; end').
        must_include 'expect(x).toBeInstanceOf(String)'
    end
  end

  describe "exception matchers" do
    it "should convert raise_error to toThrow" do
      to_js('describe "x" do; it "y" do; expect(fn).to raise_error; end; end').
        must_include 'expect(fn).toThrow()'
    end

    it "should convert raise_error with type to toThrow" do
      to_js('describe "x" do; it "y" do; expect(fn).to raise_error(TypeError); end; end').
        must_include 'expect(fn).toThrow(TypeError)'
    end
  end

  describe "mock matchers" do
    it "should convert have_been_called to toHaveBeenCalled" do
      to_js('describe "x" do; it "y" do; expect(mock).to have_been_called; end; end').
        must_include 'expect(mock).toHaveBeenCalled()'
    end

    it "should convert have_been_called_with to toHaveBeenCalledWith" do
      to_js('describe "x" do; it "y" do; expect(mock).to have_been_called_with(1, 2); end; end').
        must_include 'expect(mock).toHaveBeenCalledWith(1, 2)'
    end

    it "should convert have_been_called_times to toHaveBeenCalledTimes" do
      to_js('describe "x" do; it "y" do; expect(mock).to have_been_called_times(3); end; end').
        must_include 'expect(mock).toHaveBeenCalledTimes(3)'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Jest" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Jest
    end
  end
end
