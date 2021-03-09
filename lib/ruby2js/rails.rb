require 'rails'
require_relative './sprockets'

class Ruby2JSRailtie < Rails::Railtie
  rake_tasks do
    Dir[File.expand_path('../tasks/*.rake', __dir__)].each do |file|
      load file
    end
  end
end
