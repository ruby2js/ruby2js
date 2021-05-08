gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/active_functions'

describe Ruby2JS::Filter::ActiveFunctions do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015, filters: [Ruby2JS::Filter::ActiveFunctions]).to_s)
  end

  describe 'blank?' do
    it "should convert val.blank? to blank$(val)" do
      to_js( 'val.blank?' ).must_equal 'import { blank$ } from "@ruby2js/active-functions"; blank$(val)'
    end

    it "should not import function twice" do
      to_js( 'val.blank?;val.blank?' ).must_equal 'import { blank$ } from "@ruby2js/active-functions"; blank$(val); blank$(val)'
    end

    it "should work with other functions" do
      to_js( 'val.blank?;val.blank?;val.presence' ).must_equal 'import { blank$, presence$ } from "@ruby2js/active-functions"; blank$(val); blank$(val); presence$(val)'
    end
  end

  describe 'present?' do
    it "should convert val.present? to present$(val)" do
      to_js( 'val.present?' ).must_equal 'import { present$ } from "@ruby2js/active-functions"; present$(val)'
    end
  end

  describe 'chomp' do
    it "should convert val.chomp to chomp$(val)" do
      to_js( 'val.chomp' ).must_equal 'import { chomp$ } from "@ruby2js/active-functions"; chomp$(val)'
    end

    it "should convert val.chomp(suffix) to chomp$(val, suffix)" do
      to_js( 'val.chomp(suffix)' ).must_equal 'import { chomp$ } from "@ruby2js/active-functions"; chomp$(val, suffix)'
    end
  end

  describe 'delete_prefix' do
    it "should convert val.delete_prefix('str') to deletePrefix$(val, 'str')" do
      to_js( 'val.delete_prefix(\'str\')' ).must_equal 'import { deletePrefix$ } from "@ruby2js/active-functions"; deletePrefix$(val, "str")'
    end
  end

  describe 'delete_suffix' do
    it "should convert val.delete_suffix('str') to deleteSuffix$(val, 'str')" do
      to_js( 'val.delete_suffix(\'str\')' ).must_equal 'import { deleteSuffix$ } from "@ruby2js/active-functions"; deleteSuffix$(val, "str")'
    end
  end
end
