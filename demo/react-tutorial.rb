# Implementation of http://facebook.github.io/react/docs/tutorial.html in
# Ruby using Sinatra and Wunderbar.
#
# Key differences:
#  * Classes named Comment do bad things, at least in Firefox and Chrome.
#    https://developer.mozilla.org/en-US/docs/Web/API/Comment
#  * Vanilla JS is used in place of jQuery.  http://vanilla-js.com/
#  * A modicum of CSS styling is added.
#
# While this is a complete application (client+server) in one source file,
# more typically Sinatra views would be split out to a separate file.

require 'wunderbar/sinatra'
require 'wunderbar/script'
require 'ruby2js/filter/react'

data = []

get '/comments.json' do
  _json do
    data
  end
end

post '/comments.json' do
  _json do
    data << {author: @author, text: @text}
  end
end

get '/' do
  _html do
    _title 'Hello React'
    _script src: 'http://fb.me/react-0.12.2.js'
    _script src: 'http://cdnjs.cloudflare.com/ajax/libs/showdown/0.3.1/showdown.min.js'
    _style %{
      fieldset input, fieldset textarea {
        display: block;
        margin: 0.3em 0;
      }

      fieldset input[type=text], fieldset textarea {
        width: 100%;
      }
    }

    _div.content!

    _script_ do
      converter = Showdown.new.converter()

      class Comment < React
        def render
          rawMarkup = converter.makeHtml(@@children.toString())
          _div.comment do
            _h2.commentAuthor @@author
            _span dangerouslySetInnerHTML: {__html: rawMarkup}
          end
        end
      end

      class CommentList < React
        def render
          _div.commentList @@data do |comment|
            _Comment comment.text, author: comment.author
          end
        end
      end

      class CommentForm < React
        def handleSubmit(e)
          e.preventDefault()

          author = ~author.value.trim()
          text = ~text.value.trim()
          return unless text and author

          @@onCommentSubmit.(author: author, text: text)

          ~author.value = ''
          ~text.value = ''
        end

        def render
          _form.commentForm onSubmit: self.handleSubmit do
            _fieldset do
              _legend 'Enter new comment'
              _input type: 'text', placeholder: 'Your name', ref: 'author'
              _textarea rows: 8, placeholder: 'Say something...', ref: 'text'
              _input type: 'submit', value: 'Post'
            end
          end
        end
      end

      class CommentBox < React
        def loadCommentsFromServer()
          request = XMLHttpRequest.new()
          request.open('GET', @@url, true)
          request.onreadystatechange = proc do
            return unless request.readyState == 4 and request.status == 200
            @data = JSON.parse(request.responseText)
          end
          request.send()
        end

        def handleCommentSubmit(comment)
          @data = @data.concat([comment])

          request = XMLHttpRequest.new()
          request.open('POST', @@url, true)
          request.setRequestHeader('Content-type', 'application/json')
          request.onreadystatechange = proc do
            return unless request.readyState == 4 and request.status == 200
            @data = JSON.parse(request.responseText)
          end
          request.send(JSON.stringify(comment))
        end

        def getInitialState()
          return {data: []}
        end

        def componentDidMount()
          self.loadCommentsFromServer()
          setInterval(self.loadCommentsFromServer, @@pollInterval)
        end

        def render
          _div.commentBox do
            _h1 'Comments'
            _CommentList data: @data
            _CommentForm onCommentSubmit: self.handleCommentSubmit
          end
        end
      end

      React.render(
        _CommentBox(url: 'comments.json', pollInterval: 2000), 
        document.getElementById('content')
      )
    end
  end
end
