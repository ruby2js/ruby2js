// Reference - A thenable proxy for belongs_to/has_one associations.
//
// When an association's cached instance is not set but the foreign key exists,
// the getter returns a Reference instead of a raw Promise. This provides:
//
// - Thenable: `await card.column` loads from DB and caches on the instance
// - Sync access: `card.column.value` returns the loaded instance (throws if not loaded)
// - FK access: `card.column.id` always available without loading
//
// Instance-level caching only — no global identity map, no request leaking.

export class Reference {
  constructor(modelClass, id, cacheCallback) {
    this._modelClass = modelClass;
    this._id = id;
    this._cacheCallback = cacheCallback;
    this._loaded = null;
  }

  // The foreign key is always available without a DB hit
  get id() {
    return this._id;
  }

  // Load the associated record from the database
  async load() {
    if (!this._loaded) {
      this._loaded = await this._modelClass.find(this._id);
      if (this._cacheCallback) this._cacheCallback(this._loaded);
    }
    return this._loaded;
  }

  // Makes the Reference awaitable: `const col = await card.column`
  then(resolve, reject) {
    return this.load().then(resolve, reject);
  }

  // Synchronous access — returns the loaded instance or throws
  get value() {
    if (!this._loaded) {
      throw new Error(
        `${this._modelClass.name} (id=${this._id}) not loaded. Use await or includes() first.`
      );
    }
    return this._loaded;
  }
}

// HasOneReference - like Reference but uses find_by instead of find
export class HasOneReference {
  constructor(modelClass, conditions, cacheCallback) {
    this._modelClass = modelClass;
    this._conditions = conditions;
    this._cacheCallback = cacheCallback;
    this._loaded = undefined; // undefined = not attempted, null = attempted but not found
  }

  async load() {
    if (this._loaded === undefined) {
      this._loaded = await this._modelClass.findBy(this._conditions);
      if (this._cacheCallback) this._cacheCallback(this._loaded);
    }
    return this._loaded;
  }

  then(resolve, reject) {
    return this.load().then(resolve, reject);
  }

  get value() {
    if (this._loaded === undefined) {
      throw new Error(
        `${this._modelClass.name} not loaded. Use await or includes() first.`
      );
    }
    return this._loaded;
  }

  // Delegate destroy to the loaded record (for safe-navigation: not_now&.destroy)
  async destroy() {
    const record = await this.load();
    if (record) {
      await record.destroy();
      // Clear the parent's cache so has_one getter returns null
      if (this._cacheCallback) this._cacheCallback(null);
    }
    return record;
  }
}
