// Console Filter - translates ActiveRecord queries to Knex.js
//
// Ruby AR syntax:          Knex.js output:
// Post.all              → await knex('posts')
// Post.where(...)       → await knex('posts').where(...)
// Post.find(1)          → await knex('posts').where({id: 1}).first()
// Post.first            → await knex('posts').first()
// Post.last             → await knex('posts').orderBy('id', 'desc').first()
// Post.order(:col)      → await knex('posts').orderBy('col')
// Post.limit(n)         → await knex('posts').limit(n)
// Post.count            → await knex('posts').count()
//
// Chained queries only get await at the end:
// Post.where(...).first → await knex('posts').where(...).first()

import { Filter, registerFilter, s } from '../../selfhost/ruby2js.js';

// ActiveRecord class methods that start a query
const AR_QUERY_STARTERS = ['all', 'where', 'find', 'find_by', 'first', 'last', 'order', 'limit', 'offset', 'select', 'count'];

// AR methods that can be chained (intermediate, don't add await yet)
const AR_CHAINABLE = [
  'where', 'order', 'limit', 'offset', 'select', 'distinct',
  'includes', 'joins', 'group', 'having'
];

// AR methods that terminate a chain (final, add await here)
const AR_TERMINATORS = [
  'all', 'first', 'last', 'find', 'find_by', 'count', 'sum', 'average',
  'minimum', 'maximum', 'pluck', 'exists?', 'any?', 'none?', 'to_a'
];

// Simple inflection: Post → posts, User → users, Comment → comments
function tableize(modelName) {
  // Handle common irregular plurals
  const irregulars = {
    'Person': 'people',
    'Child': 'children',
    'Man': 'men',
    'Woman': 'women'
  };

  if (irregulars[modelName]) return irregulars[modelName];

  // Convert CamelCase to snake_case and pluralize
  const snake = modelName
    .replace(/([A-Z])/g, '_$1')
    .toLowerCase()
    .replace(/^_/, '');

  // Simple pluralization
  if (snake.endsWith('y') && !['ay', 'ey', 'oy', 'uy'].some(v => snake.endsWith(v))) {
    return snake.slice(0, -1) + 'ies';
  }
  if (snake.endsWith('s') || snake.endsWith('x') || snake.endsWith('ch') || snake.endsWith('sh')) {
    return snake + 'es';
  }
  return snake + 's';
}

// Check if this node is the target of a chained method call
function isChainedInto(node, parent) {
  if (!parent || parent.type !== 'send') return false;
  return parent.children[0] === node;
}

class Console extends Filter.Processor {
  _filter_init(...args) {
    this._parent._filter_init.call(this, ...args);
    // Track parent nodes during processing
    this._nodeParent = null;
    return this;
  }

  on_send(node) {
    let [target, method, ...args] = node.children;
    const methodStr = method?.toString();

    // Check for AR query starting on a constant: Post.all, Post.where(...)
    if (target?.type === 'const' && target.children[0] === null) {
      const modelName = target.children[1]?.toString();

      // Check if this is an AR query method
      if (AR_QUERY_STARTERS.includes(methodStr) || AR_CHAINABLE.includes(methodStr)) {
        const tableName = tableize(modelName);

        // Check if this is an intermediate step in a chain
        // We need to look at what method is being called ON this result
        const isIntermediate = this.isIntermediateInChain(node);

        return this.buildKnexQuery(tableName, methodStr, args, !isIntermediate);
      }
    }

    // Check for chained methods on an existing query
    if (target?.type === 'send') {
      const chainInfo = this.getChainInfo(target);

      if (chainInfo && (AR_CHAINABLE.includes(methodStr) || AR_TERMINATORS.includes(methodStr))) {
        // Process the base query WITHOUT await (we'll add it at the end)
        const baseQuery = this.processWithoutAwait(target);

        // Check if THIS call is the final one in the chain
        const isIntermediate = this.isIntermediateInChain(node);

        return this.appendToKnexQuery(baseQuery, methodStr, args, !isIntermediate);
      }
    }

    return this._parent.on_send.call(this, node);
  }

  // Check if this node is an intermediate step (has more methods chained after it)
  isIntermediateInChain(node) {
    // We'll use a marker to detect this during parent processing
    // For now, check if this node is the receiver of another send
    // This requires walking the AST, but we can use a simpler heuristic:
    // Terminators are always final, chainable methods might not be
    const [, method] = node.children;
    const methodStr = method?.toString();

    // If it's a terminator, it's always final
    if (AR_TERMINATORS.includes(methodStr)) {
      return false;
    }

    // For chainable methods on a constant (like Post.where),
    // we need to check if there's a parent send node
    // Since we don't have easy parent access, we'll handle this differently:
    // We'll NOT add await in buildKnexQuery for chainable methods,
    // and rely on the chain detection to add await only at the end
    return AR_CHAINABLE.includes(methodStr);
  }

