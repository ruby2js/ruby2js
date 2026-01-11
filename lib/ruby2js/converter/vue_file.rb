module Ruby2JS
  class Converter
    # Handle vue_file nodes - output Vue SFC format
    # s(:vue_file, script_content, template_content)
    handle :vue_file do |script, template|
      # Template section
      put "<template>\n"
      put "  #{template}\n"
      put "</template>\n\n"

      # Script section (only if there's content)
      if script && !script.empty?
        put "<script setup>\n"
        put script
        put "\n</script>\n"
      end
    end
  end
end
