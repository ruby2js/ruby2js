require 'minitest/autorun'
require 'ruby2js'

describe 'pnode tests' do
  # Helper to convert an AST node directly
  def convert_ast(ast)
    comments = {}
    converter = Ruby2JS::Converter.new(ast, comments, {})
    converter.convert
    converter.to_s
  end

  # Helper to create AST nodes - use appropriate class based on parser
  def s(type, *children)
    if RUBY2JS_PARSER == :prism
      Ruby2JS::Node.new(type, children)
    else
      Parser::AST::Node.new(type, children)
    end
  end

  describe 'pnode HTML elements' do
    it 'should handle simple element without attributes' do
      # s(:pnode, :div, s(:hash))
      ast = s(:pnode, :div, s(:hash))
      result = convert_ast(ast)
      _(result).must_include '<div'
      _(result).must_include '</div>'
    end

    it 'should handle element with static attributes' do
      # s(:pnode, :div, s(:hash, s(:pair, s(:sym, :class), s(:str, "card"))))
      ast = s(:pnode, :div, s(:hash, s(:pair, s(:sym, :class), s(:str, "card"))))
      result = convert_ast(ast)
      _(result).must_include '<div'
      _(result).must_include 'class='
      _(result).must_include 'card'
    end

    it 'should handle element with children' do
      # s(:pnode, :div, s(:hash), s(:pnode, :span, s(:hash)))
      ast = s(:pnode, :div, s(:hash),
        s(:pnode, :span, s(:hash)))
      result = convert_ast(ast)
      _(result).must_include '<div>'
      _(result).must_include '<span'
      _(result).must_include '</div>'
    end

    it 'should handle void elements' do
      ast = s(:pnode, :br, s(:hash))
      result = convert_ast(ast)
      _(result).must_include '<br>'
      # Void elements don't have closing tags
      _(result).wont_include '</br>'
    end
  end

  describe 'pnode components' do
    it 'should output component render call for uppercase tags' do
      ast = s(:pnode, :Card, s(:hash))
      result = convert_ast(ast)
      _(result).must_include 'Card'
      _(result).must_include '.render('
    end

    it 'should handle component with props' do
      ast = s(:pnode, :Button, s(:hash, s(:pair, s(:sym, :onClick), s(:lvar, :handler))))
      result = convert_ast(ast)
      _(result).must_include 'Button'
      _(result).must_include 'onClick'
    end
  end

  describe 'pnode custom elements' do
    it 'should handle custom elements (string tags)' do
      ast = s(:pnode, "my-widget", s(:hash))
      result = convert_ast(ast)
      _(result).must_include '<my-widget'
      _(result).must_include '</my-widget>'
    end

    it 'should handle custom element with attributes' do
      ast = s(:pnode, "my-element", s(:hash, s(:pair, s(:sym, :data_id), s(:str, "123"))))
      result = convert_ast(ast)
      _(result).must_include '<my-element'
      _(result).must_include 'data-id'  # underscore converted to dash
      _(result).must_include '123'
    end
  end

  describe 'pnode fragments' do
    it 'should handle fragments (nil tag) by outputting children' do
      ast = s(:pnode, nil, s(:hash),
        s(:pnode, :h1, s(:hash)),
        s(:pnode, :h2, s(:hash)))
      result = convert_ast(ast)
      _(result).must_include '<h1'
      _(result).must_include '<h2'
      # Fragment itself produces no wrapper
      _(result).wont_include '<nil'
    end
  end

  describe 'pnode_text' do
    it 'should handle static text' do
      ast = s(:pnode_text, s(:str, "Hello World"))
      result = convert_ast(ast)
      _(result).must_equal 'Hello World'
    end

    it 'should handle dynamic content with String wrapper' do
      ast = s(:pnode_text, s(:lvar, :name))
      result = convert_ast(ast)
      _(result).must_include 'String('
      _(result).must_include 'name'
    end

    it 'should work within pnode' do
      ast = s(:pnode, :p, s(:hash),
        s(:pnode_text, s(:str, "Hello")))
      result = convert_ast(ast)
      _(result).must_include '<p>'
      _(result).must_include 'Hello'
      _(result).must_include '</p>'
    end
  end

  describe 'nested structures' do
    it 'should handle deeply nested elements' do
      ast = s(:pnode, :div, s(:hash),
        s(:pnode, :ul, s(:hash),
          s(:pnode, :li, s(:hash),
            s(:pnode_text, s(:str, "Item 1"))),
          s(:pnode, :li, s(:hash),
            s(:pnode_text, s(:str, "Item 2")))))
      result = convert_ast(ast)
      _(result).must_include '<div>'
      _(result).must_include '<ul>'
      _(result).must_include '<li>'
      _(result).must_include 'Item 1'
      _(result).must_include 'Item 2'
      _(result).must_include '</li>'
      _(result).must_include '</ul>'
      _(result).must_include '</div>'
    end

    it 'should handle mixed static and dynamic content' do
      ast = s(:pnode, :div, s(:hash),
        s(:pnode_text, s(:str, "Hello ")),
        s(:pnode_text, s(:lvar, :name)),
        s(:pnode_text, s(:str, "!")))
      result = convert_ast(ast)
      _(result).must_include 'Hello '
      _(result).must_include 'name'
      _(result).must_include '!'
    end
  end
end
