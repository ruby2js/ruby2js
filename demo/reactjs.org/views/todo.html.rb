_html do
  _div.todos_example!

  _script crossorigin: true, src: "https://unpkg.com/react@17/umd/react.development.js"
  _script crossorigin: true, src: "https://unpkg.com/react-dom@17/umd/react-dom.development.js"

  _script do
    class TodoApp < React
      def initialize
        @items = []
        @text = ''
      end

      def render
        _h3 "TODO"
        _TodoList items: @items

        _form onSubmit: handleSubmit do
          _label 'What needs to be done?', for: 'new-todo'
          _input.new_todo! value: @text
          _button "Add ##{@items.length + 1}"
        end
      end

      def handleSubmit(e)
        e.preventDefault()
        return if @text.empty?
        @items = @items.concat(text: @text, id: Date.now())
        @text = ''
      end
    end

    class TodoList < React
      def render
        _ul @@items do |item|
          _li item.text, key: item.id
        end
      end
    end

    ReactDOM.render(
      _TodoApp,
      document.getElementById('todos-example')
    );
  end
end
