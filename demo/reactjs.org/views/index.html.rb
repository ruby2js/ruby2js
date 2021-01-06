_html do
  _style %{
    img {height: 2em; width: 2em; transition: 2s}
    img:hover {height: 4em; width: 4em}
    body {font-family:var(--bs-font-sans-serif); line-height:1.5}
  }

  _h1! do
    _img src: 'ruby2js.svg'
    _ 'Ruby2JS React Demos'
  end

  _p! do
    _ 'The following demos are based on examples from '
    _a 'reactjs.org', href: 'https://reactjs.org'
    _ '.'
  end

  __

  _ul do
    _li { _a 'A Simple Component', href: 'simple' }
    _li { _a 'A Stateful Component', href: 'stateful' }
    _li { _a 'A Todo Application', href: 'todo' }
    _li { _a 'A Markdown Application', href: 'markdown' }
  end
end
