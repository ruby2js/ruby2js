# Example usage:
#
#   sinatra.rb:
#
#     require 'ruby2js/sinatra'
#     get '/test.js' do
#       ruby2js :test
#     end
#
#   views/test.rb:
#
#     alert 'Hello World!'
#
# Using an optional filter:
#
#   require 'ruby2js/filter/functions'

require 'sinatra'
require 'ruby2js'

class Ruby2JSTemplate < Tilt::Template
  self.default_mime_type = 'application/javascript'

  def prepare
  end

  def evaluate(scope, locals, &block)
    @output ||= Ruby2JS.convert(data)
  end

  def allows_script?
    false
  end
end

Tilt.register 'rb', Ruby2JSTemplate

helpers do
  def ruby2js(*args)
    content_type 'application/javascript'
    render('rb', *args).to_s
  end
end
