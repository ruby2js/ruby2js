---
layout: post
title: "The Ruby2JS Story: A Decade of Transpilation"
subtitle: From ES5 workarounds to self-hosting—how an open source project evolved through multiple maintainers over eleven years.
categories: updates
author: rubys
---

Ruby2JS began in October 2013, forked from Marcos Castoria's original `maca/Ruby2JS` project. The timing was notable: JavaScript was still in its ES5 era. Classes required prototype chain manipulation. Modules didn't exist—you used AMD, CommonJS, or globals. Destructuring? Arrow functions? Forget it.

The appeal of transpiling Ruby to JavaScript was straightforward: write elegant Ruby syntax and generate the verbose JavaScript that browsers understood.

## The Early Years (2013-2019)

Development was intense in the beginning—159 commits in just the final two months of 2013. The codebase grew steadily:

| Year | Commits | Notes |
|------|---------|-------|
| 2013 | 159 | Project launch |
| 2014 | 96 | Steady growth |
| 2015 | 161 | React filter added |
| 2016 | 11 | Activity slowdown |
| 2017 | 116 | Recovery |
| 2018 | 177 | ES2015 support finally added |
| 2019 | 57 | Tapering off |

The irony wasn't lost on anyone: ES2015 (ES6) shipped in June 2015, but Ruby2JS didn't add ES2015 class support until December 2017—over two years later. By then, JavaScript had native classes, modules, arrow functions, template literals, destructuring, and spread operators. The gap that Ruby2JS originally filled was closing.

## Jared White Enters (October 2020)

In October 2020, Jared White arrived and reinvigorated the project. His first commits landed on October 6, 2020, focused on tagged template literals and camelCase filter improvements.

What followed was remarkable. In just over a year, Jared:

- Built the **ruby2js.com website** using Bridgetown (launched December 2020)
- Drove **version 4.0.0** (February 2021) with major modernizations
- Added the **Stimulus filter** for Hotwire integration
- Created **LitElement support**
- Expanded the **preset system** for easier configuration
- Released **version 5.0.0** (May 2022)

The numbers tell the story. The project hit its peak activity with 451 commits in 2021—more than any previous year. Jared contributed 199 commits total, second only to my 1,615.

Jared brought something the project desperately needed: energy, vision, and a focus on modern web development patterns. The Bridgetown documentation site he built made Ruby2JS accessible to a whole new generation of developers.

## The Quiet Period (2022-2024)

After version 5.0.0, activity gradually slowed:

| Year | Commits |
|------|---------|
| 2022 | 65 |
| 2023 | 21 |
| 2024 | 7 |

By May 2024, version 5.1.2 shipped—the last release before a long pause. Opal remained stuck at version 1.1.1 due to a compilation issue that was never fully resolved. Bridgetown sat at 1.3.4. The live demos on ruby2js.com stopped working.

On January 23, 2025, Jared formally [announced his departure](https://github.com/ruby2js/ruby2js/discussions/227), acknowledging that "there are a number of PRs and issues stacking up" but explaining that his time was consumed by other open source projects, particularly Bridgetown itself. He graciously noted that he hadn't created the project and hadn't written most of the codebase—leaving the door open for renewed stewardship.

## Coming Home (November 2025)

My return was prompted by a practical need: [offline functionality for a Rails application](https://intertwingly.net/blog/2025/11/25/ERB-Stimulus-Offline.html). I found the project with 21 open issues and 7 pending pull requests. The demos were broken. Dependencies were years out of date.

Since November 27, 2025, there have been over 360 commits, **30 issues closed**, and **44 pull requests merged**.

**Infrastructure modernization:**
- Opal upgraded from 1.1.1 to 1.8
- Bridgetown upgraded from 1.3.4 to 2.0.5
- Pre-ES2020 support retired (ES2015-ES2019 removed)
- Prism parser support for Ruby 3.4+

**The self-hosting breakthrough:**
- Ruby2JS now transpiles *itself* to JavaScript
- A unified 200KB `ruby2js.mjs` bundle (no Ruby required)
- 245 tests passing against the JavaScript implementation
- Enables true dual-target development—same Ruby source running on server and browser

**New framework filters:**
- **ERB** and **HAML** template support
- **Turbo** for custom Turbo Stream actions
- **Alpine.js** component registration
- **ActionCable** WebSocket DSL
- **Jest** for RSpec-style testing syntax
- **Stimulus** enhanced with outlets support (3.x)

**Enhanced Ruby patterns:**
- Type introspection (`is_a?`, `instance_of?`, `respond_to?`)
- Class introspection (`obj.class`, `obj.class.name`, `superclass`)
- Module mixins (`include`, `extend`)

**New documentation:**
- Complete User's Guide for dual-target development
- Patterns, pragmas, and anti-patterns documentation
- Live demos throughout

The self-hosting work was particularly significant—proving that Ruby2JS can handle substantial, real-world Ruby code by successfully converting its own 60+ converter handlers and serializer to JavaScript.

## The Numbers

After 11 years:

- **1,901 total commits**
- **19 releases** (v3.6.0 through v5.1.2, with 6.0 in beta)
- **~60 AST node handlers**
- **~23 filters** (functions, esm, camelCase, react, stimulus, and more)

## Thank You, Jared

Jared White kept Ruby2JS alive and relevant during a critical period. His documentation work, his filters, his energy—they transformed a useful but aging tool into something modern developers could actually adopt. The project is better for his stewardship, and I'm grateful he held the torch when I couldn't.

Open source thrives on these handoffs. Sometimes you carry the load, sometimes you pass it on, and sometimes—years later—you pick it back up again.
