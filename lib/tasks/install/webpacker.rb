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

# default config
config = <<~CONFIG
  // Insert rb2js loader at the end of list
  environment.loaders.append('rb2js', {
    test: /\.js\.rb$/,
    use: [
      {
        loader: "babel-loader",
        options: environment.loaders.get('babel').use[0].options
      },

      {
        loader: "@ruby2js/webpack-loader",
        options: {
          autoexports: "default",
          eslevel: 2021,
          filters: ["esm", "functions"]
        }
      },
    ]
  })
CONFIG

# read current configuration
target = Rails.root.join("config/webpack/environment.js").to_s
before = IO.read(target)

# extract indentation and options either from the current configuration or the
# default configuration.
if before.include? '@ruby2js/webpack-loader'
  match = /^(\s*)options: (\{.*?\n\1\})/m.match(before)
else
  match = /^(\s*)options: (\{.*?\n\1\})/m.match(config)
end

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
if before.include? '@ruby2js/webpack-loader'
  gsub_file target, match[2].to_s, replacement
else
  append_to_file target, "\n" + config.sub(match[2], replacement)
end
