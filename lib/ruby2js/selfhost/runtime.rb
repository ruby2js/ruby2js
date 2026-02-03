# Shared runtime classes for selfhosted Ruby2JS
# These provide Parser-compatible source location tracking for the JS environment.
#
# Note: This file is "Ruby-syntax JavaScript" - it's designed to be transpiled
# to JavaScript, not to run in Ruby. The transpiled output provides the runtime
# support needed by the selfhosted converter.

# Conditionally load Prism based on environment:
# - Browser: use prism_browser.js (fetch + WASI polyfill)
# - Node.js: use @ruby/prism (native WASI)
Prism = if typeof(window) != 'undefined'
  await import('./prism_browser.js')
else
  await import('@ruby/prism')
end

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
    # Build byte-to-char offset map for multi-byte UTF-8 sources.
    # Prism reports byte offsets but JS strings use char indices.
    @byteToChar = nil
    byteIdx = 0
    charIdx = 0
    while charIdx < source.length
      code = source.charCodeAt(charIdx)
      if code < 0x80
        byteIdx += 1
      elsif code < 0x800
        byteIdx += 2
      elsif code >= 0xD800 && code <= 0xDBFF
        byteIdx += 4
        charIdx += 1
      else
        byteIdx += 3
      end
      charIdx += 1
    end
    if byteIdx != source.length
      @byteToChar = Array.new(byteIdx + 1)
      byteIdx = 0
      charIdx = 0
      while charIdx < source.length
        @byteToChar[byteIdx] = charIdx
        code = source.charCodeAt(charIdx)
        if code < 0x80
          byteIdx += 1
        elsif code < 0x800
          byteIdx += 2
        elsif code >= 0xD800 && code <= 0xDBFF
          byteIdx += 4
          charIdx += 1
        else
          byteIdx += 3
        end
        charIdx += 1
      end
      @byteToChar[byteIdx] = charIdx
    end
  end

  attr_reader :source, :name

  # Convert a byte offset to a character index
  def byteToCharOffset(byteOffset)
    return byteOffset unless @byteToChar
    @byteToChar[byteOffset] || byteOffset
  end

  def lineForPosition(pos)
    idx = @lineOffsets.findIndex { |offset| offset > pos }
    idx == -1 ? @lineOffsets.length : idx
  end

  # Alias for Ruby snake_case convention (used by serializer.rb)
  def line_for_position(pos)
    lineForPosition(pos)
  end

  def columnForPosition(pos)
    lineIdx = @lineOffsets.findIndex { |offset| offset > pos }
    lineIdx = @lineOffsets.length if lineIdx == -1
    pos - @lineOffsets[lineIdx - 1]
  end

  # Alias for Ruby snake_case convention (used by serializer.rb)
  def column_for_position(pos)
    columnForPosition(pos)
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
  @@next_object_id = 1

  def initialize(prismComment, source, sourceBuffer)
    unless defined? self.object_id
      self.object_id = @@next_object_id
      @@next_object_id += 1
    end

    byteStart = prismComment.location.startOffset
    byteEnd = byteStart + prismComment.location.length
    start = sourceBuffer.byteToCharOffset(byteStart)
    end_ = sourceBuffer.byteToCharOffset(byteEnd)
    @text = source[start...end_]

    @location = {
      startOffset: start,
      endOffset: end_,
      end_offset: end_
    }

    # Use PrismSourceRange for expression so it has the line getter
    @loc = {
      start_offset: start,
      expression: PrismSourceRange.new(sourceBuffer, start, end_)
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
    return unless node

    # Only add node to list if it has location info
    if node.loc
      # Use bracket notation to prevent camelCase conversion
      start_pos = node.loc['start_offset']
      if start_pos != undefined && node.type != :begin
        nodes_by_pos.push([start_pos, depth, node])
      end
    end

    # Always recurse into children (even if current node has no loc)
    if node.children
      node.children.each do |child|
        collect_nodes(child, depth + 1) if child&.type # Pragma: method
      end
    end
  end

  collect_nodes(ast, 0) # Pragma: method

  nodes_by_pos.sort! do |a, b|
    cmp = a[0] - b[0]
    cmp != 0 ? cmp : a[1] - b[1]
  end

  comments.each do |comment|
    # Use bracket notation to prevent camelCase conversion
    comment_end = comment.location['end_offset']
    candidate = nodes_by_pos.find { |item| item[0] >= comment_end }
    next unless candidate
    node = candidate[2]
    result.set(node, []) unless result.has(node)
    result.get(node).push(comment)
  end

  result
end

# Set up globals for modules that expect them
export setupGlobals = ->(ruby2js_module) do
  globalThis.Prism = Prism
  globalThis.PrismSourceBuffer = PrismSourceBuffer
  globalThis.PrismSourceRange = PrismSourceRange
  globalThis.Hash = Hash
  globalThis.RUBY_VERSION = "3.4.0"
  globalThis.RUBY2JS_PARSER = "prism"
  # Mark this as selfhost environment for JS-specific code paths
  globalThis.RUBY2JS_SELFHOST = true
  # Set up Ruby2JS global with Node class for prism_walker
  globalThis.Ruby2JS = ruby2js_module if ruby2js_module
end

# Initialize Prism WASM parser (module-level variable for caching)
prismParse_ = nil

export async def initPrism
  prismParse_ ||= await Prism.loadPrism()
  prismParse_
end

export def getPrismParse
  prismParse_
end
