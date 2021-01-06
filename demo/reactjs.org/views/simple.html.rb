_html do
  _h1 'A Simple Component'

  _div.hello_example!

  _script crossorigin: true, src: "https://unpkg.com/react@17/umd/react.development.js"
  _script crossorigin: true, src: "https://unpkg.com/react-dom@17/umd/react-dom.development.js"

  _script do
    class HelloMessage < React::Component
      def render
        %x(
          <div>
            Hello {this.props.name}
          </div>
        )
      end
    end

    ReactDOM.render(
      %x(<HelloMessage name="Taylor" />),
      document.getElementById('hello-example')
    )
  end
end
