module Ruby2JS
  class Converter
    # Handle vue_template nodes - output template content as-is
    # s(:vue_template, template_content)
    handle :vue_template do |template|
      put template.to_s
    end
  end
end
