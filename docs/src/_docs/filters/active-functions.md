---
order: 10
title: ActiveFunctions
top_section: Filters
category: active-functions
---

The **ActiveFunctions** filter provides functionality inspired by Rails' ActiveSupport. It works in conjunction with the tiny NPM dependency [`@ruby2js/active-functions`](https://github.com/ruby2js/ruby2js/tree/master/packages/active-functions) which must be added to your application.

{% rendercontent "docs/note", type: "warning" %}
Note: this filter is currently under active (😏) development with more functions to come!
{% endrendercontent %}

* `value.blank?` becomes `blank$(value)`
* `value.present?` becomes `present$(value)`
* `value.presence` becomes `presence$(value)`

Note: these conversions are only done if `eslevel` >= 2015. Import statements
will be added to the top of the code output automatically. By default they
will be `@ruby2js/active-functions`, but you can pass an `import_from_skypack: true` option to `convert` to use the Skypack CDN instead.

