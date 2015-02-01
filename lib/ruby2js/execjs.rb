require 'ruby2js'
require 'execjs'

module Ruby2JS
  def self.compile(source, options={})
    ExecJS.compile(convert(source, options))
  end

  def self.eval(source, options={})
    ExecJS.eval(convert(source, options))
  end

  def self.exec(source, options={})
    ExecJS.exec(convert(source, options))
  end
end
