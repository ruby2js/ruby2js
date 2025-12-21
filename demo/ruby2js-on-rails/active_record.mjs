// Minimal ActiveRecord wrapper for sql.js
// Provides Ruby-like API: Article.find(1), Article.where(...), article.save, etc.

let db = null;

// Set the database connection
export function setDatabase(database) {
  db = database;
}

// Base class for ActiveRecord models
export class ActiveRecord {
  static tableName = null;  // Override in subclass
  static columns = [];      // Override in subclass

  constructor(attributes = {}) {
    this.id = attributes.id || null;
    this.attributes = { ...attributes };
    this._persisted = !!attributes.id;
    this._changes = {};
  }

  // --- Class Methods (finders) ---

  static all() {
    const sql = `SELECT * FROM ${this.tableName}`;
    const result = db.exec(sql);
    if (!result.length) return [];
    return this._resultToModels(result[0]);
  }

  static find(id) {
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE id = ?`);
    stmt.bind([id]);
    if (stmt.step()) {
      const obj = stmt.getAsObject();
      stmt.free();
      return new this(obj);
    }
    stmt.free();
    throw new Error(`${this.name} not found with id=${id}`);
  }

  static findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`);
    stmt.bind(values);
    if (stmt.step()) {
      const obj = stmt.getAsObject();
      stmt.free();
      return new this(obj);
    }
    stmt.free();
    return null;
  }

  static where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const sql = `SELECT * FROM ${this.tableName} WHERE ${where}`;
    const stmt = db.prepare(sql);
    stmt.bind(values);

    const results = [];
    while (stmt.step()) {
      results.push(new this(stmt.getAsObject()));
    }
    stmt.free();
    return results;
  }

  static create(attributes) {
    const record = new this(attributes);
    record.save();
    return record;
  }

  static count() {
    const result = db.exec(`SELECT COUNT(*) FROM ${this.tableName}`);
    return result[0].values[0][0];
  }

  static first() {
    const result = db.exec(`SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`);
    if (!result.length || !result[0].values.length) return null;
    return this._resultToModels(result[0])[0];
  }

  static last() {
    const result = db.exec(`SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`);
    if (!result.length || !result[0].values.length) return null;
    return this._resultToModels(result[0])[0];
  }

  // --- Instance Methods ---

  get persisted() {
    return this._persisted;
  }

  get newRecord() {
    return !this._persisted;
  }

  save() {
    if (this._persisted) {
      return this._update();
    } else {
      return this._insert();
    }
  }

  update(attributes) {
    Object.assign(this.attributes, attributes);
    return this.save();
  }

  destroy() {
    if (!this._persisted) return false;
    db.run(`DELETE FROM ${this.constructor.tableName} WHERE id = ?`, [this.id]);
    this._persisted = false;
    return true;
  }

  reload() {
    if (!this.id) return this;
    const fresh = this.constructor.find(this.id);
    this.attributes = fresh.attributes;
    return this;
  }

  // --- Association helpers ---

  hasMany(modelClass, foreignKey) {
    return modelClass.where({ [foreignKey]: this.id });
  }

  belongsTo(modelClass, foreignKey) {
    const fkValue = this.attributes[foreignKey];
    if (!fkValue) return null;
    return modelClass.find(fkValue);
  }

  // --- Private helpers ---

  _insert() {
    const cols = [];
    const placeholders = [];
    const values = [];

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      cols.push(key);
      placeholders.push('?');
      values.push(value);
    }

    const sql = `INSERT INTO ${this.constructor.tableName} (${cols.join(', ')}) VALUES (${placeholders.join(', ')})`;
    db.run(sql, values);

    const idResult = db.exec('SELECT last_insert_rowid()');
    this.id = idResult[0].values[0][0];
    this.attributes.id = this.id;
    this._persisted = true;
    return true;
  }

  _update() {
    const sets = [];
    const values = [];

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      sets.push(`${key} = ?`);
      values.push(value);
    }
    values.push(this.id);

    const sql = `UPDATE ${this.constructor.tableName} SET ${sets.join(', ')} WHERE id = ?`;
    db.run(sql, values);
    return true;
  }

  static _buildWhere(conditions) {
    const clauses = [];
    const values = [];
    for (const [key, value] of Object.entries(conditions)) {
      clauses.push(`${key} = ?`);
      values.push(value);
    }
    return { where: clauses.join(' AND '), values };
  }

  static _resultToModels(result) {
    const { columns, values } = result;
    return values.map(row => {
      const obj = {};
      columns.forEach((col, i) => obj[col] = row[i]);
      return new this(obj);
    });
  }
}

// Helper to define attribute accessors
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
