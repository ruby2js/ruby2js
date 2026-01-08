// Relation class for deferred query building
//
// Accumulates query state through method chaining and executes
// only when awaited or when a terminal method is called.
//
// Usage:
//   const users = await User.where({active: true}).order('name').limit(10);
//   const count = await User.where({role: 'admin'}).count();
//   const first = await User.order({created_at: 'desc'}).first();

export class Relation {
  constructor(modelClass) {
    this.model = modelClass;
    this._conditions = [];
    this._notConditions = [];
    this._orConditions = [];
    this._order = null;
    this._limit = null;
    this._offset = null;
    this._select = null;
    this._distinct = false;
  }

  // --- Chainable methods (return new Relation) ---

  where(conditions) {
    const rel = this._clone();
    rel._conditions.push(conditions);
    return rel;
  }

  order(options) {
    const rel = this._clone();
    rel._order = options;
    return rel;
  }

  limit(n) {
    const rel = this._clone();
    rel._limit = n;
    return rel;
  }

  offset(n) {
    const rel = this._clone();
    rel._offset = n;
    return rel;
  }

  // Negation: where.not({role: 'guest'}) or User.not({deleted: true})
  not(conditions) {
    const rel = this._clone();
    rel._notConditions.push(conditions);
    return rel;
  }

  // OR composition: User.where({admin: true}).or(User.where({moderator: true}))
  // Can also accept conditions directly: User.where({admin: true}).or({moderator: true})
  or(conditionsOrRelation) {
    const rel = this._clone();
    if (conditionsOrRelation instanceof Relation) {
      // Merge conditions from the other relation
      rel._orConditions.push(conditionsOrRelation._conditions);
    } else {
      // Treat as simple conditions
      rel._orConditions.push([conditionsOrRelation]);
    }
    return rel;
  }

  // --- Terminal methods (execute query) ---

  async first() {
    const results = await this.limit(1).toArray();
    return results[0] || null;
  }

  async last() {
    const rel = this._clone();
    // Reverse the order, defaulting to id desc if no order specified
    rel._order = rel._order ? this._reverseOrder(rel._order) : { id: 'desc' };
    const results = await rel.limit(1).toArray();
    return results[0] || null;
  }

  async count() {
    return this.model._executeCount(this);
  }

  async toArray() {
    return this.model._executeRelation(this);
  }

  // find() within the relation's scope
  async find(id) {
    const rel = this._clone();
    rel._conditions.push({ id });
    const results = await rel.limit(1).toArray();
    if (results.length === 0) {
      throw new Error(`${this.model.name} not found with id=${id}`);
    }
    return results[0];
  }

  // findBy() within the relation's scope
  async findBy(conditions) {
    const rel = this.where(conditions);
    const results = await rel.limit(1).toArray();
    return results[0] || null;
  }

  // --- Thenable interface (enables await) ---

  then(resolve, reject) {
    return this.toArray().then(resolve, reject);
  }

  // Support for-await-of iteration
  async *[Symbol.asyncIterator]() {
    const results = await this.toArray();
    for (const record of results) {
      yield record;
    }
  }

  // --- Internal ---

  _clone() {
    const rel = new Relation(this.model);
    rel._conditions = [...this._conditions];
    rel._notConditions = [...this._notConditions];
    rel._orConditions = [...this._orConditions];
    rel._order = this._order;
    rel._limit = this._limit;
    rel._offset = this._offset;
    rel._select = this._select;
    rel._distinct = this._distinct;
    return rel;
  }

  _reverseOrder(order) {
    if (typeof order === 'string') {
      return { [order]: 'desc' };
    }
    const [col, dir] = Object.entries(order)[0];
    return { [col]: dir === 'desc' ? 'asc' : 'desc' };
  }
}
