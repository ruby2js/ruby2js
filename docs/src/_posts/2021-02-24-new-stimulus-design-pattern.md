---
layout: post
title:  New Stimulus Design Pattern?
subtitle: Editors, Options, and Results, oh my!
categories: updates
author: rubys
---

As far as I know, this is a new design pattern for Stimulus.  At the very
least, it isn't something I was able to readily find with Google searches.

First, let's gets some standard stuff out of the way.  The
[Ruby2JS.com](https://ruby2js.com) is built using the
[Bridgetown](https://www.bridgetownrb.com/) static site generator.
[Opal](https://opalrb.com/) is used to generate the bulk of the scripts to be
executed.  [HTTP
caching](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching) ensures
that these scripts are only downloaded when they change.  [Turbo](Turbo)
ensures that these scripts are only loaded once per site visit.
[Stimulus](Stimulus) associates HTML elements with controllers.

All standard stuff so far.

[Ruby2JS.com](https://ruby2js.com) has three controllers on the page.  The
first is a Ruby editor.  The second is a read-only JavaScript view.  And the
third is invisible, but runs the JavaScript which outputs to the console log.
Other pages have these same three controllers with different arrangements
and/or different data, for example the [Stimulus
introduction](https://www.ruby2js.com/examples/stimulus/) and the [React Simple
Component](https://www.ruby2js.com/examples/stimulus/).  The [Ruby2JS
Demo](https://www.ruby2js.com/demo) has a Ruby editor and a JS ouput, but
doesn't have a results controller and adds an options controller.

The source to the controllers can be found in
[GitHub](https://github.com/ruby2js/ruby2js/tree/master/demo/controllers).
Unsurprisingly given that these controllers support the Ruby2JS site, they are
written in Ruby.

But that's not the unique design pattern part.

Look at a Ruby editor on any of the pages mentioned.  There isn't really any
[Actions](https://stimulus.hotwire.dev/reference/actions),
[Targets](https://stimulus.hotwire.dev/reference/targets),
[Values](https://stimulus.hotwire.dev/reference/values), or [CSS
Classes](https://stimulus.hotwire.dev/reference/css-classes) to speak of.

Instead, updates made in the Ruby editor are sent to *other* controllers.
A global overview of the design of these pages: the options controller on the
demo page will update the  Ruby controller.  The Ruby controller will update
both the JavaScript and evaluation results controllers.  And there is even a
case where the evaluation results controller will update the Ruby controller,
but we will get to that in a minute.

All of this is accomplished by subclassing a [common base
class](https://github.com/ruby2js/ruby2js/blob/master/demo/livedemo.js.rb) and
overridding the `source` method with calls to a `findController` method.  The
`findController` method unsurprisingly searches the `application.controllers`
array.  This base class also takes care of connecting sources with targets
indpendent of the order in which the controllers connect.

Once a source is paired with potentially multiple targets, messages pass via
standard method calls and/or attribute accessors (getters and setters in
JavaScript terms).

As an example,
[here](https://github.com/ruby2js/ruby2js/blob/master/demo/controllers/ruby_controller.js.rb#L96)
are the lines of code where `Ruby2JS.convert` is called and the resulting JavaScript is sent to each target.

The JSController's [implementation of the `contents=`
method](https://github.com/ruby2js/ruby2js/blob/91f75c3b83026bb0027c6fb390dafdd15a6ab6a9/demo/controllers/js_controller.js.rb#L38)
will dispatch the content to the jsEditor.

The EvalController's [implementation of the `contents=`
method](https://github.com/ruby2js/ruby2js/blob/master/demo/controllers/eval_controller.js.rb)
will load the script into a `script` element and append it to the document.

An interesting detail: if you bring up the [Stimulus
Introduction](https://www.ruby2js.com/examples/stimulus/) page and click on the
JavaScript tab you will see different results in Safari than you would in see
in Chrome, Firefox, or Microsoft Edge.  Safari doesn't yet support [static
public fields](https://github.com/tc39/proposal-static-class-features), so an
assignment statement after the class definition is used instead.

The way this works is that the Ruby souce code is initially converted to
JavaScript using the [ES2022
option](https://www.ruby2js.com/docs/eslevels#es2022-support), and the results
are sent to the evaluation controller.  The evaluation controller captures the
syntax error and given that this occurred on the very first update it will
update the `options` in the Ruby Controller, triggering another conversion, the
results of which are sent to both the JS and Eval controllers.

While this usage is quite different than the traditional application of
Stimulus, the end result is comparable: a site consisting entirely of static
HTML augmented with a small number of `data-` attributes that cause the
controllers to activate.

I'm quite curious if others have seen this usage of Stimulus before, if they
find it useful, or have any suggestions.
