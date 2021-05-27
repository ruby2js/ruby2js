export const blank$ = value => {
  if (typeof value == "undefined") return true

  if (value == null) return true

  if (typeof value == "string" && value === "") return true

  // This one's tricky. Any valid number including 0 is not blank, *except* if it's
  // a NaN value, in which case that *is* blank
  if (typeof value == "number") return Object.is(value, NaN)

  if (value.toString() === "[object Set]") return value.size == 0

  if (value.constructor.toString().includes("class ")) return false

  if (value === false) return true
  if (value === true) return false

  if (Object.keys(value).length === 0) return true

  return false
}

export const present$ = value => {
  return !blank$(value)
}

export const presence$ = value => {
  return present$(value) ? value : null
}

// Copied from https://github.com/sindresorhus/escape-string-regexp/blob/main/index.js
function escapeStringRegexp(string) {
  if (typeof string !== 'string') {
    throw new TypeError('Expected a string');
  }

  // Escape characters with special meaning either inside or outside character sets.
  // Use a simple backslash escape when it’s always valid, and a `\xnn` escape when the simpler form would be disallowed by Unicode patterns’ stricter grammar.
  return string
    .replace(/[|\\{}()[\]^$+*?.]/g, '\\$&')
    .replace(/-/g, '\\x2d');
}

export const deletePrefix$ = (value, prefix) => {
  return value.replace(new RegExp(`^${escapeStringRegexp(prefix)}`), "")
}

export const deleteSuffix$ = (value, suffix) => {
  return value.replace(new RegExp(`${escapeStringRegexp(suffix)}$`), "")
}

export const chomp$ = (value, suffix = null) => {
  if (suffix) {
    return deleteSuffix$(value, suffix)
  } else {
    return value.replace(/\r?\n$/, "")
  }
}
