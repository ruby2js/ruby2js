---
order: 19
title: Nokogiri
top_section: Filters
category: nokogiri
---

The **Nokogiri** filter allows the web DOM API to behave much like the API of the [Nokogiri gem](https://nokogiri.org).

## List of Transformations

{% capture caret %}<sl-icon name="caret-right-fill"></sl-icon>{% endcapture %}

{:.functions-list}
* `add_child` {{ caret }} `appendChild`
* `add_next_sibling` {{ caret }} `node.parentNode.insertBefore(sibling, node.nextSibling)`
* `add_previous_sibling` {{ caret }} `node.parentNode.insertBefore(sibling, node)`
* `after` {{ caret }} `node.parentNode.insertBefore(sibling, node.nextSibling)`
* `at` {{ caret }} `querySelector`
* `attr` {{ caret }} `getAttribute`
* `attribute` {{ caret }} `getAttributeNode`
* `before` {{ caret }} `node.parentNode.insertBefore(sibling, node)`
* `cdata?` {{ caret }} `node.nodeType === Node.CDATA_SECTION_NODE`
* `children` {{ caret }} `childNodes`
* `comment?` {{ caret }} `node.nodeType === Node.COMMENT_NODE`
* `content` {{ caret }} `textContent`
* `create_element` {{ caret }} `createElement`
* `document` {{ caret }} `ownerDocument`
* `element?` {{ caret }} `node.nodeType === Node.ELEMENT_NODE`
* `fragment?` {{ caret }} `node.nodeType === Node.FRAGMENT_NODE`
* `get_attribute` {{ caret }} `getAttribute`
* `has_attribute` {{ caret }} `hasAttribute`
* `inner_html` {{ caret }} `innerHTML`
* `key?` {{ caret }} `hasAttribute`
* `name` {{ caret }} `nextSibling`
* `next` {{ caret }} `nodeName`
* `next=` {{ caret }} `node.parentNode.insertBefore(sibling,node.nextSibling)`
* `next_element` {{ caret }} `nextElement`
* `next_sibling` {{ caret }} `nextSibling`
* `Nokogiri::HTML5` {{ caret }} `new JSDOM().window.document`
* `Nokogiri::HTML5.parse` {{ caret }} `new JSDOM().window.document`
* `Nokogiri::HTML` {{ caret }} `new JSDOM().window.document`
* `Nokogiri::HTML.parse` {{ caret }} `new JSDOM().window.document`
* `Nokogiri::XML::Node.new` {{ caret }} `document.createElement()`
* `parent` {{ caret }} `parentNode`
* `previous=` {{ caret }} `node.parentNode.insertBefore(sibling, node)`
* `previous_element` {{ caret }} `previousElement`
* `previous_sibling` {{ caret }} `previousSibling`
* `processing_instruction?` {{ caret }} `node.nodeType === Node.PROCESSING_INSTRUCTION_NODE`
* `remove_attribute` {{ caret }} `removeAttribute`
* `root` {{ caret }} `documentElement`
* `search` {{ caret }} `querySelectorAll`
* `set_attribute` {{ caret }} `setAttribute`
* `text?` {{ caret }} `node.nodeType === Node.TEXT_NODE`
* `text` {{ caret }} `textContent`
* `to_html` {{ caret }} `outerHTML`

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/nokogiri_spec.rb).
{% endrendercontent %}