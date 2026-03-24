require 'minitest/autorun'
require 'ruby2js'
require 'ruby2js/builder'

describe Ruby2JS::Builder::Html do
  include Ruby2JS::Filter::SEXP

  describe 'static tags' do
    it "creates a fully static tag" do
      node = Ruby2JS::Builder::Html.tag(:div, {class: "container"}, s(:str, "hello"))
      _(node.type).must_equal :str
      _(node.children[0]).must_equal '<div class="container">hello</div>'
    end

    it "creates a tag with no attrs" do
      node = Ruby2JS::Builder::Html.tag(:p, {}, s(:str, "text"))
      _(node.type).must_equal :str
      _(node.children[0]).must_equal '<p>text</p>'
    end

    it "creates a tag with no content" do
      node = Ruby2JS::Builder::Html.tag(:div, {class: "empty"})
      _(node.type).must_equal :str
      _(node.children[0]).must_equal '<div class="empty"></div>'
    end

    it "creates a tag with string attr values" do
      node = Ruby2JS::Builder::Html.tag(:a, {class: "btn", href: "/home"}, s(:str, "Home"))
      _(node.type).must_equal :str
      _(node.children[0]).must_equal '<a class="btn" href="/home">Home</a>'
    end
  end

  describe 'dynamic tags' do
    it "creates a tag with dynamic content" do
      node = Ruby2JS::Builder::Html.tag(:span, {}, s(:lvar, :name))
      _(node.type).must_equal :dstr
      # Should contain: "<span>", dynamic content, "</span>"
    end

    it "creates a tag with dynamic attribute" do
      node = Ruby2JS::Builder::Html.tag(:a, {href: s(:lvar, :url)}, s(:str, "click"))
      _(node.type).must_equal :dstr
      # Find the begin node containing the dynamic attr
      has_dynamic = node.children.any? { |c| c.type == :begin }
      _(has_dynamic).must_equal true
    end

    it "creates a tag with mixed static and dynamic attrs" do
      node = Ruby2JS::Builder::Html.tag(:a,
        {class: "link", href: s(:lvar, :url)},
        s(:str, "click"))
      _(node.type).must_equal :dstr
      # Static class should be in the opening string
      first_str = node.children.first.children[0]
      _(first_str).must_include 'class="link"'
    end

    it "preserves attribute order" do
      node = Ruby2JS::Builder::Html.tag(:a,
        {class: "btn", href: "/path", "data-method": "delete"},
        s(:str, "Delete"))
      _(node.type).must_equal :str
      html = node.children[0]
      class_pos = html.index('class=')
      href_pos = html.index('href=')
      data_pos = html.index('data-method=')
      _(class_pos).must_be :<, href_pos
      _(href_pos).must_be :<, data_pos
    end
  end

  describe 'void elements' do
    it "creates a void element" do
      node = Ruby2JS::Builder::Html.void(:br)
      _(node.type).must_equal :str
      _(node.children[0]).must_equal '<br />'
    end

    it "creates a void element with attrs" do
      node = Ruby2JS::Builder::Html.void(:input, {type: "hidden", name: "token", value: "abc"})
      _(node.type).must_equal :str
      _(node.children[0]).must_equal '<input type="hidden" name="token" value="abc" />'
    end

    it "creates a void element with dynamic attr" do
      node = Ruby2JS::Builder::Html.void(:input, {type: "hidden", value: s(:lvar, :token)})
      _(node.type).must_equal :dstr
      has_dynamic = node.children.any? { |c| c.type == :begin }
      _(has_dynamic).must_equal true
    end
  end

  describe 'JavaScript output' do
    def to_js(node)
      Ruby2JS.convert(node, filters: []).to_s
    end

    it "converts static tag to string" do
      node = Ruby2JS::Builder::Html.tag(:p, {}, s(:str, "hello"))
      _(to_js(node)).must_equal '"<p>hello</p>"'
    end

    it "converts dynamic tag to template literal" do
      node = Ruby2JS::Builder::Html.tag(:a, {href: s(:lvar, :url)}, s(:str, "click"))
      js = to_js(node)
      _(js).must_include '`'  # template literal
      _(js).must_include 'url'
      _(js).must_include 'click'
    end
  end
end

