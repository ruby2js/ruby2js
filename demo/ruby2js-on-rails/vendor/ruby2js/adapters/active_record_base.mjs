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

  constructor(attributes = {}) {
    this.id = attributes.id || null;
    this.attributes = { ...attributes };
    this._persisted = !!attributes.id;
    this._changes = {};
    this._errors = { _all: [] };

    // Set attribute accessors for direct property access (article.title)
    for (const [key, value] of Object.entries(attributes)) {
      if (key !== 'id' && !(key in this)) {
        this[key] = value;
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
        // count property for Rails compatibility
        if (prop === 'count') {
          return target.length;
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

    if (this._persisted) {
      return await this._update();
    } else {
      return await this._insert();
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

  // --- Class Methods ---

  static async create(attributes) {
    const record = new this(attributes);
    await record.save();
    return record;
  }

  // --- Association helpers ---

  async hasMany(modelClass, foreignKey) {
    return await modelClass.where({ [foreignKey]: this.id });
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
    Object.defineProperty(klass.prototype, attr, {
      get() { return this.attributes[attr]; },
      set(value) {
        this.attributes[attr] = value;
        this._changes[attr] = value;
      },
      enumerable: true
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