  // Process a node but strip the await wrapper if present
  processWithoutAwait(node) {
    // Recursively process, but we control await in appendToKnexQuery
    let [target, method, ...args] = node.children;
    const methodStr = method?.toString();

    // If target is a constant, start the knex chain
    if (target?.type === 'const' && target.children[0] === null) {
      const modelName = target.children[1]?.toString();
      if (AR_QUERY_STARTERS.includes(methodStr) || AR_CHAINABLE.includes(methodStr)) {
        const tableName = tableize(modelName);
        return this.buildKnexQuery(tableName, methodStr, args, false); // false = no await
      }
    }

    // If target is another send, recurse
    if (target?.type === 'send') {
      const chainInfo = this.getChainInfo(target);
      if (chainInfo) {
        const baseQuery = this.processWithoutAwait(target);
        return this.appendToKnexQuery(baseQuery, methodStr, args, false); // false = no await
      }
    }

    return this._parent.on_send.call(this, node);
  }

  // Check if a node is part of an AR query chain
  getChainInfo(node) {
    if (node.type !== 'send') return null;

    let [target, method] = node.children;
    const methodStr = method?.toString();

    // If target is a constant, check if this is a query starter
    if (target?.type === 'const' && target.children[0] === null) {
      if (AR_QUERY_STARTERS.includes(methodStr) || AR_CHAINABLE.includes(methodStr)) {
        return { modelName: target.children[1]?.toString(), method: methodStr };
      }
    }

    // Recurse up the chain
    if (target?.type === 'send') {
      return this.getChainInfo(target);
    }

    return null;
  }

  // Build initial knex query from Model.method(args)
  buildKnexQuery(tableName, method, args, addAwait = true) {
    // Start with knex('tableName')
    const knexCall = s('send', null, 'knex', s('str', tableName));

    return this.appendToKnexQuery(knexCall, method, args, addAwait);
  }

  // Append a method to an existing knex query
  appendToKnexQuery(baseQuery, method, args, addAwait = true) {
    let result;

    switch (method) {
      case 'all':
        // knex('table') returns all by default
        result = baseQuery;
        break;

      case 'where':
        // .where(hash) → .where(hash)
        result = s('send', baseQuery, 'where', ...args.map(a => this.process(a)));
        break;

      case 'find':
        // .find(id) → .where({id: id}).first()
        const idArg = args[0];
        const whereHash = s('hash', s('pair', s('sym', 'id'), this.process(idArg)));
        const withWhere = s('send', baseQuery, 'where', whereHash);
        result = s('send', withWhere, 'first');
        break;

      case 'find_by':
        // .find_by(hash) → .where(hash).first()
        const withFindByWhere = s('send', baseQuery, 'where', ...args.map(a => this.process(a)));
        result = s('send', withFindByWhere, 'first');
        break;

      case 'first':
        // .first() → .first()
        result = s('send', baseQuery, 'first');
        break;

      case 'last':
        // .last() → .orderBy('id', 'desc').first()
        const orderedDesc = s('send', baseQuery, 'orderBy', s('str', 'id'), s('str', 'desc'));
        result = s('send', orderedDesc, 'first');
        break;

      case 'order':
        // .order(:col) → .orderBy('col')
        // .order(col: :desc) → .orderBy('col', 'desc')
        result = this.buildOrderBy(baseQuery, args);
        break;

      case 'limit':
        // .limit(n) → .limit(n)
        result = s('send', baseQuery, 'limit', ...args.map(a => this.process(a)));
        break;

      case 'offset':
        // .offset(n) → .offset(n)
        result = s('send', baseQuery, 'offset', ...args.map(a => this.process(a)));
        break;

      case 'count':
        // .count → .count('* as count')
        result = s('send', baseQuery, 'count', s('str', '* as count'));
        break;

      case 'pluck':
        // .pluck(:col) → .pluck('col')
        const pluckCol = args[0];
        const colName = pluckCol?.type === 'sym' ? pluckCol.children[0].toString() : this.process(pluckCol);
        result = s('send', baseQuery, 'pluck', typeof colName === 'string' ? s('str', colName) : colName);
        break;

      case 'select':
        // .select(:col1, :col2) → .select('col1', 'col2')
        const selectArgs = args.map(arg => {
          if (arg?.type === 'sym') {
            return s('str', arg.children[0].toString());
          }
          return this.process(arg);
        });
        result = s('send', baseQuery, 'select', ...selectArgs);
        break;

      case 'distinct':
        // .distinct → .distinct()
        result = s('send', baseQuery, 'distinct');
        break;

      default:
        // For unhandled methods, pass through
        result = s('send', baseQuery, method, ...args.map(a => this.process(a)));
    }

    // Only wrap with await if this is the final call in the chain
    if (addAwait) {
      return result.updated('await!');
    }
    return result;
  }

  // Handle order(:col) and order(col: :desc)
  buildOrderBy(baseQuery, args) {
    if (args.length === 0) {
      return s('send', baseQuery, 'orderBy', s('str', 'id'));
    }

    const arg = args[0];

    // order(:column)
    if (arg?.type === 'sym') {
      const colName = arg.children[0].toString();
      return s('send', baseQuery, 'orderBy', s('str', colName));
    }

    // order(column: :desc)
    if (arg?.type === 'hash') {
      const pair = arg.children[0];
      if (pair?.type === 'pair') {
        const [key, value] = pair.children;
        const colName = key?.type === 'sym' ? key.children[0].toString() : 'id';
        const direction = value?.type === 'sym' ? value.children[0].toString() : 'asc';
        return s('send', baseQuery, 'orderBy', s('str', colName), s('str', direction));
      }
    }

    // Fallback
    return s('send', baseQuery, 'orderBy', ...args.map(a => this.process(a)));
  }
}

registerFilter('Console', Console.prototype);

export { Console, tableize };
