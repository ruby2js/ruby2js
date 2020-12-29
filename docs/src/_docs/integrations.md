---
order: 3
title: Integrations
top_section: Introduction
category: integrations
---

While **Ruby2JS** is a low level library suitable for DIY integration, one of the
obvious uses of a tool that produces JavaScript is by web servers.  Ruby2JS
includes several integrations:

*  [CGI](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/cgi.rb)
*  [Sinatra](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/sinatra.rb)
*  [Rails/Sprockets](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/rails.rb)
*  [Haml](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/haml.rb)

As you might expect, CGI is a bit sluggish.  By contrast, Sinatra and Rails
are quite speedy as the bulk of the time is spent on the initial load of the
required libraries.

For easy integration with Webpack (as well as Webpacker in Rails 5+), you can use the
[official Webpack plugin](/docs/webpack).