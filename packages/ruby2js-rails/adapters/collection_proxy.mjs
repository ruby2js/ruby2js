// CollectionProxy - mirrors Rails ActiveRecord::Associations::CollectionProxy
//
// Enables idiomatic Rails patterns like:
//   article.comments.size
//   article.comments.where({ active: true }).first
//   article.comments.build({ body: 'Hello' })
//
// Works with eager-loaded records (via includes) or lazy-loads on demand.

export class CollectionProxy {
  constructor(owner, association, AssocModel) {
    this._owner = owner;
    this._association = association;  // { name, type, foreignKey, className }
    this._model = AssocModel;
    this._loaded = false;
    this._records = null;
  }

  // --- Counting ---

  get size() {
    if (this._records) return this._records.length;
    return 0;  // Not loaded yet - use count() for async count
  }

  get length() {
    return this.size;
  }

  async count() {
    if (this._records) return this._records.length;
    const fk = this._association.foreignKey;
    return this._model.where({ [fk]: this._owner.id }).count();
  }

  get empty() {
    return this.size === 0;
  }

  // Alias for empty (Ruby's empty?)
  isEmpty() {
    return this.empty;
  }

  get any() {
    return this.size > 0;
  }

  // --- Building ---

  build(params = {}) {
    const fk = this._association.foreignKey;
    return new this._model({ ...params, [fk]: this._owner.id });
  }

  async create(params = {}) {
    const record = this.build(params);
    await record.save();
    if (this._records) this._records.push(record);
    return record;
  }

  // --- Finding ---

  async find(id) {
    // Find within association scope
    const fk = this._association.foreignKey;
    return this._model.where({ [fk]: this._owner.id, id }).first();
  }

  async first() {
    if (this._records && this._records.length > 0) {
      return this._records[0];
    }
    return this.toRelation().first();
  }

  async last() {
    if (this._records && this._records.length > 0) {
      return this._records[this._records.length - 1];
    }
    return this.toRelation().last();
  }

  // --- Chaining (returns Relation) ---

  where(conditions) {
    return this.toRelation().where(conditions);
  }

  order(options) {
    return this.toRelation().order(options);
  }

  limit(n) {
    return this.toRelation().limit(n);
  }

  offset(n) {
    return this.toRelation().offset(n);
  }

  includes(...associations) {
    return this.toRelation().includes(...associations);
  }

  select(...fields) {
    return this.toRelation().select(...fields);
  }

  // Convert to a scoped Relation for chaining
  toRelation() {
    const fk = this._association.foreignKey;
    return this._model.where({ [fk]: this._owner.id });
  }

  // Alias for toRelation
  all() {
    return this.toRelation();
  }

  // --- Enumerable ---

  [Symbol.iterator]() {
    return (this._records || [])[Symbol.iterator]();
  }

  forEach(fn) {
    return (this._records || []).forEach(fn);
  }

  map(fn) {
    return (this._records || []).map(fn);
  }

  filter(fn) {
    return (this._records || []).filter(fn);
  }

  find_by(fn) {
    return (this._records || []).find(fn);
  }

  reduce(fn, initial) {
    return (this._records || []).reduce(fn, initial);
  }

  some(fn) {
    return (this._records || []).some(fn);
  }

  every(fn) {
    return (this._records || []).every(fn);
  }

  // Array indexing
  at(index) {
    return (this._records || [])[index];
  }

  // --- Thenable (for await support) ---

  then(resolve, reject) {
    if (this._records) {
      return Promise.resolve(this._records).then(resolve, reject);
    }
    return this.toRelation().then(records => {
      this._records = records;
      this._loaded = true;
      return records;
    }).then(resolve, reject);
  }

  // --- Loading (used by eager loading) ---

  load(records) {
    this._records = records;
    this._loaded = true;
    return this;
  }

  get loaded() {
    return this._loaded;
  }

  get records() {
    return this._records || [];
  }

  // --- Array-like access ---

  toArray() {
    return this._records || [];
  }

  // Proxy array length for compatibility
  get [Symbol.toStringTag]() {
    return 'CollectionProxy';
  }
}
