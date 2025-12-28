---
order: 18
title: Jest
top_section: Filters
category: jest
---

The **Jest** filter enables you to write tests using RSpec-like Ruby syntax that compiles to Jest or Vitest. Since Jest and Vitest share the same API, tests written with this filter work with both frameworks.

## Basic Structure

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["jest", "functions"]
}'></div>

```ruby
describe "Calculator" do
  before do
    @calc = Calculator.new
  end

  it "adds two numbers" do
    expect(@calc.add(2, 3)).to eq(5)
  end

  it "subtracts two numbers" do
    expect(@calc.subtract(5, 3)).to eq(2)
  end
end
```

## Describe and Context Blocks

Both `describe` and `context` map to Jest's `describe()`:

```ruby
describe "User" do
  context "when logged in" do
    it "shows dashboard" do
      # ...
    end
  end
end
```

## Test Blocks

- `it "description"` → `it("description", () => {})`
- `specify "description"` → `test("description", () => {})`
- `test "description"` → `test("description", () => {})`

## Hooks

| Ruby                | Jest                   |
| ------------------- | ---------------------- |
| `before { }`        | `beforeEach(() => {})` |
| `before(:each) { }` | `beforeEach(() => {})` |
| `before(:all) { }`  | `beforeAll(() => {})`  |
| `after { }`         | `afterEach(() => {})`  |
| `after(:each) { }`  | `afterEach(() => {})`  |
| `after(:all) { }`   | `afterAll(() => {})`   |

## Matchers

### Equality

```ruby
expect(x).to eq(5)        # expect(x).toBe(5) for primitives
expect(x).to eq(obj)      # expect(x).toEqual(obj) for objects
expect(x).to equal(obj)   # expect(x).toBe(obj) - identity check
expect(x).not_to eq(5)    # expect(x).not.toBe(5)
expect(x).to_not eq(5)    # expect(x).not.toBe(5)
```

### Truthiness

```ruby
expect(x).to be_truthy      # expect(x).toBeTruthy()
expect(x).to be_falsy       # expect(x).toBeFalsy()
expect(x).to be_nil         # expect(x).toBeNull()
expect(x).to be_undefined   # expect(x).toBeUndefined()
expect(x).to be_defined     # expect(x).toBeDefined()
expect(x).to be_nan         # expect(x).toBeNaN()
```

### Comparisons

```ruby
expect(x).to be_greater_than(5)              # expect(x).toBeGreaterThan(5)
expect(x).to be_greater_than_or_equal_to(5)  # expect(x).toBeGreaterThanOrEqual(5)
expect(x).to be_less_than(5)                 # expect(x).toBeLessThan(5)
expect(x).to be_less_than_or_equal_to(5)     # expect(x).toBeLessThanOrEqual(5)
# Shortcuts
expect(x).to be_gt(5)   # toBeGreaterThan
expect(x).to be_gte(5)  # toBeGreaterThanOrEqual
expect(x).to be_lt(5)   # toBeLessThan
expect(x).to be_lte(5)  # toBeLessThanOrEqual
```

### Collections

```ruby
expect(arr).to include(item)     # expect(arr).toContain(item)
expect(arr).to have_length(3)    # expect(arr).toHaveLength(3)
expect(obj).to have_key(:foo)    # expect(obj).toHaveProperty("foo")
```

### Strings

```ruby
expect(str).to match(/pattern/)  # expect(str).toMatch(/pattern/)
expect(str).to start_with("Hi")  # expect(str).toMatch(/^Hi/)
expect(str).to end_with("!")     # expect(str).toMatch(/!$/)
```

### Types

```ruby
expect(x).to be_a(Array)          # expect(x).toBeInstanceOf(Array)
expect(x).to be_kind_of(String)   # expect(x).toBeInstanceOf(String)
expect(x).to be_instance_of(Date) # expect(x).toBeInstanceOf(Date)
```

### Exceptions

```ruby
expect(fn).to raise_error              # expect(fn).toThrow()
expect(fn).to raise_error(TypeError)   # expect(fn).toThrow(TypeError)
```

### Mocks

```ruby
expect(mock).to have_been_called                  # expect(mock).toHaveBeenCalled()
expect(mock).to have_been_called_with(1, 2)       # expect(mock).toHaveBeenCalledWith(1, 2)
expect(mock).to have_been_called_times(3)         # expect(mock).toHaveBeenCalledTimes(3)
```

## Complete Example

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["jest", "esm", "functions"]
}'></div>

```ruby
describe "Array" do
  before(:all) do
    @shared_data = [1, 2, 3]
  end

  describe "#push" do
    before do
      @arr = []
    end

    it "adds an element to the end" do
      @arr.push(1)
      expect(@arr).to have_length(1)
      expect(@arr).to include(1)
    end

    it "returns the new length" do
      result = @arr.push(1)
      expect(result).to eq(1)
    end
  end

  describe "#pop" do
    it "removes the last element" do
      arr = [1, 2, 3]
      arr.pop()
      expect(arr).to eq([1, 2])
    end

    it "returns the removed element" do
      arr = [1, 2, 3]
      expect(arr.pop()).to eq(3)
    end
  end
end
```

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/jest_spec.rb).
{% endrendercontent %}
