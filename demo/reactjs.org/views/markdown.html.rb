_html do
  _style %{
    #markdown-content {display: block; width: 100%; height: 8em}
  }

  _div.markdown_example!

  _script crossorigin: true, src: "https://unpkg.com/react@17/umd/react.development.js"
  _script crossorigin: true, src: "https://unpkg.com/react-dom@17/umd/react-dom.development.js"
  _script src: "https://cdn.jsdelivr.net/remarkable/1.7.1/remarkable.min.js"

  _script do
    class MarkdownEditor < React
      def initialize
        self.md = Remarkable.new
        @value = 'Hello, **world**!'
      end

      def handleChange(e)
        @value = e.target.value
      end

      def getRawMarkup
        {__html: self.md.render(@value)}
      end

      def render
        _h3 "Input"
        _label 'Enter some markdown', for: 'markdown-content'
        _textarea.markdown_content! onChange: handleChange,
          defaultValue: @value

        _h3 "Output"
        _div.content dangerouslySetInnerHTML: getRawMarkup
      end
    end

    ReactDOM.render(
      _MarkdownEditor,
      document.getElementById('markdown-example')
    );
  end
end
