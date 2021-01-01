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
end
