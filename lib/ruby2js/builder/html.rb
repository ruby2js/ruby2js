module Ruby2JS
  module Builder
    class Html
      extend Filter::SEXP

      # Standard element: <name attrs>content</name>
      def self.tag(name, attrs = {}, content = nil)
        parts = []
        open_tag = "<#{name}"
        close = ">#{content_is_static?(content) ? '' : ''}"

        static_attrs, dynamic_attrs = partition_attrs(attrs)

        if dynamic_attrs.empty? && content_is_static?(content)
          # Fully static — return a single string node
          attr_str = format_static_attrs(static_attrs)
          text = content_is_static?(content) ? extract_static(content) : ''
          return s(:str, "<#{name}#{attr_str}>#{text}</#{name}>")
        end

        # Dynamic — build dstr
        parts << s(:str, "<#{name}#{format_static_attrs(static_attrs)}")
        emit_dynamic_attrs(parts, dynamic_attrs)
        parts << s(:str, ">")
        emit_content(parts, content) if content
        parts << s(:str, "</#{name}>")

        collapse_strings(parts)
      end

      # Void element: <name attrs />
      def self.void(name, attrs = {})
        static_attrs, dynamic_attrs = partition_attrs(attrs)

        if dynamic_attrs.empty?
          attr_str = format_static_attrs(static_attrs)
          return s(:str, "<#{name}#{attr_str} />")
        end

        parts = []
        parts << s(:str, "<#{name}#{format_static_attrs(static_attrs)}")
        emit_dynamic_attrs(parts, dynamic_attrs)
        parts << s(:str, " />")

        collapse_strings(parts)
      end

      # Separate static and dynamic attributes
      def self.partition_attrs(attrs)
        static = {}
        dynamic = {}
        attrs.each do |key, value|
          if value.is_a?(String)
            static[key] = value
          elsif value.respond_to?(:type) && value.type == :str
            static[key] = value.children[0]
          else
            dynamic[key] = value
          end
        end
        [static, dynamic]
      end

      # Format static attributes as a string
      def self.format_static_attrs(attrs)
        return '' if attrs.empty?
        attrs.map { |k, v| " #{k}=\"#{v}\"" }.join
      end

      # Emit dynamic attributes into parts array
      def self.emit_dynamic_attrs(parts, attrs)
        attrs.each do |key, value|
          parts << s(:str, " #{key}=\"")
          parts << s(:begin, value)
          parts << s(:str, "\"")
        end
      end

      # Emit content into parts array
      def self.emit_content(parts, content)
        if content.respond_to?(:type)
          if content.type == :str
            parts << content
          else
            parts << s(:begin, content)
          end
        else
          parts << s(:str, content.to_s)
        end
      end

      # Check if content is a static string
      def self.content_is_static?(content)
        return true if content.nil?
        return true if content.is_a?(String)
        content.respond_to?(:type) && content.type == :str
      end

      # Extract static string value
      def self.extract_static(content)
        return '' if content.nil?
        return content if content.is_a?(String)
        content.children[0]
      end

      # Collapse adjacent :str nodes and wrap in :dstr
      def self.collapse_strings(parts)
        collapsed = []
        parts.each do |part|
          if part.type == :str && collapsed.last&.type == :str
            collapsed[-1] = s(:str, collapsed.last.children[0] + part.children[0])
          else
            collapsed << part
          end
        end

        return collapsed.first if collapsed.length == 1 && collapsed.first.type == :str
        s(:dstr, *collapsed)
      end
    end
  end
end
