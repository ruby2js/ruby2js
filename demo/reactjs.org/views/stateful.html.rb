_html do
  _h1 'A Stateful Component'

  _div.timer_example!

  _script crossorigin: true, src: "https://unpkg.com/react@17/umd/react.development.js"
  _script crossorigin: true, src: "https://unpkg.com/react-dom@17/umd/react-dom.development.js"

  _script do
		class Timer < React
			def initialize
				@seconds = 0
			end

			def tick()
        @seconds += 1
			end

			def componentDidMount()
				self.interval = setInterval(1000) {tick()}
			end

			def componentWillUnmount()
				clearInterval(self.interval)
			end

			def render
				%x{
					<div>
						Seconds: {@seconds}
					</div>
				}
			end
		end

		ReactDOM.render(
			%x(<Timer />),
			document.getElementById('timer-example')
		);
  end
end
