---
order: 10
title: ActiveFunctions
top_section: Filters
category: active-functions
---

The **ActiveFunctions** filter provides functionality inspired by (but not limited to) Rails' ActiveSupport. It works in conjunction with the tiny NPM dependency [`@ruby2js/active-functions`](https://github.com/ruby2js/ruby2js/tree/master/packages/active-functions) which must be added to your application.

{% rendercontent "docs/note", type: "warning" %}
Note: this filter is currently under active (😏) development with more functions to come!
{% endrendercontent %}

{% capture caret %}<sl-icon name="caret-right-fill"></sl-icon>{% endcapture %}

{:.functions-list}
* `value.blank?` {{ caret }} `blank$(value)`
* `value.present?` {{ caret }} `present$(value)`
* `value.presence` {{ caret }} `presence$(value)`
* `value.chomp` {{ caret }} `chomp$(value)`
* `value.chomp(suffix)` {{ caret }} `chomp$(value, suffix)`
* `value.delete_prefix(prefix)` {{ caret }} `delete_prefix$(value, prefix)`
* `value.delete_suffix(suffix)` {{ caret }} `delete_suffix$(value, suffix)`

Import statements will be added to the top of the code output automatically. By default they
will be `@ruby2js/active-functions`, but you can pass an `import_from_skypack: true` option to `convert` to use the Skypack CDN instead.

