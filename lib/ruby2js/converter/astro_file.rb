module Ruby2JS
  class Converter
    # Handle astro_file nodes - output Astro component format
    # s(:astro_file, frontmatter, template_content)
    handle :astro_file do |frontmatter, template|
      if frontmatter && !frontmatter.empty?
        put "---\n"
        put frontmatter
        put "\n---\n\n"
      end

      put template.to_s
    end
  end
end