describe Ruby2JS::Builder::Member do
  include Ruby2JS::Filter::SEXP

  describe 'getter' do
    it "creates a getter" do
      node = Ruby2JS::Builder::Member.getter(:name, s(:attr, s(:self), :_name))
      _(node.type).must_equal :defget
      _(node.children[0]).must_equal :name
      _(node.children[1].type).must_equal :args
      _(node.children[2].type).must_equal :attr
    end
  end

  describe 'cached_getter' do
    it "creates a getter with cache check" do
      constructor = s(:send, s(:const, nil, :CollectionProxy), :new, s(:self))
      node = Ruby2JS::Builder::Member.cached_getter(:comments, constructor)
      _(node.type).must_equal :defget
      _(node.children[0]).must_equal :comments
      # Body is a begin with if + return
      body = node.children[2]
      _(body.type).must_equal :begin
      # First child: if check for cached value
      _(body.children[0].type).must_equal :if
      # Cache check: this._comments
      _(body.children[0].children[0].type).must_equal :attr
      _(body.children[0].children[0].children[1]).must_equal :_comments
    end
  end

  describe 'setter' do
    it "creates a setter" do
      node = Ruby2JS::Builder::Member.setter(:comments)
      _(node.type).must_equal :def
      _(node.children[0]).must_equal :"comments="
      _(node.children[1].children[0].children[0]).must_equal :value
    end
  end

  describe 'method' do
    it "creates an instance method" do
      body = s(:send, s(:self), :validate)
      node = Ruby2JS::Builder::Member.method(:save, s(:args), body)
      _(node.type).must_equal :def
      _(node.children[0]).must_equal :save
      _(node.children[2]).must_equal body
    end
  end

  describe 'async' do
    it "creates an async method" do
      body = s(:send, nil, :await, s(:send, s(:self), :save))
      node = Ruby2JS::Builder::Member.async(:create, s(:args, s(:arg, :attrs)), body)
      _(node.type).must_equal :async
      _(node.children[0]).must_equal :create
    end
  end

  describe 'accessor' do
    it "creates getter + setter pair" do
      constructor = s(:send, s(:const, nil, :Proxy), :new, s(:self))
      node = Ruby2JS::Builder::Member.accessor(:items, constructor)
      _(node.type).must_equal :begin
      _(node.children.length).must_equal 2
      _(node.children[0].type).must_equal :defget
      _(node.children[1].type).must_equal :def
      _(node.children[1].children[0]).must_equal :"items="
    end
  end

  describe 'JavaScript output' do
    def to_js(node)
      # Wrap in a class to get valid JS for getters/setters
      klass = s(:class, s(:const, nil, :Test), nil, s(:begin, node))
      Ruby2JS.convert(klass, filters: [], eslevel: 2020).to_s
    end

    it "converts cached_getter to JavaScript" do
      constructor = s(:send, s(:const, nil, :Proxy), :new, s(:self))
      node = Ruby2JS::Builder::Member.cached_getter(:items, constructor)
      js = to_js(node)
      _(js).must_include 'get items()'
      _(js).must_include 'this._items'
      _(js).must_include 'return this._items'
    end

    it "converts setter to JavaScript" do
      node = Ruby2JS::Builder::Member.setter(:items)
      js = to_js(node)
      _(js).must_include 'set items(value)'
      _(js).must_include 'this._items = value'
    end

    it "converts accessor to JavaScript" do
      constructor = s(:send, s(:const, nil, :Proxy), :new, s(:self))
      node = Ruby2JS::Builder::Member.accessor(:items, constructor)
      js = to_js(node)
      _(js).must_include 'get items()'
      _(js).must_include 'set items(value)'
    end
  end
end

