# View helpers for HTML generation
# Mimics Rails view helpers

export module ViewHelpers
  def self.link_to(text, path, options = {})
    onclick = options[:onclick] || "navigate('#{path}')"
    style = options[:style] ? " style=\"#{options[:style]}\"" : ''
    css_class = options[:class] ? " class=\"#{options[:class]}\"" : ''

    "<a onclick=\"#{onclick}\"#{css_class}#{style}>#{text}</a>"
  end

  def self.button_to(text, path, options = {})
    method = options[:method] || 'post'
    css_class = options[:class] || ''
    onclick = options[:onclick] || "#{method}Action('#{path}')"

    "<button class=\"#{css_class}\" onclick=\"#{onclick}\">#{text}</button>"
  end
end
