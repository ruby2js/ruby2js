import Ruby2JS, from: '@ruby2js/ruby2js'
import path, from: 'path'
import [ get_options ], from: "loader-utils"

export default def loader(source)
  file = path.relative(process.cwd(), self.resourcePath)
  options = { **get_options(self), file: file }

  begin
    js = Ruby2JS.convert(source, options)

    if options[:provide_source_maps] == false
      return js.to_s
    else
      self.callback(nil, js.to_s, js.sourcemap)
    end
  rescue => error
    message = error.message
    message += "\n\n#{error.diagnostic}" if error.diagnostic
    self.callback(Error.new(message))
  end
end