describe Ruby2JS::Builder::Call do
  include Ruby2JS::Filter::SEXP

  describe 'factory methods' do
    it "creates a call on a receiver" do
      call = Ruby2JS::Builder::Call.on(s(:lvar, :foo), :bar)
      _(call.node.type).must_equal :send
      _(call.node.children[0]).must_equal s(:lvar, :foo)
      _(call.node.children[1]).must_equal :bar
    end

    it "creates a call on self" do
      call = Ruby2JS::Builder::Call.self(:foo)
      _(call.node.type).must_equal :send
      _(call.node.children[0].type).must_equal :self
      _(call.node.children[1]).must_equal :foo
    end

    it "creates a bare function call" do
      call = Ruby2JS::Builder::Call.bare(:foo, s(:int, 1))
      _(call.node.type).must_equal :send
      _(call.node.children[0]).must_be_nil
      _(call.node.children[1]).must_equal :foo
      _(call.node.children[2]).must_equal s(:int, 1)
    end

    it "passes multiple arguments" do
      call = Ruby2JS::Builder::Call.on(nil, :foo, s(:int, 1), s(:str, "bar"))
      _(call.node.children.length).must_equal 4
      _(call.node.children[2]).must_equal s(:int, 1)
      _(call.node.children[3]).must_equal s(:str, "bar")
    end

    it "creates a property access" do
      call = Ruby2JS::Builder::Call.attr(s(:lvar, :foo), :bar)
      _(call.node.type).must_equal :attr
      _(call.node.children[0]).must_equal s(:lvar, :foo)
      _(call.node.children[1]).must_equal :bar
    end

    it "creates a property access on self" do
      call = Ruby2JS::Builder::Call.self_attr(:name)
      _(call.node.type).must_equal :attr
      _(call.node.children[0].type).must_equal :self
      _(call.node.children[1]).must_equal :name
    end
  end

  describe 'chaining' do
    it "chains a method call" do
      call = Ruby2JS::Builder::Call.self(:foo).chain(:bar)
      _(call.node.type).must_equal :send
      _(call.node.children[0].type).must_equal :send
      _(call.node.children[0].children[1]).must_equal :foo
      _(call.node.children[1]).must_equal :bar
    end

    it "chains multiple calls" do
      call = Ruby2JS::Builder::Call.self(:a).chain(:b).chain(:c)
      _(call.node.children[1]).must_equal :c
      _(call.node.children[0].children[1]).must_equal :b
      _(call.node.children[0].children[0].children[1]).must_equal :a
    end

    it "chains with arguments" do
      call = Ruby2JS::Builder::Call.self(:foo).chain(:bar, s(:int, 1))
      _(call.node.children[1]).must_equal :bar
      _(call.node.children[2]).must_equal s(:int, 1)
    end

    it "chains a property access" do
      call = Ruby2JS::Builder::Call.self(:foo).prop(:length)
      _(call.node.type).must_equal :attr
      _(call.node.children[0].type).must_equal :send
      _(call.node.children[1]).must_equal :length
    end
  end

  describe 'await' do
    it "wraps in await" do
      call = Ruby2JS::Builder::Call.self(:save).await
      _(call.node.type).must_equal :send
      _(call.node.children[0]).must_be_nil
      _(call.node.children[1]).must_equal :await
      _(call.node.children[2].type).must_equal :send
    end

    it "chains then awaits" do
      call = Ruby2JS::Builder::Call.on(s(:const, nil, :Article), :find, s(:int, 1)).await
      inner = call.node.children[2]
      _(inner.children[0]).must_equal s(:const, nil, :Article)
      _(inner.children[1]).must_equal :find
    end
  end

  describe 'AST node delegation' do
    it "delegates type" do
      call = Ruby2JS::Builder::Call.self(:foo)
      _(call.type).must_equal :send
    end

    it "delegates children" do
      call = Ruby2JS::Builder::Call.bare(:foo)
      _(call.children[0]).must_be_nil
      _(call.children[1]).must_equal :foo
    end

    it "delegates updated" do
      call = Ruby2JS::Builder::Call.bare(:foo)
      updated = call.updated(nil, [nil, :bar])
      _(updated.type).must_equal :send
      _(updated.children[1]).must_equal :bar
    end
  end

  describe 'JavaScript output' do
    def to_js(node)
      Ruby2JS.convert(node, filters: []).to_s
    end

    it "converts self call to JavaScript" do
      js = to_js(Ruby2JS::Builder::Call.self(:foo).node)
      _(js).must_equal 'this.foo()'
    end

    it "converts chained call to JavaScript" do
      js = to_js(Ruby2JS::Builder::Call.self(:foo).chain(:bar).node)
      _(js).must_equal 'this.foo().bar()'
    end

    it "converts call with args to JavaScript" do
      js = to_js(Ruby2JS::Builder::Call.bare(:foo, s(:int, 1), s(:str, "x")).node)
      _(js).must_equal 'foo(1, "x")'
    end

    it "converts await to JavaScript" do
      js = to_js(Ruby2JS::Builder::Call.self(:save).await.node)
      _(js).must_equal 'await this.save()'
    end

    it "converts property access to JavaScript" do
      js = to_js(Ruby2JS::Builder::Call.self_attr(:name).node)
      _(js).must_equal 'this.name'
    end

    it "converts chained call then property to JavaScript" do
      js = to_js(Ruby2JS::Builder::Call.self(:items).prop(:length).node)
      _(js).must_equal 'this.items().length'
    end
  end
end
