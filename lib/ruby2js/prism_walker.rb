# frozen_string_literal: true

require 'prism' # Pragma: skip
require_relative 'node'

module Ruby2JS
  # Simple location class that mimics Parser::Source::Map interface
  # for the parts Ruby2JS actually uses
  class SimpleLocation
    attr_reader :start_offset, :end_offset, :expression

    def initialize(start_offset:, end_offset:, assignment: nil, end_loc: nil, source: nil, file: nil, source_buffer: nil)
      @start_offset = start_offset
      @end_offset = end_offset
      @assignment = assignment
      @end_loc = end_loc
      # Create expression for comment association and sourcemap generation
      if source_buffer
        @expression = PrismSourceRange.new(source_buffer, start_offset, end_offset)
      elsif source
        buffer = PrismSourceBuffer.new(source, file)
        @expression = PrismSourceRange.new(buffer, start_offset, end_offset)
      end
    end

    # For endless method detection: has assignment (=) but no end keyword
    def assignment
      @assignment
    end

    # For endless method detection: end keyword location (nil for endless)
    def end
      @end_loc
    end

    def respond_to?(method, include_private = false)
      [:start_offset, :end_offset, :assignment, :end, :expression].include?(method) || super
    end
  end

  # Fake source buffer for XStr nodes (used by react filter)
  class FakeSourceBuffer
    attr_reader :source

    def initialize(source)
      @source = source
    end
  end

  # Fake source range for XStr nodes (mimics Parser::Source::Range)
  class FakeSourceRange
    attr_reader :end_pos, :begin_pos, :source_buffer

    def initialize(source_buffer, begin_pos, end_pos)
      @source_buffer = source_buffer
      @begin_pos = begin_pos
      @end_pos = end_pos
    end
  end

  # Location class for XStr nodes that provides full Parser-compatible interface
  # needed by filters like react.rb which access loc.begin.source_buffer.source
  class XStrLocation
    attr_reader :start_offset, :end_offset

    def initialize(source:, start_offset:, end_offset:, opening_end:, closing_start:)
      @source = source
      @start_offset = start_offset
      @end_offset = end_offset
      @opening_end = opening_end
      @closing_start = closing_start
      @source_buffer = FakeSourceBuffer.new(source)
    end

    def begin
      FakeSourceRange.new(@source_buffer, @start_offset, @opening_end)
    end

    def end
      FakeSourceRange.new(@source_buffer, @closing_start, @end_offset)
    end
  end

  # Location class for send/csend nodes that provides Parser-compatible interface
  # for is_method? detection via selector.source_buffer.source[selector.end_pos]
  class SendLocation
    attr_reader :start_offset, :end_offset, :selector, :expression

    def initialize(source:, start_offset:, end_offset:, selector_end_pos:, file: nil, source_buffer: nil)
      @start_offset = start_offset
      @end_offset = end_offset
      @fake_source_buffer = FakeSourceBuffer.new(source)
      @selector = FakeSourceRange.new(@fake_source_buffer, 0, selector_end_pos)
      # Create expression for sourcemap generation
      prism_buffer = source_buffer || PrismSourceBuffer.new(source, file)
      @expression = PrismSourceRange.new(prism_buffer, start_offset, end_offset)
    end

    def respond_to?(method, include_private = false)
      [:start_offset, :end_offset, :selector, :expression].include?(method) || super
    end
  end

  # Location class for def/defs nodes that provides Parser-compatible interface
  # for is_method? detection via name.source_buffer.source[name.end_pos]
  class DefLocation
    attr_reader :start_offset, :end_offset, :name, :assignment, :expression

    def initialize(source:, start_offset:, end_offset:, name_end_pos:, endless: false, file: nil, source_buffer: nil)
      @start_offset = start_offset
      @end_offset = end_offset
      @fake_source_buffer = FakeSourceBuffer.new(source)
      @name = FakeSourceRange.new(@fake_source_buffer, 0, name_end_pos)
      @assignment = endless  # For endless method detection
      @end_loc = endless ? nil : true  # nil means no 'end' keyword (endless)
      # Create expression for sourcemap generation
      prism_buffer = source_buffer || PrismSourceBuffer.new(source, file)
      @expression = PrismSourceRange.new(prism_buffer, start_offset, end_offset)
    end

    # For endless method detection: end keyword location (nil for endless)
    def end
      @end_loc
    end

    def respond_to?(method, include_private = false)
      [:start_offset, :end_offset, :name, :assignment, :end, :expression].include?(method) || super
    end
  end

  # Walker that translates Prism's native AST to Parser-compatible AST nodes.
  # This enables Ruby2JS to work directly with Prism without going through
  # the Prism::Translation::Parser layer.
  class PrismWalker < Prism::Visitor
    attr_reader :source, :file, :source_buffer

    def initialize(source, file = nil)
      super()  # Must be first for JavaScript derived class compatibility
      @source = source
      @file = file
      # Create a shared source buffer for all nodes (ensures == comparison works for comments)
      @source_buffer = PrismSourceBuffer.new(source, file)
    end

    # Create a new AST node
    def s(type, *children)
      Node.new(type, children)
    end

    # Create a new AST node with location from Prism node
    def sl(node, type, *children, endless: false)
      loc = node.location
      location = SimpleLocation.new(
        start_offset: loc.start_offset,
        end_offset: loc.end_offset,
        assignment: endless ? true : nil,  # has = sign for endless methods
        end_loc: endless ? nil : true,     # no end keyword for endless methods
        source_buffer: @source_buffer      # shared buffer for comment association
      )
      Node.new(type, children, location: location)
    end

    # Create a send/csend node with location info for is_method? detection
    def send_node(node, type, *children)
      loc = node.location
      # message_loc points to the method name; if nil (like .() syntax), selector is nil
      # which causes is_method? to return true (matching Parser gem behavior)
      if node.message_loc
        selector_end = node.message_loc.end_offset
        location = SendLocation.new(
          source: @source,
          start_offset: loc.start_offset,
          end_offset: loc.end_offset,
          selector_end_pos: selector_end,
          source_buffer: @source_buffer
        )
      else
        # No message_loc means implicit call (like .() syntax) - always a method call
        # Still need expression for sourcemap
        location = SimpleLocation.new(
          start_offset: loc.start_offset,
          end_offset: loc.end_offset,
          source_buffer: @source_buffer
        )
      end
      Node.new(type, children, location: location)
    end

    # Create a send/csend node for compound assignments (like a.b ||= 1)
    # where the parent node has message_loc for the property access
    def send_with_loc(node, type, *children)
      loc = node.location
      if node.respond_to?(:message_loc) && node.message_loc
        selector_end = node.message_loc.end_offset
        location = SendLocation.new(
          source: @source,
          start_offset: loc.start_offset,
          end_offset: loc.end_offset,
          selector_end_pos: selector_end,
          source_buffer: @source_buffer
        )
      else
        location = SimpleLocation.new(
          start_offset: loc.start_offset,
          end_offset: loc.end_offset,
          source_buffer: @source_buffer
        )
      end
      Node.new(type, children, location: location)
    end

    # Create a def/defs node with location info for is_method? detection
    def def_node(node, type, *children, endless: false)
      loc = node.location
      # name_loc points to the method name; checking char after it detects parens
      name_end = node.name_loc.end_offset
      location = DefLocation.new(
        source: @source,
        start_offset: loc.start_offset,
        end_offset: loc.end_offset,
        name_end_pos: name_end,
        endless: endless,
        source_buffer: @source_buffer
      )
      Node.new(type, children, location: location)
    end

    # Visit a node, returning nil if node is nil
    def visit(node)
      return nil if node.nil?
      super
    end

    # Visit multiple nodes
    def visit_all(nodes)
      return [] if nodes.nil?
      nodes.map { |node| visit(node) }.compact
    end
  end
end

# Load all visitor modules
require_relative 'prism_walker/literals'
require_relative 'prism_walker/variables'
require_relative 'prism_walker/collections'
require_relative 'prism_walker/calls'
require_relative 'prism_walker/blocks'
require_relative 'prism_walker/control_flow'
require_relative 'prism_walker/definitions'
require_relative 'prism_walker/operators'
require_relative 'prism_walker/exceptions'
require_relative 'prism_walker/strings'
require_relative 'prism_walker/regexp'
require_relative 'prism_walker/misc'
