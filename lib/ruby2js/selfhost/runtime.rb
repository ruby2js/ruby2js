# Shared runtime classes for selfhosted Ruby2JS
# These provide Parser-compatible source location tracking for the JS environment.
#
# Note: This file is "Ruby-syntax JavaScript" - it's designed to be transpiled
# to JavaScript, not to run in Ruby. The transpiled output provides the runtime
# support needed by the selfhosted converter.

import "*", as: Prism, from: '@ruby/prism'

export [Prism]

# ============================================================================
# Source Location Classes (Prism-independent)
# ============================================================================

# PrismSourceBuffer - provides source buffer for location tracking
export class PrismSourceBuffer
  def initialize(source, file)
    @source = source
    @name = file || '(eval)'
    # Build line offsets for line/column calculation
    @lineOffsets = [0]
    i = 0
    while i < source.length
      @lineOffsets.push(i + 1) if source[i] == "\n"
      i += 1
    end
  end

  attr_reader :source, :name

  def lineForPosition(pos)
    idx = @lineOffsets.findIndex { |offset| offset > pos }
    idx == -1 ? @lineOffsets.length : idx
  end

  def columnForPosition(pos)
    lineIdx = @lineOffsets.findIndex { |offset| offset > pos }
    lineIdx = @lineOffsets.length if lineIdx == -1
    pos - @lineOffsets[lineIdx - 1]
  end
end

# PrismSourceRange - provides source range for location tracking
export class PrismSourceRange
  def initialize(sourceBuffer, beginPos, endPos)
    @source_buffer = sourceBuffer
    @begin_pos = beginPos
    @end_pos = endPos
  end

  attr_reader :source_buffer, :begin_pos, :end_pos

  def source
    @source_buffer.source[@begin_pos...@end_pos]
  end

  def line
    @source_buffer.lineForPosition(@begin_pos)
  end

  def column
    @source_buffer.columnForPosition(@begin_pos)
  end
end

# Hash class placeholder - used for instanceof checks
export class Hash
end

# ============================================================================
# Comment Handling
# ============================================================================

# PrismComment wrapper - provides interface expected by converter
export class PrismComment
  def initialize(prismComment, source, sourceBuffer)
    start = prismComment.location.startOffset
    end_ = start + prismComment.location.length
    @text = source[start...end_]

    @location = {
      startOffset: start,
      endOffset: end_,
      end_offset: end_
    }

    @loc = {
      start_offset: start,
      expression: {
        source_buffer: sourceBuffer,
        begin_pos: start,
        end_pos: end_
      }
    }
  end

  attr_reader :text, :location, :loc
end

# CommentsMap - alias for Map (object key support)
CommentsMap = Map

export [CommentsMap]

# Associate comments with AST nodes based on position
export associateComments = ->(ast, comments) do
  result = CommentsMap.new
  return result if comments.nil? || comments.length == 0 || ast.nil?

  nodes_by_pos = []

  collect_nodes = ->(node, depth) do
    return unless node && node.loc
    start_pos = node.loc.start_offset

    if start_pos && node.type != :begin
      nodes_by_pos.push([start_pos, depth, node])
    end

    if node.children
      node.children.each do |child|
        collect_nodes(child, depth + 1) if child&.type
      end
    end
  end

  collect_nodes(ast, 0)

  nodes_by_pos.sort! do |a, b|
    cmp = a[0] - b[0]
    cmp != 0 ? cmp : a[1] - b[1]
  end

  comments.each do |comment|
    comment_end = comment.location.end_offset
    candidate = nodes_by_pos.find { |item| item[0] >= comment_end }
    next unless candidate
    node = candidate[2]
    result.set(node, []) unless result.has(node)
    result.get(node).push(comment)
  end

  result
end

# Set up globals for modules that expect them
export setupGlobals = ->() do
  globalThis.Prism = Prism
  globalThis.PrismSourceBuffer = PrismSourceBuffer
  globalThis.PrismSourceRange = PrismSourceRange
  globalThis.Hash = Hash
  globalThis.RUBY_VERSION = "3.4.0"
  globalThis.RUBY2JS_PARSER = "prism"
end

# Initialize Prism WASM parser
prismParse_ = nil # Pragma: let prismParse = null

export async def initPrism
  prismParse_ ||= await Prism.loadPrism()
  prismParse_
end

export def getPrismParse
  prismParse_
end
