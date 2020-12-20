export const blank$ = value => {
  if (typeof value == "undefined") return true
  
  if (value == null) return true
  
  if (typeof value == "string" && value === "") return true
  
  if (typeof value == "number") return false
  
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
