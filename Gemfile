source 'https://rubygems.org'

gem 'parser'

group :development, :test do
  gem 'minitest'
  gem 'rake', ('~> 12.2.1' if RUBY_VERSION =~ /^1/)
  gem 'execjs'
end

group :test do
  if RUBY_VERSION =~ /^1/
    gem 'haml', '~> 4.0'
  else
    gem 'haml'
  end
end
