---
layout: post
title: Ruby2JS 5.1, esbuild, and a Peek at the Future
subtitle: Improving the quality of our developer experience while ensuring future maintainability and health of the project.
categories: updates
author: jared
---

At long last, **Ruby2JS 5.1 is here!** It comes packed with several very welcome features:

* A brand-new Ruby-based configuration DSL
* A "preset" option for sane defaults
* Magic comment support for sharing portable Ruby2JS code (based on the preset)

In addition, the [esbuild plugin](https://github.com/ruby2js/ruby2js/tree/master/packages/esbuild-plugin) has reached 1.0 status and has been re-architected to use the Ruby version of the compiler rather than the Node (aka Opal) version. Why? Performance and modern language compatibility.

Let's dig in a bit on all these new features! And keep reading as well for an update on the status of Ruby2JS and its open source governance.

## Ruby-based Configuration

Ruby2JS, despite being a language transpiler usually needing some degree of configuration, never had a canonical format for project-based configuration. Until today!

You can add `config/ruby2js.rb` to your project and both the Ruby API and the CLI tool will automatically detect its presence and use it for configuration. In addition, you can specify the location of a configuration file manually if you prefer to use a different filename or folder.

The configuration format is very simple and easy to work with, just like other configuration formats such as Puma. You can read all about it in [the documentation here](/docs/options). But that's not all!

## A Preset Configuration for Sane Defaults

We believe most Ruby2JS code would benefit greatly from transpiling to a modern ECMAScript version (namely ES2021), using a few common filters such as [Functions](/docs/filters/functions), [ESM](/docs/filters/esm), and [Return](/docs/filters/return), using identity-based comparison operators (aka `==` becomes `===`), and automatically underscoring instance variables (`@x` becomes `this._x`).

So that's exactly what we built. By simply adding `preset` to a configuration file or passing `preset: true` or `--preset` to the Ruby API or CLI respectively, you can gain all the benefits of these common options. In addition, by writing your code to use the preset, you can ensure wider compatibility between projects and between tutorials/code samples and production workflows.

Even more to that point, we've introduced the idea of a "magic comment". By adding `# ruby2js: preset` to the top of a `.js.rb` file, you instruct Ruby2JS to use the preset configuration for that file. You can even add additional filters right in the magic comment, change the ES level, or disable a filter that comes with the preset. [Read the documentation here.](/docs/options)

We believe all of these features now mean that Ruby2JS code is easier to teach and easier to share. We took your feedback about these issues in the past to heart and are trying to make improvements for better DX.

## esbuild is faster using Ruby?!

[esbuild](https://esbuild.github.io) is a modern, fast, and easily-configured frontend bundling tool, and we want to support it as a "first-party" citizen in the Ruby2JS ecosystem.

esbuild is fast because its core code is written in Go, not JavaScript. Along similar lines, we discovered something extraordinary when testing the beta of the esbuild bundling package. When we tried spawning a process to transpile a file using the Ruby version of Ruby2JS, rather than the Opal/Node-powered JavaScript version, we discovered that it was actually faster! And not just a little bit faster…[almost 2x faster!](https://github.com/ruby2js/ruby2js/discussions/170)

Transpiling using the Ruby version also has the added benefit that the syntax of the code you write on the frontend matches the version of Ruby your project uses overall. Before, you could be using Ruby 3.2 in your overall stack but the "version of Ruby" (in fact the version of Opal) might be older. In fact, there's actually an outstanding issue that the version of Opal used to generate the JavaScript version of Ruby2JS is locked to an older version of Opal due to bugs introduced when upgrading. More on that below…

So, all in all, it makes sense to standardize around Ruby, even when using esbuild. After all, I would be shocked if anyone had an interest in writing Ruby2JS frontend code and using esbuild as a bundling tool who _didn't_ actually have Ruby installed for use in a Ruby-based web project. So why rely on Opal/Node if we don't have to?

## The Future of Ruby2JS

Which brings us to a broader topic: the future of this project.

[Sam Ruby](http://intertwingly.net/blog/), a well-known figure in the Ruby community and the brains behind Ruby2JS for many years, stepped down as an active maintainer in 2021. This effectively left me as the sole maintainer of Ruby2JS—and not only the sole maintainer, but by and large the _only_ active contributor to Ruby2JS.

I had started contributing to the project in 2020, and through much trial-and-error and helpful mentorship from Sam, I eventually learned my way around the codebase enough to help usher in a few improvements to the feature set as well as set up this Bridgetown documentation site. It was an amazing experience, and I'd like to thank Sam publicly for his trust in (and patience with!) me.

**Here's the deal:** I love this project and sincerely hope to continue to see it fill an important role in the niche of "Ruby frontend web developers" as [I like to consider myself to be](https://www.fullstackruby.dev).

But the fact of the matter is I have my hands very full with the [Bridgetown project](https://www.bridgetownrb.com), and my ability to devote much attention to Ruby2JS is limited. In addition, what attention I _can_ devote to Ruby2JS is mostly relegated to the use cases for which Ruby2JS is personally useful to me. I'm not saying that's ideal. It just is what it is.

So because I _primarily_ use Ruby2JS for writing web components (usually using [Lit](https://lit.dev)) and bundling using esbuild, that is the principal scope I intend to maintain going forward. I would also argue that it's a very ergonomic and obvious way to make the most of Ruby2JS as a web developer building projects (as I do) with Rails or Bridgetown.

Thus I have decided to deprecate quite a number of features ("filters" and other integration points) which will be removed officially by the time Ruby2JS 6.0 is released. I don't have any immediate release date for that, but for the sake of discussion let's assume it will happen towards the end of this year.

The list of deprecated features is as follows:

* jQuery filter
* JSX filter
* matchAll filter (only necessary for ES < 2020)
* minitest-jasmine filter
* Preact filter
* React filter
* Require filter
* Underscore filter
* Vue filter
* CGI server integration
* ExecJS integration
* Haml integration
* Rails integration (outside of the new "jsbundling" esbuild pipeline)
* Sinatra integration (as a view template type)
* Sprockets integration
* "use strict" option (all modern ESM code is considered strict anyway)
* Webpack loader

In addition, I am actively looking for a maintainer to own the [Rollup and Vite plugins](https://github.com/ruby2js/ruby2js/tree/master/packages) for transpiling Ruby2JS code via those bundlers. I don't myself use Rollup/Vite, but I understand they're quite popular as an alternative to using esbuild directly. They still need to be upgraded to use Ruby rather than Node for the transpilation (like esbuild).

If any of these stand out to you as having a _serious impact_ on current production workflows, let's talk about possible strategies—either migrations to a better solution, or extracting features out to their own repo. For example, I simply have no interest in maintaining a React filter. I don't recommend people adopt React in new projects as a general rule, and if they do, then I recommend they use the Next.js framework because it just makes React much, much better. React + Ruby2JS is not a solution I can, in all good conscience, promote.

**However**, if someone _really_ needs a React filter long into the future for their projects, I'd be happy to help extract this functionality out to a separate gem with fresh open source governance. Again, that holds true for any of the deprecated features listed above.

The alternative to this approach, _and one I strongly considered_, would be for me to step down myself as a maintainer of Ruby2JS and seek someone else in the community to come onboard instead. I decided against this move for several reasons:

* I still really enjoy writing Ruby2JS code and singing the praises of the project.
* This is a pretty gnarly codebase to wrap your head around, and I had the benefit of being mentored by Sam Ruby himself. For someone to come in fresh and begin to make sizable contributions, that's a tall order—especially with the variety of JS packages now in the project as well. There's also a fair bit of technical debt that has no clear upgrade path at present. For example:
* We're locked into an old version of Opal for compiling the JavaScript version of the Ruby2JS compiler. Over time, this will result in the Node version of Ruby2JS falling farther and farther behind relative to its native Ruby counterpart. It may mean that, at some future date, we sunset this other than for trivial use (such as the online interactive demos)—or we figure out why the transpiler is broken on newer version of Opal which will take a considerable amount of time (I've failed after two separate attempts).
* And as mentioned above, nobody else _has_ been contributing with any frequency.

So ultimately I gladly intend on continuing to act as lead maintainer for Ruby2JS—while significantly reducing the scope of the project down to what (in my opinion) it is best suited for and what I best understand. And beyond that, any additional features are quite welcome to be handled via Ruby2JS "plugins" by others in the community.

## The Future of Ruby on the Frontend

This brings me to my final and most general point regarding where we, the Ruby web developer community, are headed.

I have become fairly convinced with the release of [Ruby 3.2 and its brand-new WebAssembly support](https://ruby.github.io/ruby.wasm/) that **the future of Ruby on the frontend is Wasm**. This means [I forsee a day](https://www.fullstackruby.dev/podcast/7/) when writing _actual Ruby code_ and directly executing it in the browser will be feasible for a considerable number of ambitious projects.

In effect, this will render both Ruby2JS _and_ Opal obsolete. Why try to fiddle with various compile-to-JavaScript languages and syntaxes when you can simply write **Ruby** and run it?! That's obviously the ideal, even if today there are significant hurdles to overcome (most notably large Wasm payloads and simplistic Ruby<->JS APIs).

So I look forward to that day, even if it's still a few years away. In the meantime, I'm thrilled I can continue to write frontend code in a Ruby-like way using Ruby2JS. And I hope you are as well.

**Questions? Ideas? Suggestions?** Hop in our [GitHub Discussions](https://github.com/ruby2js/ruby2js/discussions) and let us know! And if you find an issue with Ruby2JS 5.1, please file an issue report so we can make Ruby2JS. Better yet, if you'd like to become a contributor yourself to Ruby2JS, we welcome your involvement and support!
