create_file Rails.root.join('config/initializers/ruby2js').to_s,
  <<~CONFIG
		require 'ruby2js/filter/esm'
		require 'ruby2js/filter/functions'
		require 'ruby2js/filter/stimulus'

		Ruby2JS::SprocketsTransformer.options = {
			autoexports: :default,
			eslevel: 2020
		}

		require 'stimulus/importmap_helper'

		module Stimulus::ImportmapHelper
			def find_javascript_files_in_tree(path)
				 exts = {'.js' => '.js', '.jsm' => '.jsm'}.merge(
					 Sprockets.mime_exts.map {|key, value|
						 next unless Sprockets.transformers[value]["application/javascript"]
						 [key, '.js']
					 }.compact.to_h)

				 Dir[path.join('**/*')].map {|file|
					 file_ext, web_ext = Sprockets::PathUtils.match_path_extname(file, exts)
					 next unless file_ext

					 next unless File.file? file

					 Pathname.new(file.chomp(file_ext) + web_ext)
				 }.compact
			end
		end
  CONFIG
