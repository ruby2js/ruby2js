require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'stringio'

# Mock Rails for testing
module Rails
  def self.root
    @root ||= Pathname.new(Dir.tmpdir).join("ruby2js_test_#{$$}")
  end

  def self.root=(path)
    @root = Pathname.new(path)
  end

  def self.env
    @env ||= OpenStruct.new(development?: true)
  end
end

require 'ruby2js/rails/stimulus_middleware'

describe Ruby2JS::Rails::StimulusMiddleware do
  let(:inner_app) { ->(env) { [200, {'Content-Type' => 'text/plain'}, ['OK']] } }
  let(:middleware) { Ruby2JS::Rails::StimulusMiddleware.new(inner_app) }
  let(:controllers_path) { Rails.root.join("app/javascript/controllers") }

  def get(path)
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => path,
      'rack.input' => StringIO.new
    }
    status, headers, body = middleware.call(env)
    OpenStruct.new(status: status, headers: headers, body: body.join)
  end

  before do
    FileUtils.mkdir_p(controllers_path)
  end

  after do
    FileUtils.rm_rf(Rails.root)
  end

  describe 'controller transpilation' do
    it 'transpiles .rb controller to .js file' do
      File.write(controllers_path.join("chat_controller.rb"), <<~RUBY)
        class ChatController < Stimulus::Controller
          def connect()
            console.log("connected")
          end
        end
      RUBY

      # Trigger middleware to transpile
      get('/anything')

      # Check that .js file was created
      js_path = controllers_path.join("chat_controller.js")
      _(File.exist?(js_path)).must_equal true

      js_content = File.read(js_path)
      _(js_content).must_include 'class ChatController extends Controller'
      _(js_content).must_include 'connect()'
      _(js_content).must_include 'console.log("connected")'
    end

    it 'generates ESM-compatible output with export default' do
      File.write(controllers_path.join("chat_controller.rb"), <<~RUBY)
        class ChatController < Stimulus::Controller
          def connect()
          end
        end
      RUBY

      get('/anything')

      js_content = File.read(controllers_path.join("chat_controller.js"))
      _(js_content).must_include 'import { Controller } from "@hotwired/stimulus"'
      _(js_content).must_include 'export default class ChatController'
    end

    it 'skips transpilation when .js is newer than .rb' do
      rb_path = controllers_path.join("chat_controller.rb")
      js_path = controllers_path.join("chat_controller.js")

      File.write(rb_path, "class ChatController < Stimulus::Controller; end")
      File.write(js_path, "// existing js")

      # Make .js newer than .rb
      sleep 0.01
      FileUtils.touch(js_path)

      get('/anything')

      # JS content should not have been overwritten
      _(File.read(js_path)).must_equal "// existing js"
    end

    it 're-transpiles when .rb is newer than .js' do
      rb_path = controllers_path.join("chat_controller.rb")
      js_path = controllers_path.join("chat_controller.js")

      File.write(js_path, "// old js")
      sleep 0.01
      File.write(rb_path, <<~RUBY)
        class ChatController < Stimulus::Controller
          def connect()
            console.log("updated")
          end
        end
      RUBY

      get('/anything')

      js_content = File.read(js_path)
      _(js_content).must_include 'console.log("updated")'
    end

    it 'handles transpilation errors gracefully' do
      File.write(controllers_path.join("broken_controller.rb"), <<~RUBY)
        class BrokenController < Stimulus::Controller
          def connect(
            # syntax error - missing closing paren
          end
        end
      RUBY

      # Should not raise - errors are logged, not thrown
      response = get('/anything')
      _(response.status).must_equal 200

      # .js file should not be created
      _(File.exist?(controllers_path.join("broken_controller.js"))).must_equal false
    end
  end

  describe 'pass-through behavior' do
    it 'passes all requests to the inner app' do
      File.write(controllers_path.join("chat_controller.rb"), <<~RUBY)
        class ChatController < Stimulus::Controller; end
      RUBY

      # All paths should pass through
      [
        '/controllers/chat_controller.js',
        '/assets/application.js',
        '/anything/else'
      ].each do |path|
        response = get(path)
        _(response.status).must_equal 200
        _(response.body).must_equal 'OK'
      end
    end
  end

  describe 'development mode checking' do
    it 'checks for updates on every request in development' do
      rb_path = controllers_path.join("chat_controller.rb")
      js_path = controllers_path.join("chat_controller.js")

      File.write(rb_path, <<~RUBY)
        class ChatController < Stimulus::Controller
          def connect()
            console.log("v1")
          end
        end
      RUBY

      get('/anything')
      _(File.read(js_path)).must_include 'console.log("v1")'

      # Update the .rb file
      sleep 0.01
      File.write(rb_path, <<~RUBY)
        class ChatController < Stimulus::Controller
          def connect()
            console.log("v2")
          end
        end
      RUBY

      # In development mode, should pick up the change
      get('/anything')
      _(File.read(js_path)).must_include 'console.log("v2")'
    end
  end

  describe 'empty controllers directory' do
    it 'handles missing controllers directory gracefully' do
      FileUtils.rm_rf(controllers_path)

      response = get('/anything')
      _(response.status).must_equal 200
    end
  end
end
