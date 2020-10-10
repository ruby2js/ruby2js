gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/nokogiri'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Nokogiri do
  
  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Nokogiri]).to_s)
  end
  
  def to_js_esm( string)
    _(Ruby2JS.convert(string,
      filters: [Ruby2JS::Filter::Nokogiri, Ruby2JS::Filter::ESM]).to_s)
  end
  
  describe 'parse' do
    it 'should support nokogiri parse' do
      to_js( 'Nokogiri::HTML.parse "<b>"' ).
        must_equal 'var JSDOM = require("jsdom").JSDOM; ' +
        'new JSDOM("<b>").window.document'

      to_js( 'Nokogiri::HTML "<b>"' ).
        must_equal 'var JSDOM = require("jsdom").JSDOM; ' +
        'new JSDOM("<b>").window.document'

      to_js( 'Nokogiri::HTML5.parse "<b>"' ).
        must_equal 'var JSDOM = require("jsdom").JSDOM; ' +
        'new JSDOM("<b>").window.document'

      to_js( 'Nokogiri::HTML5 "<b>"' ).
        must_equal 'var JSDOM = require("jsdom").JSDOM; ' +
        'new JSDOM("<b>").window.document'
    end
  end

  describe 'query' do
    it 'should support search' do
      to_js('doc.search("tr")').must_equal 'doc.querySelectorAll("tr")'
    end
    
    it 'should support at' do
      to_js('doc.at("tr")').must_equal 'doc.querySelector("tr")'
    end
  end

  describe 'construction' do
    it 'should create an node' do
      to_js( 'Nokogiri::XML::Node.new "a", doc' ).
        must_equal 'doc.createElement("a")'
    end

    it 'should create an element' do
      to_js( 'doc.create_element "a"' ).
        must_equal 'doc.createElement("a")'
      to_js( 'doc.create_element "a", "text", href: ".."' ).
        must_equal '(function() {var $_ = doc.createElement("a"); ' +
          '$_.content = "text"; $_.setAttribute("href", ".."); return $_})()'
    end
  end

  describe 'navigation' do
    it 'should handle parent' do
      to_js( 'node.parent' ).must_equal 'node.parentNode'
    end

    it 'should handle children' do
      to_js( 'node.children' ).must_equal 'node.childNodes'
    end

    it 'should handle next sibling' do
      to_js( 'node.next' ).must_equal 'node.nextSibling'
      to_js( 'node.next_sibling' ).must_equal 'node.nextSibling'
    end

    it 'should handle next element' do
      to_js( 'node.next_element' ).must_equal 'node.nextElement'
    end

    it 'should handle previous sibling' do
      to_js( 'node.previous' ).must_equal 'node.previousSibling'
      to_js( 'node.previous_sibling' ).must_equal 'node.previousSibling'
    end

    it 'should handle previous element' do
      to_js( 'node.previous_element' ).must_equal 'node.previousElement'
    end

    it 'should handle document' do
      to_js( 'node.document' ).must_equal 'node.ownerDocument'
    end

    it 'should handle root' do
      to_js( 'doc.root' ).must_equal 'doc.documentElement'
    end
  end

  describe 'node type' do
    it 'should check for cdata' do
      to_js( 'node.cdata?' ).
        must_equal 'node.nodeType === Node.CDATA_SECTION_NODE'
    end

    it 'should check for comment' do
      to_js( 'node.comment?' ).must_equal 'node.nodeType === Node.COMMENT_NODE'
    end

    it 'should check for element' do
      to_js( 'node.element?' ).must_equal 'node.nodeType === Node.ELEMENT_NODE'
    end

    it 'should check for fragment' do
      to_js( 'node.fragment?' ).
        must_equal 'node.nodeType === Node.DOCUMENT_FRAGMENT_NODE'
    end

    it 'should check for processing instruction' do
      to_js( 'node.processing_instruction?' ).
        must_equal 'node.nodeType === Node.PROCESSING_INSTRUCTION_NODE'
    end

    it 'should check for text' do
      to_js( 'node.text?' ).must_equal 'node.nodeType === Node.TEXT_NODE'
    end
  end

  describe 'properties' do
    it 'should handle name' do
      to_js( 'node.name' ).must_equal 'node.nodeName'
    end

    it 'should handle content' do
      to_js( 'node.content' ).must_equal 'node.textContent'
      to_js( 'node.text' ).must_equal 'node.textContent'
    end

    it 'should handle content=' do
      to_js( 'node.content = "foo"' ).must_equal 'node.textContent = "foo"'
    end

    it 'should handle inner_html' do
      to_js( 'node.inner_html' ).must_equal 'node.innerHTML'
    end

    it 'should handle inner_html=' do
      to_js( 'node.inner_html = "foo"' ).must_equal 'node.innerHTML = "foo"'
    end

    it 'should handle to_html' do
      to_js( 'node.to_html' ).must_equal 'node.outerHTML'
    end

    it 'should handle getting an attribute node' do
      to_js( 'node.attribute("href")' ).
        must_equal 'node.getAttributeNode("href")'
    end

    it 'should handle getting an attribute value' do
      to_js( 'node.attr("href")' ).must_equal 'node.getAttribute("href")'
      to_js( 'node.get_attribute("href")' ).
        must_equal 'node.getAttribute("href")'
    end

    it 'should handle checking to see if an attribute exists' do
      to_js( 'node.key?("href")' ).must_equal 'node.hasAttribute("href")'
      to_js( 'node.has_attribute("href")' ).
        must_equal 'node.hasAttribute("href")'
    end

    it 'should handle set_attribute' do
      to_js( 'node.set_attribute("href", link)' ).
        must_equal 'node.setAttribute("href", link)'
    end

    it 'should handle remove_attribute' do
      to_js( 'node.remove_attribute("href")' ).
        must_equal 'node.removeAttribute("href")'
    end
  end

  describe 'tree manipulation' do
    it 'should add a child' do
      to_js( 'node.add_child child' ).must_equal 'node.appendChild(child)'
    end

    it 'should add a previous sibling' do
      to_js( 'node.add_previous_sibling sibling' ).
        must_equal 'node.parentNode.insertBefore(sibling, node)'
      to_js( 'node.before sibling' ).
        must_equal 'node.parentNode.insertBefore(sibling, node)'
      to_js( 'node.previous=sibling' ).
        must_equal 'node.parentNode.insertBefore(sibling, node)'
    end

    it 'should add a next sibling' do
      to_js( 'node.add_next_sibling sibling' ).
        must_equal 'node.parentNode.insertBefore(sibling, node.nextSibling)'
      to_js( 'node.after sibling' ).
        must_equal 'node.parentNode.insertBefore(sibling, node.nextSibling)'
      to_js( 'node.next = sibling' ).
        must_equal 'node.parentNode.insertBefore(sibling, node.nextSibling)'
    end
  end

  describe 'nokogiri related requires' do
    it 'should eat nokogiri requires' do
      to_js( 'require "nokogiri"' ).must_equal ''
    end

    it 'should eat nokogumbo requires' do
      to_js( 'require "nokogumbo"' ).must_equal ''
    end
  end

  describe 'esm' do
    it 'should support JSDOM import' do
      to_js_esm( 'Nokogiri::HTML.parse "<b>"' ).
        must_equal 'import { JSDOM } from "jsdom"; ' +
        'new JSDOM("<b>").window.document'
    end
  end
  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Nokogiri" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Nokogiri
    end
  end
end
