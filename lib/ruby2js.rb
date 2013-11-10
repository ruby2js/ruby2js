require 'parser/current'
require 'ruby2js/converter'

module Ruby2JS
  VERSION   = '0.0.2'
  
  def self.convert(source)

    if Proc === source
      file,line = source.source_location
      source = File.read(file)
      ast = find_block( parse(source), line )
    else
      ast = parse( source )
    end

    ruby2js = Ruby2JS::Converter.new( ast )

    ruby2js.method_calls += source.scan(/(\w+)\(\)/).flatten.map(&:to_sym)

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
      lines.join("\n")
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
