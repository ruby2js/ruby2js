require 'parser/current'
require 'ruby2js/converter'

module Ruby2JS
  module Filter
    DEFAULTS = []

    module SEXP
      # construct an AST Node
      def s(type, *args)
        Parser::AST::Node.new type, args
      end
    end
  end

  def self.convert(source, options={})

    if Proc === source
      file,line = source.source_location
      source = File.read(file)
      ast = find_block( parse(source), line )
    elsif Parser::AST::Node === source
      ast = source
      source = ast.loc.expression.source_buffer.source
    else
      ast = parse( source )
    end

    filters = options[:filters] || Filter::DEFAULTS

    unless filters.empty?
      filter = Parser::AST::Processor
      filters.reverse.each do |mod|
        filter = Class.new(filter) {include mod} 
      end
      ast = filter.new.process(ast)
    end

    ruby2js = Ruby2JS::Converter.new( ast )

    ruby2js.binding = options[:binding]

    if source.include? "\n"
      ruby2js.enable_vertical_whitespace 
      lines = ruby2js.to_js.split("\n")
      pre = ''
      pending = false
      blank = true
      lines.each do |line|
        if line.start_with? '}' or line.start_with? ']'
          pre.sub!(/^  /,'')
          line.sub!(/;$/,";\n")
          pending = true
        else
          pending = false
        end

        line.sub! /^/, pre
        if line.end_with? '{' or line.end_with? '['
          pre += '  ' 
          line.sub!(/^/,"\n") unless blank or pending
          pending = true
        end

        blank = pending
      end

      lines.join("\n").gsub(/^  ( *(case.*|default):$)/, '\1')
    else
      ruby2js.to_js
    end
  end
  
  def self.parse(source)
    # workaround for https://github.com/whitequark/parser/issues/112
    buffer = Parser::Source::Buffer.new('__SOURCE__')
    buffer.raw_source = source.encode('utf-8')
    Parser::CurrentRuby.new.parse(buffer)
  end

  def self.find_block(ast, line)
    if ast.type == :block and ast.loc.expression.line == line
      return ast.children.last
    end

    ast.children.each do |child|
      if Parser::AST::Node === child
        block = find_block child, line
        return block if block
      end
    end

    nil
  end
end
