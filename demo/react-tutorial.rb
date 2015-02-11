# Implementation of http://facebook.github.io/react/docs/tutorial.html in
# Ruby using Sinatra and Wunderbar.
#
# Key differences:
#  * Server side rendering is performed, enabling this application to
#    degrade gracefully even if JavaScript is disabled
#  * Vanilla JS is used in place of jQuery.  http://vanilla-js.com/
#  * marked is used instead of showdown
#  * A modicum of CSS styling is added.
#
# While this is a complete application (client+server) in one source file,
# more typically Sinatra views would be split out to a separate file.

require 'sinatra'
require 'wunderbar/react'
require 'wunderbar/marked'

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

post '/' do
  data << {author: params[:author], text: params[:text]}
  call env.merge('REQUEST_METHOD' => 'GET')
end

get '/' do
  @data = data

  _html do
    _title 'Hello React'
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
      class Comment < React
        def render
          rawMarkup = marked(@@children.toString())
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
          _form.commentForm method: 'POST', onSubmit: self.handleSubmit do
            _fieldset do
              _legend 'Enter new comment'
              _input ref: 'author', name: 'author',
                placeholder: 'Your name'
              _textarea rows: 8, ref: 'text', name: 'text',
                placeholder: 'Say something...'
              _input type: 'submit', value: 'Post'
            end
          end
        end
      end

      class CommentBox < React
        def loadCommentsFromServer()
          request = XMLHttpRequest.new()
          request.open('GET', @@url, true)
          def request.onload()
            @data = JSON.parse(request.responseText)
          end
          request.send()
        end

        def handleCommentSubmit(comment)
          @data = @data.concat([comment])

          request = XMLHttpRequest.new()
          request.open('POST', @@url, true)
          request.setRequestHeader('Content-type', 'application/json')
          def request.onload()
            @data = JSON.parse(request.responseText)
          end
          request.send(JSON.stringify(comment))
        end

        def getInitialState()
          return {data: @@data}
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
    end

    _.render '#content' do
      _CommentBox data: @data, url: 'comments.json', pollInterval: 2000
    end
  end
end
