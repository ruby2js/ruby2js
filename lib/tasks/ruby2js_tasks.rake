if defined? Thor
  Thor::Actions::WARNINGS[:unchanged_no_flag] = 'unchanged'
end

def template(location)
  system "#{RbConfig.ruby} #{Rails.root.join("bin")}/rails app:template " + 
    "LOCATION=#{File.expand_path(location, __dir__)}"
end

namespace :ruby2js do
  namespace :install do
    desc "Install Ruby2JS with LitElement support"
    task :litelement do
      template 'install/lit-webpacker.rb'
    end

    desc "Install Ruby2JS with Preact support"
    task :preact do
      template 'install/preact.rb'
    end

    desc "Install Ruby2JS with React support"
    task :react do
      template 'install/react.rb'
      Rake::Task['webpacker:install:react'].invoke
    end

    namespace :stimulus do
      desc "Install Ruby2JS with Stimulus Rollup support"
      task :rollup do
        template 'install/stimulus-rollup.rb'
      end

      desc "Install Ruby2JS with Stimulus Webpacker support"
      task :webpacker => :"stimulus:install" do
        template 'install/stimulus-webpacker.rb'
      end
    end

    namespace :lit do
      desc "Install Ruby2JS with Lit Rollup support"
      task :rollup do
        template 'install/lit-rollup.rb'
      end

      desc "Install Ruby2JS with Lit Webpacker support"
      task :webpacker do
        template 'install/lit-webpacker.rb'
      end
    end
  end
end

namespace :webpacker do
  namespace :install do
    desc "Install everything needed for Ruby2JS"
    task :ruby2js do
      template 'install/webpacker.rb'
    end
  end
end
