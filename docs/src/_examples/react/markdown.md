---
top_section: React
order: 25
title: A Markdown editor
category: markdown
---

### A Markdown editor

This example highlights invoking third party components, and *dangerously*
setting HTML from the results.

<div data-controller="combo" data-options='{
  "eslevel": 2020,
  "filters": ["react"]
}'></div>

```ruby
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
```

There is not a whole lot new in this example:

 * setting an adhoc property on a React component is done via `self.name=`
   assignments and referenced using `self.name`.

 * Creating an instance of a third party component is done by calling the
   `.new` operator.  As an aside, with Ruby2js, this can also be done using
   the JavaScript syntax of `new Remarkable()`.

 * In this case, a `handleChange` method is provided and referenced as an
   `onChange` handler.  This is necessary as a `onChange` handler is only
   necessary and therefore automatically provided by the **react** filter when
   a `value` attribute is provided on a `textarea`, not when a `defaultValue`
   is provided.  See the React document for
   [Uncontrolled Components](https://reactjs.org/docs/uncontrolled-components.html)
   for more details.

 * `getRawMarkup` returns a Ruby hash/JavaScript object, and is invoked via
   `getRawMarkup` (i.e., no `this.` nor `()`).
