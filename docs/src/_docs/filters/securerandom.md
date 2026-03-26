---
order: 365
title: SecureRandom
top_section: Filters
category: securerandom
---

The **SecureRandom** filter maps Ruby's `SecureRandom` class to the [Web Crypto API](https://developer.mozilla.org/en-US/docs/Web/API/Crypto), which is available in all modern browsers and Node.js. No npm dependencies required.

## List of Transformations

{% capture caret %}<sl-icon name="caret-right-fill"></sl-icon>{% endcapture %}

{:.functions-list}
* `SecureRandom.uuid` {{ caret }} `crypto.randomUUID()`
* `SecureRandom.alphanumeric(n)` {{ caret }} helper using `crypto.getRandomValues`
* `SecureRandom.hex(n)` {{ caret }} helper using `crypto.getRandomValues`
* `SecureRandom.random_number` {{ caret }} helper using `crypto.getRandomValues`
* `SecureRandom.random_number(n)` {{ caret }} helper using `crypto.getRandomValues`
* `SecureRandom.base64(n)` {{ caret }} helper using `crypto.getRandomValues`

Default length is 16 when not specified (matching Ruby's defaults).

## Examples

```ruby
# Generate a UUID
token = SecureRandom.uuid
```

```js
let token = crypto.randomUUID()
```

```ruby
# Generate a random alphanumeric string
code = SecureRandom.alphanumeric(12)
```

```js
let code = _secureRandomAlphanumeric(12)
```

```ruby
# Generate a random hex string
key = SecureRandom.hex(32)
```

```js
let key = _secureRandomHex(32)
```

Helper functions are automatically prepended to the file when needed. Each helper is only included once, even if multiple `SecureRandom` calls are made.
