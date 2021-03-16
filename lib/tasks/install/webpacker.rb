#
# These instructions can be used standalone or in combination with other
# instructions.
#
# If used standalone on a repository which did not previously have the Ruby2JS
# webpack loader configured, it will add the '.js.rb' extension to
# `config/webpacker.yml`, install the Ruby2JS webpack-loader and add a minimal
# configuration which runs the Ruby2JS webpack loader then the babel loader to
# `config/webpacker.yml`.
#
# Other instructions can require these instructions.  If they set the
# @ruby2js_options instance variable before they do so, the options provided
# will be merged and/or override the ones in the base configuration.  
#
# If these instructions are run against a Rails application that was
# previously configured, the @ruby2js_options provided, if any, will be merged
# with the options found in the configuration.
#

# default options
options = @ruby2js_options || {}

# define .js.rb as a extension to webpacker
insert_into_file Rails.root.join("config/webpacker.yml").to_s,
  "    - .js.rb\n", after: "\n    - .js\n"

# install webpack loader
run "yarn add @ruby2js/webpack-loader #{@yarn_add}"

target = Rails.root.join("config/webpack/loaders/ruby2js.js").to_s

# default config
if not File.exist? target
  # may be called via eval, or directly.  Resolve source either way.
  source_paths.unshift __dir__
  source_paths.unshift File.dirname(caller.first)
  directory "config/webpack/loaders", File.dirname(target)
end

# load config
insert_into_file Rails.root.join("config/webpack/environment.js").to_s,
  "environment.loaders.prepend('ruby2js', require('./loaders/ruby2js'))\n"

# read current configuration
before = IO.read(target)

# extract indentation and options
match = /^(\s*)options: (\{.*?\n\1\})/m.match(before)

# evaluate base options.  Here it is handy that Ruby's syntax for hashes is
# fairly close to JavaScript's object literals.  May run into problems in the
# future if there ever is a need for {"x": y} as that would need to be
# {"x" => y} in Ruby.
base = eval(match[2])

# Merge the options, initially having the new options override the original
# options.
merged = base.merge(options)

# Intelligently combine options if they are the same type.
options.keys.each do |key|
  next unless base[key]

  if options[key].is_a? Array and base[key].is_a? Array
    merged[key] = (base[key] + options[key]).uniq
  elsif options[key].is_a? Numeric and base[key].is_a? Numeric
    merged[key] = [base[key], options[key]].max
  elsif options[key].is_a? Hash and base[key].is_a? Hash
    merged[key] = base[key].merge(options[key])
  end
end

# Serialize options as JavaScript, matching original indentation.
replacement =  Ruby2JS.convert(merged.inspect + "\n").to_s.
  gsub(/^/, match[1]).strip

# Update configuration
unless before.include? replacement
  gsub_file target, match[2].to_s, replacement
end
