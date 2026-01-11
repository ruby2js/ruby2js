require 'minitest/autorun'
require 'ruby2js/rbx'
require 'ruby2js/filter/react'

describe "Ruby2JS.rbx2_js" do
  def to_js(string)
    _(Ruby2JS.rbx2_js(string))
  end

  describe "basic elements" do
    it "should handle simple text" do
      to_js('<div>Hello</div>').must_equal(
        'React.createElement("div", null, "Hello")')
    end

    it "should handle self-closing elements" do
      to_js('<br/>').must_equal('React.createElement("br", null)')
    end

    it "should handle nested elements" do
      to_js('<div><span>Text</span></div>').must_equal(
        'React.createElement("div", null, React.createElement("span", null, "Text"))')
    end

    it "should handle multiple children" do
      to_js('<div><p>One</p><p>Two</p></div>').must_equal(
        'React.createElement("div", null, React.createElement("p", null, "One"), React.createElement("p", null, "Two"))')
    end
  end

  describe "attributes" do
    it "should handle string attributes" do
      to_js('<div className="card">Hi</div>').must_equal(
        'React.createElement("div", {className: "card"}, "Hi")')
    end

    it "should handle expression attributes" do
      to_js('<img src={url} />').must_equal(
        'React.createElement("img", {src: url})')
    end

    it "should handle boolean attributes" do
      to_js('<button disabled>Click</button>').must_equal(
        'React.createElement("button", {disabled: true}, "Click")')
    end

    it "should handle event handlers" do
      to_js('<button onClick={handleClick}>Click</button>').must_equal(
        'React.createElement("button", {onClick: handleClick}, "Click")')
    end

    it "should convert class to className" do
      to_js('<div class="foo">Hi</div>').must_equal(
        'React.createElement("div", {className: "foo"}, "Hi")')
    end

    it "should convert kebab-case to camelCase" do
      to_js('<div data-id="1" aria-label="test">Hi</div>').must_equal(
        'React.createElement("div", {dataId: "1", ariaLabel: "test"}, "Hi")')
    end
  end

  describe "expressions" do
    it "should preserve variable references" do
      to_js('<div>{name}</div>').must_equal(
        'React.createElement("div", null, name)')
    end

    it "should preserve complex expressions" do
      to_js('<div>{a + b}</div>').must_equal(
        'React.createElement("div", null, a + b)')
    end

    it "should preserve ternary expressions" do
      to_js('<div>{active ? "Yes" : "No"}</div>').must_equal(
        'React.createElement("div", null, active ? "Yes" : "No")')
    end

    it "should preserve template literals" do
      to_js('<div>{`Hello ${name}`}</div>').must_equal(
        'React.createElement("div", null, `Hello ${name}`)')
    end

    it "should handle nested JSX in expressions" do
      to_js('<ul>{items.map(i => <li>{i}</li>)}</ul>').must_equal(
        'React.createElement("ul", null, items.map(i => React.createElement("li", null, i)))')
    end

    it "should handle nested JSX with attributes" do
      to_js('<ul>{items.map(i => <li key={i.id}>{i.name}</li>)}</ul>').must_equal(
        'React.createElement("ul", null, items.map(i => React.createElement("li", {key: i.id}, i.name)))')
    end
  end

  describe "components" do
    it "should handle component references" do
      to_js('<MyComponent />').must_equal(
        'React.createElement(MyComponent, null)')
    end

    it "should handle components with props" do
      to_js('<MyComponent name={value} />').must_equal(
        'React.createElement(MyComponent, {name: value})')
    end
  end

  describe "fragments" do
    it "should handle empty fragment syntax" do
      to_js('<>Content</>').must_equal(
        'React.createElement(React.Fragment, null, "Content")')
    end

    it "should handle fragments with multiple children" do
      to_js('<><h1>Title</h1><p>Text</p></>').must_equal(
        'React.createElement(React.Fragment, null, React.createElement("h1", null, "Title"), React.createElement("p", null, "Text"))')
    end
  end

  describe "Preact support" do
    it "should use Preact when specified" do
      _(Ruby2JS.rbx2_js('<div>Hi</div>', react_name: 'Preact')).must_equal(
        'Preact.createElement("div", null, "Hi")')
    end
  end

  describe "multiline JSX" do
    it "should handle multiline input" do
      jsx = <<~JSX
        <div className="card">
          <h1>{title}</h1>
          <p>{content}</p>
        </div>
      JSX
      result = Ruby2JS.rbx2_js(jsx)
      _(result).must_include('React.createElement("div", {className: "card"}')
      _(result).must_include('React.createElement("h1", null, title)')
      _(result).must_include('React.createElement("p", null, content)')
    end
  end
end

describe "React filter with RBX mode" do
  def to_js(string, options = {})
    _(Ruby2JS.convert(string,
      filters: [Ruby2JS::Filter::React],
      eslevel: 2022,
      rbx: true,
      **options).to_s)
  end

  it "should preserve variable references in JSX" do
    result = to_js('def Greeting(name:); %x{<h1>{name}</h1>}; end')
    result.must_include('React.createElement("h1", null, name)')
  end

  it "should handle function components with multiple props" do
    result = to_js('def Card(title:, content:); %x{<div><h1>{title}</h1><p>{content}</p></div>}; end')
    result.must_include('function Card({ title, content })')
    result.must_include('title')
    result.must_include('content')
  end
end
