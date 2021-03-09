Thor::Actions::WARNINGS[:unchanged_no_flag] = 'unchanged'

def template(location)
  system "#{RbConfig.ruby} #{Rails.root.join("bin")}/rails app:template " + 
    "LOCATION=#{File.expand_path(location, __dir__)}"
end

namespace :ruby2js do
  namespace :install do
    desc "Install Ruby2JS with LitElement support"
    task :litelement do
      template 'install/litelement.rb'
    end

    namespace :stimulus do
      desc "Install Ruby2JS with Stimulus Sprockets support"
      task :sprockets => :"stimulus:install:asset_pipeline" do
        template 'install/stimulus-sprockets.rb'
      end

      desc "Install Ruby2JS with Stimulus Webpacker support"
      task :webpacker => :"stimulus:install" do
        template 'install/stimulus-webpacker.rb'
      end
    end
  end
end
