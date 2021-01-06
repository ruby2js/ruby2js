require 'bundler/setup'
require 'wunderbar/sinatra'
require 'wunderbar/script'
require 'ruby2js/filter/react'
require 'ruby2js/filter/functions'
require 'ruby2js/es2020'

get '/' do
  _html :index
end

get '/ruby2js.svg' do
  # /srv/git/ruby2js/ruby2js.svg
  send_file File.expand_path('../../docs/src/images/ruby2js.svg')
end

get '/simple' do
  _html :simple
end

get '/stateful' do
  _html :stateful
end

get '/todo' do
  _html :todo
end

get '/markdown' do
  _html :markdown
end
