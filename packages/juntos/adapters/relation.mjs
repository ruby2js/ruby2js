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
    this._group = null;    // GROUP BY column(s)
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
  // Supports nested: Card.joins({entry: [:lead, :follow]})
  joins(...associations) {
    const rel = this._clone();
    rel._joins = [...rel._joins, ...associations];
    return rel;
  }

  // GROUP BY column(s): User.group('status').count() → {active: 5, inactive: 2}
  group(...columns) {
    const rel = this._clone();
    rel._group = columns.length === 1 ? columns[0] : columns;
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
    if (this._group) {
      return this.model._executeGroupCount(this);
    }
    return this.model._executeCount(this);
  }

  // Aggregate: sum of a column. When grouped, returns {key: sum}.
  async sum(col) {
    if (this._group) {
      return this.model._executeGroupAggregate(this, 'SUM', col);
    }
    return this.model._executeAggregate(this, 'SUM', col);
  }

  // Check if any records exist: User.where({admin: true}).exists()
  async exists() {
    return this.model._executeExists(this);
  }

  // Alias for exists: User.where({admin: true}).any()
  async any() {
    return this.exists();
  }

  // Return values instead of models: User.pluck('name') or User.pluck('id', 'name')
  async pluck(...columns) {
    return this.model._executePluck(this, columns);
  }

  // Return a single value: User.where({admin: true}).pick('name') → 'Alice'
  async pick(...columns) {
    const results = await this.model._executePluck(this.limit(1), columns);
    if (results.length === 0) return null;
    return results[0];
  }

  // Return exactly one record; raises if zero or more than one
  async sole() {
    const results = await this.limit(2).toArray();
    if (results.length === 0) {
      throw new Error(`${this.model.name}: no records found`);
    }
    if (results.length > 1) {
      throw new Error(`${this.model.name}: more than one record found`);
    }
    return results[0];
  }

  async toArray() {
    return this.model._executeRelation(this);
  }

  // Aggregate: maximum value of a column
  async maximum(col) {
    return this.model._executeAggregate(this, 'MAX', col);
  }

  // Aggregate: minimum value of a column
  async minimum(col) {
    return this.model._executeAggregate(this, 'MIN', col);
  }

  // Update all matching records (direct SQL, no callbacks)
  // Usage: User.where({role: 'guest'}).updateAll({status: 'inactive'})
  async updateAll(attrs) {
    return this.model._executeUpdateAll(this, attrs);
  }

  // Destroy all matching records (loads each, calls destroy for callbacks)
  async destroyAll() {
    const records = await this.toArray();
    for (const record of records) {
      await record.destroy();
    }
    return records;
  }

  // Delete all matching records (direct SQL, no callbacks)
  async deleteAll() {
    return this.model._executeDelete(this);
  }

  // Find or create within this relation's scope
  async findOrCreateBy(attrs) {
    const existing = await this.findBy(attrs);
    if (existing) return existing;
    // Merge relation conditions into create attrs
    const createAttrs = { ...attrs };
    for (const cond of this._conditions) {
      Object.assign(createAttrs, cond);
    }
    return this.model.create(createAttrs);
  }

  // Find by conditions, throw if not found (Rails find_by!)
  async findByBang(conditions) {
    const result = await this.findBy(conditions);
    if (!result) {
      throw new Error(`${this.model.name} not found`);
    }
    return result;
  }

  // Find and destroy records matching conditions
  async destroyBy(conditions) {
    const records = await this.where(conditions).toArray();
    for (const record of records) {
      await record.destroy();
    }
    return records;
  }

  // Snake case aliases
  update_all(attrs) { return this.updateAll(attrs); }
  destroy_all() { return this.destroyAll(); }
  delete_all() { return this.deleteAll(); }
  find_or_create_by(attrs) { return this.findOrCreateBy(attrs); }
  find_by_bang(conditions) { return this.findByBang(conditions); }
  destroy_by(conditions) { return this.destroyBy(conditions); }

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

  // --- Introspection ---

  // Returns { sql, values } without executing the query.
  // Requires the model to have _buildRelationSQL (i.e., extends ActiveRecordSQL).
  toSQL() {
    if (typeof this.model._buildRelationSQL !== 'function') {
      throw new Error('toSQL() requires a model that extends ActiveRecordSQL');
    }
    return this.model._buildRelationSQL(this);
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
    rel._group = this._group;
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
