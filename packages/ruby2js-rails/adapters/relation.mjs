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
    this._rawConditions = [];  // For raw SQL: ['updated_at > ?', timestamp]
    this._notConditions = [];
    this._orConditions = [];
    this._order = null;
    this._limit = null;
    this._offset = null;
    this._select = null;
    this._distinct = false;
    this._includes = [];
    this._joins = [];      // INNER JOIN associations
    this._missing = [];    // LEFT JOIN ... WHERE id IS NULL (where().missing())
  }

  // --- Chainable methods (return new Relation) ---

  // where({active: true}) - hash conditions
  // where('updated_at > ?', timestamp) - raw SQL with placeholder
  // where('status = ? AND role = ?', 'active', 'admin') - multiple placeholders
  where(conditionOrSql, ...values) {
    const rel = this._clone();
    if (conditionOrSql == null) {
      // No-op: where() with no args returns a chainable relation (like Rails)
      return rel;
    }
    if (typeof conditionOrSql === 'string') {
      // Raw SQL condition
      rel._rawConditions.push({ sql: conditionOrSql, values });
    } else {
      // Hash condition
      rel._conditions.push(conditionOrSql);
    }
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

  // Select specific columns: User.select('id', 'name')
  select(...columns) {
    const rel = this._clone();
    rel._select = columns;
    return rel;
  }

  // Return distinct results: User.distinct()
  distinct() {
    const rel = this._clone();
    rel._distinct = true;
    return rel;
  }

  // Eager load associations: User.includes('posts') or User.includes('posts', 'comments')
  // Also supports nested includes: User.includes({ posts: 'comments' }) or User.includes({ posts: ['comments', 'tags'] })
  includes(...associations) {
    const rel = this._clone();
    rel._includes = [...rel._includes, ...associations];
    return rel;
  }

  // INNER JOIN on an association: Card.joins("closure")
  joins(...associations) {
    const rel = this._clone();
    rel._joins = [...rel._joins, ...associations];
    return rel;
  }

  // LEFT JOIN ... WHERE id IS NULL: Card.where().missing("closure")
  // Finds records that do NOT have the associated record.
  missing(...associations) {
    const rel = this._clone();
    rel._missing = [...rel._missing, ...associations];
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

  // Check if any records exist: User.where({admin: true}).exists()
  async exists() {
    return this.model._executeExists(this);
  }

  // Return values instead of models: User.pluck('name') or User.pluck('id', 'name')
  async pluck(...columns) {
    return this.model._executePluck(this, columns);
  }

  async toArray() {
    return this.model._executeRelation(this);
  }

  // Alias for Rails compatibility: Article.includes(:comments).all
  all() {
    return this;
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
    rel._rawConditions = [...this._rawConditions];
    rel._notConditions = [...this._notConditions];
    rel._orConditions = [...this._orConditions];
    rel._order = this._order;
    rel._limit = this._limit;
    rel._offset = this._offset;
    rel._select = this._select;
    rel._distinct = this._distinct;
    rel._includes = [...this._includes];
    rel._joins = [...this._joins];
    rel._missing = [...this._missing];
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
