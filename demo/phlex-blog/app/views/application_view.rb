# Base view class for blog application
# Provides common helpers and layout wrapping
class ApplicationView < Phlex::HTML
  # Override in subclasses
  def title
    "Blog"
  end

  # Helper: truncate text
  def truncate(text, length: 100)
    return "" unless text
    if text.length > length
      "#{text[0...length]}..."
    else
      text
    end
  end

  # Helper: format time ago
  def time_ago(time)
    return "unknown" unless time
    seconds = (Date.now - time) / 1000

    if seconds < 60
      "#{seconds.to_i}s ago"
    elsif seconds < 3600
      "#{(seconds / 60).to_i}m ago"
    elsif seconds < 86400
      "#{(seconds / 3600).to_i}h ago"
    else
      "#{(seconds / 86400).to_i}d ago"
    end
  end

  # Helper: format date
  def format_date(time)
    return "" unless time
    date = Date.new(time)
    date.toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" })
  end
end
