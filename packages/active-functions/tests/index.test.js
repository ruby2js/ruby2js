import { blank$, present$, presence$ } from "../src"

// Truthy Tests

test ("blank undefined is true", () => {
  expect(blank$(undefined)).toBeTruthy()
})

test ("blank null is true", () => {
  expect(blank$(null)).toBeTruthy()
})

test ("blank string is true", () => {
  expect(blank$("")).toBeTruthy()
})

test ("blank array is true", () => {
  expect(blank$([])).toBeTruthy()
})

test ("blank object literal is true", () => {
  expect(blank$({})).toBeTruthy()
})

test ("blank Map is true", () => {
  expect(blank$(new Map())).toBeTruthy()
})

test ("blank Set is true", () => {
  expect(blank$(new Set())).toBeTruthy()
})

test ("blank false literal is true", () => {
  expect(blank$(false)).toBeTruthy()
})

test ("blank NaN is true", () => {
  expect(blank$(parseInt(""))).toBeTruthy()
})

// Falsy Tests

test ("blank string value is false", () => {
  expect(blank$("Hello")).toBeFalsy()
})

test ("blank number value is false", () => {
  expect(blank$(3.5)).toBeFalsy()
})

test ("blank array value is false", () => {
  expect(blank$([5])).toBeFalsy()
})

test ("blank object literal value is false", () => {
  expect(blank$({a: 1})).toBeFalsy()
})

test ("blank Map value is false", () => {
  const m = new Map()
  m.foo = "bar"
  expect(blank$(m)).toBeFalsy()
})

test ("blank Set value is false", () => {
  const s = new Set()
  s.add("bar")
  expect(blank$(s)).toBeFalsy()
})

test ("blank Set value is false", () => {
  class TestSetValue {}

  expect(blank$(new TestSetValue())).toBeFalsy()
})

test ("blank true value is false", () => {
  expect(blank$(true)).toBeFalsy()
})

// Present / Presence Tests

test ("present undefined is false", () => {
  expect(present$({}.nothingHere)).toBeFalsy()
})

test ("present string value is true", () => {
  expect(present$("hello")).toBeTruthy()
})

test ("presence returns null for blank value", () => {
  expect(presence$(undefined)).toBe(null)
})

test ("presence returns value for present value", () => {
  expect(presence$("abc")).toBe("abc")
})
