require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'stringio'

# Mock Rails.root for testing
module Rails
  def self.root
    @root ||= Pathname.new(Dir.tmpdir).join("ruby2js_test_#{$$}")
  end

  def self.root=(path)
    @root = Pathname.new(path)
  end
end

require 'ruby2js/rails/stimulus_middleware'

describe Ruby2JS::Rails::StimulusMiddleware do
  let(:inner_app) { ->(env) { [404, {'Content-Type' => 'text/plain'}, ['Not Found']] } }
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
    it 'transpiles .rb controller to JavaScript' do
      File.write(controllers_path.join("chat_controller.rb"), <<~RUBY)
        class ChatController < Stimulus::Controller
          def connect()
            console.log("connected")
          end
        end
      RUBY

      response = get('/controllers/chat_controller.js')

      _(response.status).must_equal 200
      _(response.headers['Content-Type']).must_include 'application/javascript'
      _(response.body).must_include 'class ChatController extends Stimulus.Controller'
      _(response.body).must_include 'connect()'
      _(response.body).must_include 'console.log("connected")'
    end

    it 'passes through requests for non-existent .rb files' do
      response = get('/controllers/missing_controller.js')

      _(response.status).must_equal 404
    end

    it 'handles nested controller paths' do
      nested_path = controllers_path.join("admin")
      FileUtils.mkdir_p(nested_path)
      File.write(nested_path.join("users_controller.rb"), <<~RUBY)
        class Admin::UsersController < Stimulus::Controller
          def connect()
          end
        end
      RUBY

      response = get('/controllers/admin/users_controller.js')

      _(response.status).must_equal 200
      # Ruby2JS transpiles namespaced classes as Admin.UsersController = class ...
      _(response.body).must_include 'UsersController'
      _(response.body).must_include 'extends Stimulus.Controller'
    end

    it 'returns error JavaScript on transpilation failure' do
      File.write(controllers_path.join("broken_controller.rb"), <<~RUBY)
        class BrokenController < Stimulus::Controller
          def connect(
            # syntax error - missing closing paren
          end
        end
      RUBY

      response = get('/controllers/broken_controller.js')

      _(response.status).must_equal 500
      _(response.body).must_include 'console.error'
    end
  end

  describe 'manifest generation' do
    it 'generates index.js with all Ruby controllers' do
      File.write(controllers_path.join("chat_controller.rb"), <<~RUBY)
        class ChatController < Stimulus::Controller
        end
      RUBY

      File.write(controllers_path.join("modal_controller.rb"), <<~RUBY)
        class ModalController < Stimulus::Controller
        end
      RUBY

      response = get('/controllers/index.js')

      _(response.status).must_equal 200
      _(response.body).must_include 'import { application } from "./application"'
      _(response.body).must_include 'import ChatController from "./chat_controller.js"'
      _(response.body).must_include 'import ModalController from "./modal_controller.js"'
      _(response.body).must_include 'application.register("chat", ChatController)'
      _(response.body).must_include 'application.register("modal", ModalController)'
    end

    it 'includes JavaScript-only controllers in manifest' do
      File.write(controllers_path.join("chat_controller.rb"), "class ChatController < Stimulus::Controller; end")
      File.write(controllers_path.join("legacy_controller.js"), "// pure JS controller")

      response = get('/controllers/index.js')

      _(response.body).must_include 'import ChatController from "./chat_controller.js"'
      _(response.body).must_include 'import LegacyController from "./legacy_controller.js"'
    end

    it 'prefers .rb over .js when both exist' do
      File.write(controllers_path.join("chat_controller.rb"), "class ChatController < Stimulus::Controller; end")
      File.write(controllers_path.join("chat_controller.js"), "// should be ignored")

      response = get('/controllers/index.js')

      # Should only appear once
      _(response.body.scan('ChatController').length).must_equal 2  # import + register
    end

    it 'returns 404 when controllers directory does not exist' do
      FileUtils.rm_rf(controllers_path)

      response = get('/controllers/index.js')

      _(response.status).must_equal 404
    end
  end

  describe 'path matching' do
    it 'matches various path prefixes' do
      File.write(controllers_path.join("test_controller.rb"), <<~RUBY)
        class TestController < Stimulus::Controller
        end
      RUBY

      # Different path prefixes that should all work
      [
        '/controllers/test_controller.js',
        '/javascript/controllers/test_controller.js',
        '/assets/controllers/test_controller.js'
      ].each do |path|
        response = get(path)
        _(response.status).must_equal 200, "Expected 200 for #{path}"
      end
    end
  end
end
