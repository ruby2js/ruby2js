// Base class for all models
// Transpiled to JavaScript, runs on sql.js
export class ApplicationRecord {
  #attributes = {};
  #errors = [];
  #persisted = false;
  #id;

  get id() {
    return this.#id
  };

  set id(id) {
    this.#id = id
  };

  get attributes() {
    return this.#attributes
  };

  set attributes(attributes) {
    this.#attributes = attributes
  };

  get errors() {
    return this.#errors
  };

  set errors(errors) {
    this.#errors = errors
  };

  constructor(attrs={}) {
    for (let key of Object.keys(attrs)) {
      let value = attrs[key];
      this.#attributes[key.toString()] = value;
      if (key.toString() == "id") this.#id = value
    };

    if (this.#id) this.#persisted = true
  };

  // Class methods
  static get all() {
    let sql = `SELECT * FROM ${this.table_name}`;
    let results = DB.exec(sql);
    if (results.length <= 0) return [];
    return this.result_to_models(results[0])
  };

  static find(id) {
    let obj;
    let stmt = DB.prepare(`SELECT * FROM ${this.table_name} WHERE id = ?`);
    stmt.bind([id]);

    if (stmt.step()) {
      obj = stmt.getAsObject();
      stmt.free();
      return new this(obj)
    } else {
      stmt.free();
      return (() => { throw `${this.name} not found with id=${id}` })()
    }
  };

  static find_by(conditions) {
    let obj;
    let [where_clause, values] = this.build_where(conditions);
    let stmt = DB.prepare(`SELECT * FROM ${this.table_name} WHERE ${where_clause} LIMIT 1`);
    stmt.bind(values);

    if (stmt.step()) {
      obj = stmt.getAsObject();
      stmt.free();
      return new this(obj)
    } else {
      stmt.free();
      return null
    }
  };

  static where(conditions) {
    let [where_clause, values] = this.build_where(conditions);
    let stmt = DB.prepare(`SELECT * FROM ${this.table_name} WHERE ${where_clause}`);
    stmt.bind(values);
    let results = [];

    while (stmt.step()) {
      results.push(new this(stmt.getAsObject()))
    };

    stmt.free();
    return results
  };

  static create(attrs) {
    let record = new this(attrs);
    record.save;

    // Access as getter, not method call
    return record
  };

  static get count() {
    let result = DB.exec(`SELECT COUNT(*) FROM ${this.table_name}`);
    return result[0].values[0][0]
  };

  static get first() {
    let result = DB.exec(`SELECT * FROM ${this.table_name} ORDER BY id ASC LIMIT 1`);
    if (result.length <= 0 || result[0].values.length <= 0) return null;
    return this.result_to_models(result[0])[0]
  };

  static get last() {
    let result = DB.exec(`SELECT * FROM ${this.table_name} ORDER BY id DESC LIMIT 1`);
    if (result.length <= 0 || result[0].values.length <= 0) return null;
    return this.result_to_models(result[0])[0]
  };

  // Instance methods
  persisted() {
    return this.#persisted
  };

  new_record() {
    return !this.#persisted
  };

  get save() {
    if (!this.is_valid()) return false;
    return this.#persisted ? this.#do_update : this.#do_insert
  };

  // Access as getter
  update(attrs) {
    // Access as getter
    for (let key of Object.keys(attrs)) {
      this.#attributes[key.toString()] = attrs[key]
    };

    return this.save
  };

  // Access as getter
  get destroy() {
    if (!this.#persisted) return false;

    DB.run(
      `DELETE FROM ${this.constructor.table_name} WHERE id = ?`,
      [this.#id]
    );

    this.#persisted = false;
    return true
  };

  get is_valid() {
    this.#errors = [];
    this.validate;

    // Access as getter
    return this.#errors.length == 0
  };

  get validate() {
    return null
  };

  // Override in subclasses
  // Validation helpers
  validates_presence_of(field) {
    let value = this.#attributes[field.toString()];

    if (value == null || value.toString().trim().length == 0) {
      return this.#errors.push(`${field} can't be blank`)
    }
  };

  validates_length_of(field, options) {
    let value = this.#attributes[field.toString()].toString();

    if (options.minimum && value.length < options.minimum) {
      return this.#errors.push(`${field} is too short (minimum is ${options.minimum} characters)`)
    }
  };

  get #do_insert() {
    let now = Time.now().toString();
    this.#attributes.created_at = now;
    this.#attributes.updated_at = now;
    let cols = [];
    let placeholders = [];
    let values = [];

    for (let key of Object.keys(this.#attributes)) {
      if (key == "id") continue;
      cols.push(key);
      placeholders.push("?");
      values.push(this.#attributes[key])
    };

    let sql = `INSERT INTO ${this.constructor.table_name} (${cols.join(", ")}) VALUES (${placeholders.join(", ")})`;
    DB.run(sql, values);
    let id_result = DB.exec("SELECT last_insert_rowid()");
    this.#id = id_result[0].values[0][0];
    this.#attributes.id = this.#id;
    this.#persisted = true;
    return true
  };

  get #do_update() {
    this.#attributes.updated_at = Time.now().toString();
    let sets = [];
    let values = [];

    for (let key of Object.keys(this.#attributes)) {
      if (key == "id") continue;
      sets.push(`${key} = ?`);
      values.push(this.#attributes[key])
    };

    values.push(this.#id);
    let sql = `UPDATE ${this.constructor.table_name} SET ${sets.join(", ")} WHERE id = ?`;
    DB.run(sql, values);
    return true
  };

  static build_where(conditions) {
    let clauses = [];
    let values = [];

    for (let key of Object.keys(conditions)) {
      clauses.push(`${key} = ?`);
      values.push(conditions[key])
    };

    return [clauses.join(" AND "), values]
  };

  static result_to_models(result) {
    let columns = result.columns;

    return result.values.map((row) => {
      let obj = {};
      columns.forEach((col, i) => obj[col] = row[i]);
      return new this(obj)
    })
  }
}