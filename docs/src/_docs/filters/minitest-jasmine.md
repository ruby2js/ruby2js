---
order: 19
kitle: minitest-jasmine
top_section: Filters
category: minitest
---

The **minitest-jasmine** filter is for users of the [Jasmine](https://jasmine.github.io) behavior-driven test framework. It: 

* maps subclasses of `Minitest::Test` to `describe` calls
* maps `test_` methods inside subclasses of `Minitest::Test` to `it` calls
* maps `setup`, `teardown`, `before`, and `after` calls to `beforeEach`
  and `afterEach` calls
* maps `assert` and `refute` calls to `expect`...`toBeTruthy()` and
  `toBeFalsy` calls
* maps `assert_equal`, `refute_equal`, `.must_equal` and `.cant_equal`
  calls to `expect`...`toBe()` calls
* maps `assert_in_delta`, `refute_in_delta`, `.must_be_within_delta`,
  `.must_be_close_to`, `.cant_be_within_delta`, and `.cant_be_close_to`
  calls to `expect`...`toBeCloseTo()` calls
* maps `assert_includes`, `refute_includes`, `.must_include`, and
  `.cant_include` calls to `expect`...`toContain()` calls
* maps `assert_match`, `refute_match`, `.must_match`, and `.cant_match`
  calls to `expect`...`toMatch()` calls
* maps `assert_nil`, `refute_nil`, `.must_be_nil`, and `.cant_be_nill` calls
  to `expect`...`toBeNull()` calls
* maps `assert_operator`, `refute_operator`, `.must_be`, and `.cant_be`
    calls to `expect`...`toBeGreaterThan()` or `toBeLessThan` calls

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/minitest_jasmine_spec.rb).
{% endrendercontent %}
