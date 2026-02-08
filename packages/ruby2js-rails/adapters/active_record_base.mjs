// ActiveRecord Base Class - Shared logic for all database adapters
//
// This file contains database-agnostic ActiveRecord functionality:
// - Validation system (errors, isValid, validates_*)
// - Instance method wrappers (save, update)
// - Association helpers (hasMany, belongsTo)
// - Attribute accessors
//
// Database-specific adapters extend this class and implement:
// - static get table() - database table access
// - static async all(), find(), findBy(), where(), first(), last(), count()
// - async _insert(), _update(), destroy(), reload()

// Base class for ActiveRecord models
export class ActiveRecordBase {
  static table_name = null;  // Override in subclass (Ruby convention)
  static columns = [];       // Override in subclass

  // Getter to support both tableName and table_name (JS vs Ruby convention)
  static get tableName() {
    return this.table_name;
  }

  // Getter/setter for id property access
  get id() {
    return this._id;
  }

  set id(value) {
    this._id = value;
  }

  constructor(attributes = {}) {
    this._id = attributes.id || null;
    this._persisted = !!attributes.id;
    this._changes = {};
    this._errors = { _all: [] };

    // Initialize attributes, but don't copy association objects (they have setters)
    // This prevents storing full objects in the database and avoids reconstruction issues
    this.attributes = {};
    for (const [key, value] of Object.entries(attributes)) {
      const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(this), key);
      if (descriptor?.get?._isAttrAccessor) {
        // Column attribute with attr_accessor - use setter (writes to this.attributes)
        this[key] = value;
      } else if (descriptor?.set) {
        // Association setter - only call with model instances
        // Don't copy to attributes - the setter will handle storing the FK
        if (value && typeof value === 'object' && 'id' in value && typeof value.id !== 'undefined') {
          this[key] = value;
        }
        // If value is a plain object with _id (from DB), skip - the FK should already be set
      } else {
        // Regular attribute - copy to attributes and set as property
        this.attributes[key] = value;
        if (key !== 'id' && !(key in this)) {
          this[key] = value;
        }
      }
    }
  }

  // --- Validation ---

  // Returns an errors object that supports both array iteration and field-specific access
  // errors.any?() / errors.some() - check if any errors
  // errors.count - number of errors
  // errors.title - returns array of errors for title field (empty if none)
  get errors() {
    const errorsData = this._errors;
    const allErrors = errorsData._all;

    return new Proxy(allErrors, {
      get(target, prop) {
        // count as method for Rails compatibility (ERB transpiles to method call)
        if (prop === 'count') {
          return () => target.length;
        }
        // Array methods delegate to _all array
        if (prop in target) {
          const value = target[prop];
          return typeof value === 'function' ? value.bind(target) : value;
        }
        // Field-specific access returns field errors or empty array
        if (typeof prop === 'string' && prop !== '_all') {
          return errorsData[prop] || [];
        }
        return undefined;
      }
    });
  }

  get isValid() {
    this._errors = { _all: [] };
    this.validate();
    if (this._errors._all.length > 0) {
      console.warn('  Validation failed:', this._errors._all);
    }
    return this._errors._all.length === 0;
  }

  // Override in subclass to add validations
  validate() {}

  // Add an error for a field
  addError(field, message) {
    const fullMessage = `${field} ${message}`;
    this._errors._all.push({ attribute: field, message, full_message: fullMessage });
    if (!this._errors[field]) this._errors[field] = [];
    this._errors[field].push({ attribute: field, message, full_message: fullMessage });
  }

  validates_presence_of(field) {
    const value = this.attributes[field];
    if (value == null || String(value).trim().length === 0) {
      this.addError(field, "can't be blank");
    }
  }

  validates_length_of(field, options) {
    const value = String(this.attributes[field] || '');
    if (options.minimum && value.length < options.minimum) {
      this.addError(field, `is too short (minimum is ${options.minimum} characters)`);
    }
    if (options.maximum && value.length > options.maximum) {
      this.addError(field, `is too long (maximum is ${options.maximum} characters)`);
    }
  }

  validates_format_of(field, options) {
    const value = String(this.attributes[field] || '');
    if (options.with && !options.with.test(value)) {
      this.addError(field, options.message || 'is invalid');
    }
  }

  validates_inclusion_of(field, options) {
    const value = this.attributes[field];
    if (options.in && !options.in.includes(value)) {
      this.addError(field, options.message || `is not included in the list`);
    }
  }

  validates_exclusion_of(field, options) {
    const value = this.attributes[field];
    if (options.in && options.in.includes(value)) {
      this.addError(field, options.message || `is reserved`);
    }
  }

  validates_numericality_of(field, options = {}) {
    const value = this.attributes[field];
    const num = Number(value);

    if (isNaN(num)) {
      this.addError(field, 'is not a number');
      return;
    }

    if (options.only_integer && !Number.isInteger(num)) {
      this.addError(field, 'must be an integer');
    }
    if (options.greater_than != null && !(num > options.greater_than)) {
      this.addError(field, `must be greater than ${options.greater_than}`);
    }
    if (options.greater_than_or_equal_to != null && !(num >= options.greater_than_or_equal_to)) {
      this.addError(field, `must be greater than or equal to ${options.greater_than_or_equal_to}`);
    }
    if (options.less_than != null && !(num < options.less_than)) {
      this.addError(field, `must be less than ${options.less_than}`);
    }
    if (options.less_than_or_equal_to != null && !(num <= options.less_than_or_equal_to)) {
      this.addError(field, `must be less than or equal to ${options.less_than_or_equal_to}`);
    }
  }

  // --- Instance Properties ---

  get persisted() {
    return this._persisted;
  }

  get newRecord() {
    return !this._persisted;
  }

  // --- Instance Methods ---

  async save() {
    if (!this.isValid) return false;

    // Set timestamps centrally - adapters don't need to handle this
    const now = new Date().toISOString();
    this.attributes.updated_at = now;
    this.updated_at = now;

    // Run before_save instance method and registered callbacks
    if (typeof this.before_save === 'function') await this.before_save();
    await this._runCallbacks('before_save');

    if (this._persisted) {
      // Run before_update callbacks
      await this._runCallbacks('before_update');

      const result = await this._update();

      if (result) {
        // Run after_update instance method and callbacks
        if (typeof this.after_update === 'function') await this.after_update();
        await this._runCallbacks('after_update');
        await this._runCallbacks('after_save');
        if (typeof this.after_save === 'function') await this.after_save();
        await this._runCallbacks('after_update_commit');
      }
      return result;
    } else {
      this.attributes.created_at ??= now;
      this.created_at ??= now;

      // Run before_create instance method and registered callbacks
      if (typeof this.before_create === 'function') await this.before_create();
      await this._runCallbacks('before_create');

      const result = await this._insert();

      if (result) {
        // Run after_create callbacks
        await this._runCallbacks('after_create');
        await this._runCallbacks('after_save');
        if (typeof this.after_save === 'function') await this.after_save();
        await this._runCallbacks('after_create_commit');
      }
      return result;
    }
  }

  // Run callbacks registered on the class, passing this instance as parameter
  async _runCallbacks(type) {
    const callbacks = this.constructor[`_${type}_callbacks`];
    if (!callbacks) return;
    for (const callback of callbacks) {
      // Pass instance as first argument (arrow functions don't bind 'this')
      await callback(this);
    }
  }

  async update(attributes) {
    Object.assign(this.attributes, attributes);
    // Also update direct properties
    for (const [key, value] of Object.entries(attributes)) {
      if (key !== 'id') {
        this[key] = value;
      }
    }
    return await this.save();
  }

  // Increment a counter column and save, returns self for chaining
  async increment(field, by = 1) {
    this.attributes[field] = (this.attributes[field] || 0) + by;
    this[field] = this.attributes[field];
    await this.save();
    return this;
  }

  // --- Class Methods ---

  static async create(attributes) {
    const record = new this(attributes);
    await record.save();
    return record;
  }

  // --- Callback registration ---
  static before_save(callback) {
    if (!this._before_save_callbacks) this._before_save_callbacks = [];
    this._before_save_callbacks.push(callback);
  }

  static before_create(callback) {
    if (!this._before_create_callbacks) this._before_create_callbacks = [];
    this._before_create_callbacks.push(callback);
  }

  static before_update(callback) {
    if (!this._before_update_callbacks) this._before_update_callbacks = [];
    this._before_update_callbacks.push(callback);
  }

  static after_create(callback) {
    if (!this._after_create_callbacks) this._after_create_callbacks = [];
    this._after_create_callbacks.push(callback);
  }

  static after_save(callback) {
    if (!this._after_save_callbacks) this._after_save_callbacks = [];
    this._after_save_callbacks.push(callback);
  }

  static after_update(callback) {
    if (!this._after_update_callbacks) this._after_update_callbacks = [];
    this._after_update_callbacks.push(callback);
  }

  static after_create_commit(callback) {
    if (!this._after_create_commit_callbacks) this._after_create_commit_callbacks = [];
    this._after_create_commit_callbacks.push(callback);
  }

  static after_update_commit(callback) {
    if (!this._after_update_commit_callbacks) this._after_update_commit_callbacks = [];
    this._after_update_commit_callbacks.push(callback);
  }

  static after_destroy_commit(callback) {
    if (!this._after_destroy_commit_callbacks) this._after_destroy_commit_callbacks = [];
    this._after_destroy_commit_callbacks.push(callback);
  }

  // --- Declarative class methods ---

  static has_secure_token(field = 'token') {
    // Generates a unique token on create; no-op at class definition time
  }

  static has_rich_text(field) {
    // ActionText: declares a rich text attribute; no-op at class definition time
  }

  static serialize(field, options = {}) {
    if (!this._serialized) this._serialized = {};
    this._serialized[field] = options;
  }

  static store(field, options = {}) {
    // ActiveRecord::Store: key-value store in a single column; no-op at class definition time
  }

  static normalizes(field, options = {}) {
    if (!this._normalizations) this._normalizations = {};
    this._normalizations[field] = options;
  }

  static attribute(name, type, options = {}) {
    // Rails attribute DSL: declares typed virtual attributes
    if (!this._attributes) this._attributes = {};
    this._attributes[name] = { type, ...options };
  }

  static validate(method) {
    if (!this._custom_validations) this._custom_validations = [];
    this._custom_validations.push(method);
  }

  // --- Association helpers ---

  async hasMany(modelClass, foreignKey) {
    return await modelClass.where({ [foreignKey]: this.id });
  }

  // --- Turbo Stream helpers ---

  // Generate HTML for Turbo Stream broadcasts
  // Override in model for custom rendering
  toHTML() {
    const domId = `${this.constructor.tableName.replace(/_/g, '-').slice(0, -1)}_${this.id}`;
    const attrs = Object.entries(this.attributes)
      .filter(([k]) => !['id', 'created_at', 'updated_at'].includes(k))
      .map(([k, v]) => `<span class="${k}">${v ?? ''}</span>`)
      .join(' ');
    return `<div id="${domId}">${attrs}</div>`;
  }

  // Generate dom_id compatible ID
  domId() {
    const modelName = this.constructor.tableName.replace(/_/g, '-').slice(0, -1);
    return `${modelName}_${this.id}`;
  }

  // --- Broadcasting methods ---

  // Broadcast JSON event for React components
  // Usage: this.broadcast_json_to("workflow_1", "node_created")
  broadcast_json_to(channel, event, data = null) {
    const Broadcaster = globalThis.TurboBroadcast;
    if (!Broadcaster?.broadcast) return;

    const payload = JSON.stringify({
      type: event,
      model: this.constructor.name,
      id: this.id,
      data: data || { ...this.attributes, id: this.id }
    });
    Broadcaster.broadcast(channel, payload);
  }

  // Broadcast Turbo Stream append for ERB views
  async broadcast_append_to(channel, options = {}) {
    const Broadcaster = globalThis.TurboBroadcast;
    if (!Broadcaster?.broadcast) return;

    const target = options.target || this.constructor.tableName;
    let html = options.html;
    if (!html && this.constructor.renderPartial) {
      const modelName = this.constructor.name.toLowerCase();
      html = await this.constructor.renderPartial({
        $context: { authenticityToken: '', flash: {}, contentFor: {} },
        [modelName]: this
      });
    }
    if (!html) html = this.toHTML();
    const stream = `<turbo-stream action="append" target="${target}"><template>${html}</template></turbo-stream>`;
    Broadcaster.broadcast(channel, stream);
  }

  // Broadcast Turbo Stream prepend for ERB views
  async broadcast_prepend_to(channel, options = {}) {
    const Broadcaster = globalThis.TurboBroadcast;
    if (!Broadcaster?.broadcast) return;

    const target = options.target || this.constructor.tableName;
    let html = options.html;
    if (!html && this.constructor.renderPartial) {
      const modelName = this.constructor.name.toLowerCase();
      html = await this.constructor.renderPartial({
        $context: { authenticityToken: '', flash: {}, contentFor: {} },
        [modelName]: this
      });
    }
    if (!html) html = this.toHTML();
    const stream = `<turbo-stream action="prepend" target="${target}"><template>${html}</template></turbo-stream>`;
    Broadcaster.broadcast(channel, stream);
  }

  // Broadcast Turbo Stream replace for ERB views
  async broadcast_replace_to(channel, options = {}) {
    const Broadcaster = globalThis.TurboBroadcast;
    if (!Broadcaster?.broadcast) return;

    const target = options.target || this.domId();
    // Use renderPartial if available (from broadcasts_to), otherwise fall back to toHTML
    let html = options.html;
    if (!html && this.constructor.renderPartial) {
      // Build locals object with model name as key (e.g., { article: this })
      // Use class name lowercased to match transpiler output
      const modelName = this.constructor.name.toLowerCase();
      html = await this.constructor.renderPartial({
        $context: { authenticityToken: '', flash: {}, contentFor: {} },
        [modelName]: this
      });
    }
    if (!html) html = this.toHTML();
    const stream = `<turbo-stream action="replace" target="${target}"><template>${html}</template></turbo-stream>`;
    Broadcaster.broadcast(channel, stream);
  }

  // Broadcast Turbo Stream remove for ERB views
  broadcast_remove_to(channel, options = {}) {
    const Broadcaster = globalThis.TurboBroadcast;
    if (!Broadcaster?.broadcast) return;

    const target = options.target || this.domId();
    const stream = `<turbo-stream action="remove" target="${target}"></turbo-stream>`;
    Broadcaster.broadcast(channel, stream);
  }

  async belongsTo(modelClass, foreignKey) {
    const fkValue = this.attributes[foreignKey];
    if (!fkValue) return null;
    return await modelClass.find(fkValue);
  }

  // --- Abstract methods (must be implemented by adapters) ---

  // static get table() { throw new Error('Subclass must implement static get table()'); }
  // static async all() { throw new Error('Subclass must implement static all()'); }
  // static async find(id) { throw new Error('Subclass must implement static find()'); }
  // static async findBy(conditions) { throw new Error('Subclass must implement static findBy()'); }
  // static async where(conditions) { throw new Error('Subclass must implement static where()'); }
  // static async first() { throw new Error('Subclass must implement static first()'); }
  // static async last() { throw new Error('Subclass must implement static last()'); }
  // static async count() { throw new Error('Subclass must implement static count()'); }
  // async _insert() { throw new Error('Subclass must implement _insert()'); }
  // async _update() { throw new Error('Subclass must implement _update()'); }
  // async destroy() { throw new Error('Subclass must implement destroy()'); }
  // async reload() { throw new Error('Subclass must implement reload()'); }
}

// Helper to define attribute accessors on a class
export function attr_accessor(klass, ...attrs) {
  for (const attr of attrs) {
    const getter = function() { return this.attributes[attr]; };
    getter._isAttrAccessor = true;
    Object.defineProperty(klass.prototype, attr, {
      get: getter,
      set(value) {
        this.attributes[attr] = value;
        this._changes[attr] = value;
      },
      enumerable: true,
      configurable: true
    });
  }
}

// Time polyfill for Ruby compatibility
export function initTimePolyfill(globalObj = globalThis) {
  globalObj.Time = {
    now() {
      return { toString() { return new Date().toISOString(); } };
    }
  };
}
