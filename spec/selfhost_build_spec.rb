require 'minitest/autorun'
require 'ruby2js/filter/selfhost_build'

describe Ruby2JS::Filter::SelfhostBuild do

  def to_js(string, opts = {})
    _(Ruby2JS.convert(string, opts.merge(
      filters: [Ruby2JS::Filter::SelfhostBuild]
    )).to_s)
  end

  describe 'YAML' do
    it 'should transform YAML.load_file' do
      to_js('YAML.load_file("config.yml")').
        must_equal 'import yaml from "js-yaml"; import fs from "fs"; ' +
          'yaml.load(fs.readFileSync("config.yml", "utf8"))'
    end

    it 'should transform YAML.dump' do
      to_js('YAML.dump({foo: 1})').
        must_equal 'import yaml from "js-yaml"; yaml.dump({foo: 1})'
    end

    it 'should remove require yaml' do
      to_js('require "yaml"').must_equal ''
    end
  end

  describe '$LOAD_PATH' do
    it 'should remove $LOAD_PATH.unshift' do
      to_js('$LOAD_PATH.unshift("lib")').must_equal ''
    end

    it 'should remove $LOAD_PATH with method chains' do
      to_js('$LOAD_PATH.unshift(File.expand_path("lib"))').must_equal ''
    end
  end

  describe 'ruby2js requires' do
    it 'should transform require ruby2js' do
      to_js('require "ruby2js"').
        must_equal 'import Ruby2JS from "../selfhost/ruby2js.js"'
    end

    it 'should use custom selfhost_path option' do
      to_js('require "ruby2js"', selfhost_path: './converter.js').
        must_equal 'import Ruby2JS from "./converter.js"'
    end

    it 'should transform require ruby2js/filter/rails' do
      to_js('require "ruby2js/filter/rails"').
        must_equal 'import Rails from "../selfhost/filters/rails.js"'
    end

    it 'should transform require ruby2js/filter/functions' do
      to_js('require "ruby2js/filter/functions"').
        must_equal 'import Functions from "../selfhost/filters/functions.js"'
    end

    it 'should use custom selfhost_filters option' do
      to_js('require "ruby2js/filter/esm"', selfhost_filters: './filters').
        must_equal 'import ESM from "./filters/esm.js"'
    end
  end

  describe 'require_relative' do
    it 'should transform require_relative to import' do
      to_js('require_relative "../lib/foo"').
        must_equal 'import "../lib/foo.js"'
    end

    it 'should convert .rb extension to .js' do
      to_js('require_relative "../lib/foo.rb"').
        must_equal 'import "../lib/foo.js"'
    end
  end

  describe 'Ruby2JS constants' do
    it 'should transform Ruby2JS::Filter::Rails::Model' do
      to_js('Ruby2JS::Filter::Rails::Model').must_equal 'Rails_Model'
    end

    it 'should transform Ruby2JS::Filter::Rails::Controller' do
      to_js('Ruby2JS::Filter::Rails::Controller').must_equal 'Rails_Controller'
    end

    it 'should transform Ruby2JS::Filter::Functions' do
      to_js('Ruby2JS::Filter::Functions').must_equal 'Functions'
    end

    it 'should not transform other constants' do
      to_js('Foo::Bar::Baz').must_equal 'Foo.Bar.Baz'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include SelfhostBuild" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::SelfhostBuild
    end
  end
end
