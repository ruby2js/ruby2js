// Console Filter - wraps ActiveRecord class methods with await
//
// In Ruby: Post.all, Post.where(published: true)
// Becomes: await Post.all(), await Post.where({published: true})
//
// This filter detects AR class methods called on constants and wraps them
// with await! to ensure proper async handling and parentheses.

import { Filter, registerFilter, s } from '../../selfhost/ruby2js.js';

// ActiveRecord class methods that need await
const AR_CLASS_METHODS = [
  'all', 'find', 'find_by', 'where', 'first', 'last',
  'count', 'create', 'create!', 'order', 'limit', 'offset',
  'includes', 'joins', 'select', 'distinct', 'pluck',
  'exists?', 'any?', 'none?', 'one?', 'many?',
  'sum', 'average', 'minimum', 'maximum',
  'update_all', 'delete_all', 'destroy_all'
];

// ActiveRecord instance methods that need await
const AR_INSTANCE_METHODS = [
  'save', 'save!', 'update', 'update!', 'destroy', 'destroy!', 'reload'
];

class Console extends Filter.Processor {
  _filter_init(...args) {
    this._parent._filter_init.call(this, ...args);
    return this;
  }

  on_send(node) {
    let [target, method, ...args] = node.children;
    const methodStr = method?.toString();

    // Check for AR class method on a constant: Post.all, Post.where(...)
    if (target?.type === 'const' && target.children[0] === null) {
      if (AR_CLASS_METHODS.includes(methodStr)) {
        // Use updated('await!') to wrap with await and force parentheses
        // Process children first, then wrap the result
        const processed = this._parent.on_send.call(this, node);
        return processed.updated('await!');
      }
    }

    // Check for chained AR methods: Post.where(...).first, Post.order(...).limit(5)
    if (target?.type === 'send' && AR_CLASS_METHODS.includes(methodStr)) {
      // Walk up the chain to find if it starts with a constant
      let chainStart = target;
      while (chainStart?.type === 'send') {
        chainStart = chainStart.children[0];
      }

      if (chainStart?.type === 'const' && chainStart.children[0] === null) {
        // This is a chained AR method, process then wrap with await
        const processed = this._parent.on_send.call(this, node);
        return processed.updated('await!');
      }
    }

    // Check for AR instance methods: post.save, post.update(...)
    if (AR_INSTANCE_METHODS.includes(methodStr)) {
      const processed = this._parent.on_send.call(this, node);
      return processed.updated('await!');
    }

    return this._parent.on_send.call(this, node);
  }
}

registerFilter('Console', Console.prototype);

export { Console, AR_CLASS_METHODS, AR_INSTANCE_METHODS };
