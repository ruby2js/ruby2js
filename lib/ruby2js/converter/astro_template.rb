module Ruby2JS
  class Converter
    # Handle astro_template nodes - output template content as-is
    # s(:astro_template, template_content)
    handle :astro_template do |template|
      put template.to_s
    end
  end
end
