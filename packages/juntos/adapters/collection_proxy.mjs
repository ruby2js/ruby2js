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
    this._association = association;  // { name, type, foreignKey, foreignType?, ownerType? }
    this._model = AssocModel;
    this._loaded = false;
    this._records = null;
  }

  // Build scope conditions for this association
  // Normal: { article_id: owner.id }
  // Polymorphic: { eventable_id: owner.id, eventable_type: "Card" }
  _scopeConditions() {
    const fk = this._association.foreignKey;
    const conditions = { [fk]: this._owner.id };
    if (this._association.foreignType) {
      conditions[this._association.foreignType] = this._association.ownerType;
    }
    return conditions;
  }

  // --- Counting ---

  // size() - smart like Rails: returns cached count or does COUNT query
  // Usage: await article.comments.size()
  size() {
    if (this._records) return this._records.length;
    return this._model.where(this._scopeConditions()).count();
  }

  // count() - always does COUNT query (ignores cache), like Rails
  // Usage: await article.comments.count()
  async count() {
    return this._model.where(this._scopeConditions()).count();
  }

  // length property - for (await proxy).length after loading records
  // This is accessed on the records array, not the proxy, but keep for direct access
  get length() {
    if (this._records) return this._records.length;
    return 0;
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
    return new this._model({ ...params, ...this._scopeConditions() });
  }

  async create(params = {}) {
    const record = this.build(params);
    await record.save();
    if (!this._records) this._records = [];
    this._records.push(record);
    return record;
  }

  // --- Finding ---

  async find(id) {
    // Find within association scope
    return this._model.where({ ...this._scopeConditions(), id }).first();
  }

  async first() {
    if (this._loaded) {
      return this._records?.[0] || null;
    }
    return this.toRelation().first();
  }

  async last() {
    if (this._loaded) {
      const len = this._records?.length || 0;
      return len > 0 ? this._records[len - 1] : null;
    }
    return this.toRelation().last();
  }

  // --- Bulk operations ---

  async updateAll(attrs) {
    return this.toRelation().updateAll(attrs);
  }

  async destroyAll() {
    return this.toRelation().destroyAll();
  }

  async deleteAll() {
    return this.toRelation().deleteAll();
  }

  async findOrCreateBy(attrs) {
    return this.toRelation().findOrCreateBy(attrs);
  }

  async destroyBy(conditions) {
    return this.toRelation().destroyBy(conditions);
  }

  // Chaining methods that return Relation
  group(...columns) {
    return this.toRelation().group(...columns);
  }

  pluck(...columns) {
    return this.toRelation().pluck(...columns);
  }

  // Snake case aliases
  update_all(attrs) { return this.updateAll(attrs); }
  destroy_all() { return this.destroyAll(); }
  delete_all() { return this.deleteAll(); }
  find_or_create_by(attrs) { return this.findOrCreateBy(attrs); }
  destroy_by(conditions) { return this.destroyBy(conditions); }

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
    return this._model.where(this._scopeConditions());
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

  find_by(conditions) {
    // If conditions is a plain object, delegate to scoped query (like Rails find_by)
    if (conditions && typeof conditions === 'object' && !Array.isArray(conditions) && typeof conditions !== 'function') {
      return this.toRelation().findBy(conditions);
    }
    // If it's a function, use as Array.find callback
    return (this._records || []).find(conditions);
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

  // Array indexing (supports negative indices like Ruby)
  at(index) {
    return (this._records || []).at(index);
  }

  slice(start, end) {
    return (this._records || []).slice(start, end);
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

class _ThroughProxy {
  constructor(owner, throughName, sourceKey, TargetModel) {
    this._owner = owner;
    this._throughName = throughName;  // e.g., "studio1_pairs"
    this._sourceKey = sourceKey;      // e.g., "studio1_id"
    this._model = TargetModel;        // e.g., Studio class
    this._loaded = false;
    this._records = null;
  }

  async _load() {
    if (this._loaded) return this._records;
    const intermediates = await this._owner[this._throughName];
    const ids = [...new Set(
      intermediates.map(r => r.attributes?.[this._sourceKey] ?? r[this._sourceKey])
    )];
    this._records = ids.length > 0 ? await this._model.where({id: ids}) : [];
    this._loaded = true;
    return this._records;
  }

  then(resolve, reject) {
    return this._load().then(resolve, reject);
  }

  pluck(...cols) {
    return this._load().then(records => {
      if (cols.length === 1) return records.map(r => r[cols[0]]);
      return records.map(r => cols.map(c => r[c]));
    });
  }

  async count() { return (await this._load()).length; }
  async first() { return (await this._load())[0] || null; }
  async last() { const r = await this._load(); return r.length > 0 ? r[r.length - 1] : null; }

  [Symbol.iterator]() { return (this._records || [])[Symbol.iterator](); }
  map(fn) { return (this._records || []).map(fn); }
  filter(fn) { return (this._records || []).filter(fn); }
  slice(start, end) { return (this._records || []).slice(start, end); }
  get length() { return this._records?.length ?? 0; }
  get loaded() { return this._loaded; }
  get records() { return this._records || []; }
}

CollectionProxy.through = function(owner, throughName, sourceKey, TargetModel) {
  return new _ThroughProxy(owner, throughName, sourceKey, TargetModel);
};
