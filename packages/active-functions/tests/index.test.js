import { blank$, present$, presence$, chomp$, deletePrefix$, deleteSuffix$ } from "../src"

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

// Chomp / Delete tests

test ("chomp with no argument", () => {
  expect(chomp$("st\nring\r\n")).toBe("st\nring")
  expect(chomp$("st\nring\n")).toBe("st\nring")
  expect(chomp$("st\nring")).toBe("st\nring")
  expect(chomp$("\nst\nring\n\n")).toBe("\nst\nring\n")
})

test ("chomp with argument", () => {
  expect(chomp$("st\nring", "ing")).toBe("st\nr")
  expect(chomp$("st\nrin+g", "in+g")).toBe("st\nr")
  expect(chomp$("from [a-z]+", "[a-z]+")).toBe("from ")
})

test ("delete_prefix", () => {
  expect(deletePrefix$("\nst\nring", "\n")).toBe("st\nring")
  expect(deletePrefix$("st\nring", "st\n")).toBe("ring")
  expect(deletePrefix$("[a-z]+ and beyond", "[a-z]+")).toBe(" and beyond")
  expect(deletePrefix$("[a-z]+[a-z]+ and beyond", "[a-z]+")).toBe("[a-z]+ and beyond")
  expect(deletePrefix$("[a-z]+[a-z]+ and beyond[a-z]+", "[a-z]+")).toBe("[a-z]+ and beyond[a-z]+")
})

test ("delete_suffix", () => {
  expect(deleteSuffix$("st\nring", "ing")).toBe("st\nr")
  expect(deleteSuffix$("st\nrin+g", "in+g")).toBe("st\nr")
  expect(deleteSuffix$("from [a-z]+", "[a-z]+")).toBe("from ")
})
