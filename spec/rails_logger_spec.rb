require 'minitest/autorun'
require 'ruby2js/filter/rails/logger'

describe Ruby2JS::Filter::Rails::Logger do
  def to_js(string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Rails::Logger]).to_s
  end

  describe "Rails.logger" do
    it "converts debug to console.debug" do
      assert_equal 'console.debug("msg")', to_js('Rails.logger.debug "msg"')
    end

    it "converts info to console.info" do
      assert_equal 'console.info("msg")', to_js('Rails.logger.info "msg"')
    end

    it "converts warn to console.warn" do
      assert_equal 'console.warn("msg")', to_js('Rails.logger.warn "msg"')
    end

    it "converts error to console.error" do
      assert_equal 'console.error("msg")', to_js('Rails.logger.error "msg"')
    end

    it "converts fatal to console.error" do
      assert_equal 'console.error("msg")', to_js('Rails.logger.fatal "msg"')
    end

    it "handles multiple arguments" do
      assert_equal 'console.info("User:", user)', to_js('Rails.logger.info "User:", user')
    end

    it "does not affect other Rails methods" do
      assert_equal 'Rails.application', to_js('Rails.application')
    end

    it "does not affect other logger calls" do
      assert_equal 'logger.info("msg")', to_js('logger.info "msg"')
    end
  end
end
