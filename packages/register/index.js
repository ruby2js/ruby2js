const { addHook } = require('pirates');
const Ruby2JS = require('@ruby2js/ruby2js');

let options = {};
let exts = ['.rb'];
let match = null;

function compileHook(code, file) {
  return Ruby2JS.convert(code, { ...options, file }).toString()
}

let revert = addHook(compileHook, {exts});

// Babel-like interface: pass configuration to the return value of the require
// function.
function register(config) {
  if (config.options) options = {...config.options};
  if (!config.only && !config.ignore && !config.extensions) return;

  if (config.extensions) exts = config.extensions;

  if (config.only) {
    if (config.only instanceof RegExp) {
      match = name => config.only.test(name)
    } else if (typeof config.only === 'function') {
      match = name => config.only(name)
    } else if (Array.isArray(config.only)) {
      match = name => config.only.every(condition => {
        if (condition instanceof RegExp) {
          return condition.test(name)
        } else if (typeof condition === 'function') {
          return condition(name)
        })
      }
    }
  } else if (config.ignore) {
    if (config.ignore instanceof RegExp) {
      match = name => !config.ignore.test(name)
    } else if (typeof config.ignore === 'function') {
      match = name => !config.ignore(name)
    } else if (Array.isArray(config.ignore)) {
      match = name => !config.ignore.some(condition => {
        if (condition instanceof RegExp) {
          return condition.test(name)
        } else if (typeof condition === 'function') {
          return condition(name)
        })
      }
    }
  }

  revert();
  revert = addHook(compileHook, { exts, match })
}

// Alternate interface: treat the return value of require as an object
Object.defineProperty(register, 'options', {
  get() {
    return options;
  },

  set(opts) {
    options = opts;
  }
})

Object.defineProperty(register, 'ignore', {
  set(ignore) {
    register({ ignore })
  }
})

Object.defineProperty(register, 'only', {
  set(only) {
    register({ only })
  }
})

module.exports = register;
