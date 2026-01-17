require 'minitest/autorun'
require 'ruby2js/isr'

describe Ruby2JS::ISR do
  describe "Base adapter interface" do
    it "raises NotImplementedError for serve" do
      _ { Ruby2JS::ISR::Base.serve(nil, '/test') {} }.must_raise NotImplementedError
    end

    it "raises NotImplementedError for revalidate" do
      _ { Ruby2JS::ISR::Base.revalidate('/test') }.must_raise NotImplementedError
    end

    it "raises NotImplementedError for revalidate_tag" do
      _ { Ruby2JS::ISR::Base.revalidate_tag('posts') }.must_raise NotImplementedError
    end
  end

  describe "parse_pragma" do
    it "parses revalidate pragma from comments" do
      comments = ['# Pragma: revalidate 60']
      result = Ruby2JS::ISR::Base.parse_pragma(comments)
      _(result).must_equal({ revalidate: 60 })
    end

    it "parses revalidate pragma case-insensitively" do
      comments = ['# pragma: REVALIDATE 120']
      result = Ruby2JS::ISR::Base.parse_pragma(comments)
      _(result).must_equal({ revalidate: 120 })
    end

    it "returns nil when no pragma found" do
      comments = ['# This is a regular comment']
      result = Ruby2JS::ISR::Base.parse_pragma(comments)
      _(result).must_be_nil
    end

    it "handles empty comments array" do
      result = Ruby2JS::ISR::Base.parse_pragma([])
      _(result).must_be_nil
    end

    it "handles comment objects with to_s" do
      comment = Object.new
      def comment.to_s; '# Pragma: revalidate 30'; end
      result = Ruby2JS::ISR::Base.parse_pragma([comment])
      _(result).must_equal({ revalidate: 30 })
    end
  end

  describe "cache_control_header" do
    it "generates header with default values" do
      header = Ruby2JS::ISR::Base.cache_control_header
      _(header).must_equal "s-maxage=60, stale-while-revalidate=86400"
    end

    it "generates header with custom revalidate time" do
      header = Ruby2JS::ISR::Base.cache_control_header(revalidate: 120)
      _(header).must_equal "s-maxage=120, stale-while-revalidate=86400"
    end

    it "generates header with custom stale window" do
      header = Ruby2JS::ISR::Base.cache_control_header(
        revalidate: 60,
        stale_while_revalidate: 3600
      )
      _(header).must_equal "s-maxage=60, stale-while-revalidate=3600"
    end
  end

  describe "Memory adapter" do
    before do
      Ruby2JS::ISR::Memory.clear_cache
    end

    it "caches content on first request" do
      call_count = 0
      content = Ruby2JS::ISR::Memory.serve(nil, '/test', revalidate: 60) do
        call_count += 1
        "content #{call_count}"
      end

      _(content).must_equal "content 1"
      _(call_count).must_equal 1
    end

    it "serves cached content on subsequent requests" do
      call_count = 0
      render = -> {
        Ruby2JS::ISR::Memory.serve(nil, '/test', revalidate: 60) do
          call_count += 1
          "content #{call_count}"
        end
      }

      first = render.call
      second = render.call

      _(first).must_equal "content 1"
      _(second).must_equal "content 1"
      _(call_count).must_equal 1
    end

    it "serves stale content and regenerates when expired" do
      call_count = 0
      render = -> {
        Ruby2JS::ISR::Memory.serve(nil, '/test', revalidate: 0) do
          call_count += 1
          "content #{call_count}"
        end
      }

      first = render.call
      sleep 0.01  # Ensure time passes
      second = render.call

      _(first).must_equal "content 1"
      # Memory adapter returns stale content while regenerating
      _(second).must_equal "content 1"
      # But it did call the block to regenerate
      _(call_count).must_equal 2
    end

    it "revalidate clears cached content" do
      call_count = 0
      render = -> {
        Ruby2JS::ISR::Memory.serve(nil, '/test', revalidate: 60) do
          call_count += 1
          "content #{call_count}"
        end
      }

      first = render.call
      Ruby2JS::ISR::Memory.revalidate('/test')
      second = render.call

      _(first).must_equal "content 1"
      _(second).must_equal "content 2"
      _(call_count).must_equal 2
    end

    it "revalidate returns true" do
      result = Ruby2JS::ISR::Memory.revalidate('/test')
      _(result).must_equal true
    end

    it "revalidate_tag clears all cache" do
      Ruby2JS::ISR::Memory.serve(nil, '/a') { "a" }
      Ruby2JS::ISR::Memory.serve(nil, '/b') { "b" }

      Ruby2JS::ISR::Memory.revalidate_tag('anything')

      call_count = 0
      Ruby2JS::ISR::Memory.serve(nil, '/a') { call_count += 1; "a2" }
      Ruby2JS::ISR::Memory.serve(nil, '/b') { call_count += 1; "b2" }

      _(call_count).must_equal 2
    end

    it "uses different cache entries for different keys" do
      a = Ruby2JS::ISR::Memory.serve(nil, '/a') { "content a" }
      b = Ruby2JS::ISR::Memory.serve(nil, '/b') { "content b" }

      _(a).must_equal "content a"
      _(b).must_equal "content b"
    end
  end

  describe "constants" do
    it "has default revalidate time of 60 seconds" do
      _(Ruby2JS::ISR::DEFAULT_REVALIDATE).must_equal 60
    end

    it "has default stale-while-revalidate of 24 hours" do
      _(Ruby2JS::ISR::DEFAULT_STALE_WHILE_REVALIDATE).must_equal 86400
    end
  end
end
