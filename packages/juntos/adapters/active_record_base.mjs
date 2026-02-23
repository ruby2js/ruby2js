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

// Quote a SQL identifier to handle reserved words (order, group, key, type, etc.)
export function quoteId(name) {
  return `"${name}"`;
}

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

    // Apply enum defaults for new records (Rails defaults to first enum value)
    const enumDefaults = this.constructor._enumDefaults;
    if (enumDefaults && !this._persisted) {
      for (const [field, defaultVal] of Object.entries(enumDefaults)) {
        if (!(field in attributes)) {
          this.attributes[field] = defaultVal;
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

  valid() {
    return this.isValid;
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

  validates_associated_of(field) {
    const record = this[`_${field}`] || this.attributes[field];
    if (record && typeof record.valid === 'function' && !record.valid()) {
      this.addError(field, 'is invalid');
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
        await this._processNestedAttributes();
        // Run after_update instance method and callbacks
        if (typeof this.after_update === 'function') await this.after_update();
        await this._runCallbacks('after_update');
        await this._runCallbacks('after_save');
        if (typeof this.after_save === 'function') await this.after_save();
        await this._runCallbacks('after_update_commit');
        await this._runCallbacks('after_save_commit');
        this._changes = {};  // Clear dirty tracking after successful save
      }
      return result;
    } else {
      this.attributes.created_at ??= now;
      this.created_at ??= now;

      // Resolve belongs_to defaults (e.g., default: -> { board.account })
      if (typeof this._resolveDefaults === 'function') {
        await this._resolveDefaults();
      }

      // Run before_create instance method and registered callbacks
      if (typeof this.before_create === 'function') await this.before_create();
      await this._runCallbacks('before_create');

      const result = await this._insert();

      if (result) {
        await this._processNestedAttributes();
        // Run after_create callbacks
        await this._runCallbacks('after_create');
        await this._runCallbacks('after_save');
        if (typeof this.after_save === 'function') await this.after_save();
        await this._runCallbacks('after_create_commit');
        await this._runCallbacks('after_save_commit');
        this._changes = {};  // Clear dirty tracking after successful save
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
    for (const [key, value] of Object.entries(attributes)) {
      if (key === 'id') continue;
      const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(this), key);
      if (descriptor?.set) {
        // Association setter — let it handle FK storage, don't copy raw key to attributes
        this[key] = value;
      } else {
        this.attributes[key] = value;
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

  // Increment a counter column via direct SQL (skip callbacks/validations)
  async increment_bang(field, by = 1) {
    this.attributes[field] = (this.attributes[field] || 0) + by;
    this[field] = this.attributes[field];
    await this.updateColumn(field, this.attributes[field]);
    return this;
  }

  // Direct SQL update of a single column, skipping callbacks and validations
  async updateColumn(col, val) {
    return this.updateColumns({ [col]: val });
  }

  // Direct SQL update of multiple columns, skipping callbacks and validations
  async updateColumns(attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      this.attributes[k] = v;
      if (k !== 'id') this[k] = v;
    }
    // Direct SQL update via the class's static _update helper
    const sets = [];
    const values = [];
    let i = 1;
    for (const [k, v] of Object.entries(attrs)) {
      sets.push(`${quoteId(k)} = ${this.constructor._param(i++)}`);
      values.push(this.constructor._formatValue(v));
    }
    values.push(this.id);
    const sql = `UPDATE ${this.constructor.tableName} SET ${sets.join(', ')} WHERE ${quoteId('id')} = ${this.constructor._param(i)}`;
    await this.constructor._execute(sql, values);
    return true;
  }

  // Touch updated_at (and optional extra timestamp columns) via direct SQL
  async touch(...names) {
    const now = new Date().toISOString();
    const attrs = { updated_at: now };
    for (const name of names) attrs[name] = now;
    return this.updateColumns(attrs);
  }

  // Execute block with a pessimistic lock. For SQLite (single-writer), just reload and execute.
  async withLock(callback) {
    await this.reload();
    return callback ? await callback() : undefined;
  }

  // Transaction wrapper — delegates to class-level transaction if available,
  // otherwise a simple pass-through for in-memory adapters.
  async transaction(callback) {
    if (typeof this.constructor.transaction === 'function') {
      return this.constructor.transaction(() => callback.call(this));
    }
    return await callback.call(this);
  }

  // Track an event on this record (from Eventable concern).
  // Creates an Event record linked to this eventable and its board.
  async track_event(action, { creator, board, ...particulars } = {}) {
    // Check should_track_event (concern template method pattern).
    // This is typically a getter from the mixed-in concern that returns a boolean.
    // Only skip if the method exists and returns falsy.
    if ('should_track_event' in this && !this.should_track_event) return;
    if (!creator) creator = globalThis.Current?.user;
    if (!board && this.board) board = this.board;
    const prefix = this.constructor.name.replace(/([A-Z])/g, (m, c, i) => (i > 0 ? '_' : '') + c.toLowerCase());
    const eventAction = `${prefix}_${action}`;
    if (board?.events) {
      const event = await board.events.create({ action: eventAction, creator, board, eventable: this, particulars });
      // Wrap action as StringInquirer so event.action.card_closed works like Rails
      if (event && typeof event.action === 'string') {
        const actionStr = event.action;
        event.action = new Proxy(new String(actionStr), {
          get(target, prop) {
            if (prop === Symbol.toPrimitive || prop === 'valueOf') return () => actionStr;
            if (prop === 'toString') return () => actionStr;
            if (typeof prop === 'string' && prop !== 'length' && prop !== 'constructor') {
              return target.valueOf() === prop ? true : target[prop];
            }
            return Reflect.get(target, prop);
          }
        });
      }
      // Also push into this record's events proxy (card.events cache).
      // Use the getter (this.events) to ensure the proxy is created.
      try {
        const myEvents = this.events;
        if (myEvents && typeof myEvents === 'object' && '_records' in myEvents) {
          if (!myEvents._records) myEvents._records = [];
          myEvents._records.push(event);
        }
      } catch(e) { /* no events association on this model */ }
      return event;
    }
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

  static before_destroy(callback) {
    if (!this._before_destroy_callbacks) this._before_destroy_callbacks = [];
    this._before_destroy_callbacks.push(callback);
  }

  static after_destroy(callback) {
    if (!this._after_destroy_callbacks) this._after_destroy_callbacks = [];
    this._after_destroy_callbacks.push(callback);
  }

  static after_destroy_commit(callback) {
    if (!this._after_destroy_commit_callbacks) this._after_destroy_commit_callbacks = [];
    this._after_destroy_commit_callbacks.push(callback);
  }

  static after_save_commit(callback) {
    if (!this._after_save_commit_callbacks) this._after_save_commit_callbacks = [];
    this._after_save_commit_callbacks.push(callback);
  }

  static before_validation(callback) {
    if (!this._before_validation_callbacks) this._before_validation_callbacks = [];
    this._before_validation_callbacks.push(callback);
  }

  static after_validation(callback) {
    if (!this._after_validation_callbacks) this._after_validation_callbacks = [];
    this._after_validation_callbacks.push(callback);
  }

  static after_touch(callback) {
    if (!this._after_touch_callbacks) this._after_touch_callbacks = [];
    this._after_touch_callbacks.push(callback);
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

  static accepts_nested_attributes_for(association, options = {}) {
    if (!this._nested_attributes) this._nested_attributes = {};
    this._nested_attributes[association] = options;
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

  async _processNestedAttributes() {
    const config = this.constructor._nested_attributes;
    if (!config || !this._pending_nested_attributes) return;

    for (const [assocName, options] of Object.entries(config)) {
      const data = this._pending_nested_attributes[assocName];
      if (!data) continue;

      // Use the has_many association proxy (CollectionProxy) to access the model class
      const proxy = this[assocName];
      if (!proxy || !proxy._model) continue;
      const modelClass = proxy._model;
      const fk = proxy._association?.foreignKey || `${this.constructor.name.toLowerCase()}_id`;

      // Normalize to array of attribute hashes
      const entries = Array.isArray(data)
        ? data
        : Object.values(data);

      for (const attrs of entries) {
        // Apply reject_if filter
        if (options.reject_if && options.reject_if(attrs)) continue;

        // Handle _destroy
        if (attrs._destroy && options.allow_destroy) {
          if (attrs.id) {
            const record = await modelClass.find(attrs.id);
            if (record) await record.destroy();
          }
          continue;
        }

        if (attrs.id) {
          // Update existing record
          const record = await modelClass.find(attrs.id);
          if (record) {
            const updateAttrs = { ...attrs };
            delete updateAttrs.id;
            await record.update(updateAttrs);
          }
        } else {
          // Create new record with parent FK
          await modelClass.create({ ...attrs, [fk]: this.id });
        }
      }
    }

    this._pending_nested_attributes = {};
  }

  attribute_present(name) {
    const value = this.attributes[name];
    return value != null && value !== '' && value !== false;
  }

  // Snake case aliases
  update_column(col, val) { return this.updateColumn(col, val); }
  update_columns(attrs) { return this.updateColumns(attrs); }
  with_lock(callback) { return this.withLock(callback); }

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

    // Rails dirty tracking: <attr>_changed? → <attr>_changed()
    Object.defineProperty(klass.prototype, `${attr}_changed`, {
      value() { return attr in this._changes; },
      writable: true,
      configurable: true
    });
  }
}

// Time polyfill for Ruby compatibility
export function initTimePolyfill(globalObj = globalThis) {
  // Don't overwrite enhanced Time (e.g. from test globals with freeze/travel support)
  if (globalObj.Time) return;
  globalObj.Time = {
    get current() { return new Date().toISOString(); },
    now() {
      return { toString() { return new Date().toISOString(); } };
    }
  };
}
