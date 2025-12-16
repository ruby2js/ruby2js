// Base class for all models
// Transpiled to JavaScript, runs on sql.js
export class ApplicationRecord {
  #_attributes = {};
  #_errors = [];
  #_persisted = false;
  #_id;

  // Use underscore-prefixed properties instead of private fields
  // so subclasses can access them (JS private fields don't inherit)
  get id() {
    return this.#_id
  };

  set id(value) {
    this.#_id = value;
    return this.#_id
  };

  // Expose internal properties for subclass access (JS private fields don't inherit)
  get _id() {
    return this.#_id
  };

  get _attributes() {
    return this.#_attributes
  };

  get attributes() {
    return this.#_attributes
  };

  get errors() {
    return this.#_errors
  };

  constructor(attrs={}) {
    for (let key of Object.keys(attrs)) {
      let value = attrs[key];
      this.#_attributes[key.toString()] = value;

      // Also set as direct property for easy access (article.title instead of article._attributes['title'])
      this[key] = value;
      if (key.toString() == "id") this.#_id = value
    };

    if (this.#_id) this.#_persisted = true
  };

  // Class methods
  static get all() {
    let sql = `SELECT * FROM ${this.table_name}`;
    console.debug(`  ${this.name} Load  ${sql}`);
    let results = DB.exec(sql);
    if (results.length <= 0) return [];
    return this.result_to_models(results[0])
  };

  static find(id) {
    let obj;
    let sql = `SELECT * FROM ${this.table_name} WHERE id = ?`;
    console.debug(`  ${this.name} Load  ${sql}  [["id", ${id}]]`);
    let stmt = DB.prepare(sql);
    stmt.bind([id]);

    if (stmt.step()) {
      obj = stmt.getAsObject();
      stmt.free();
      return new this(obj)
    } else {
      stmt.free();
      console.error(`  ${this.name} not found with id=${id}`);
      return (() => { throw `${this.name} not found with id=${id}` })()
    }
  };

  static find_by(conditions) {
    let obj;
    let [where_clause, values] = this.build_where(conditions);
    let sql = `SELECT * FROM ${this.table_name} WHERE ${where_clause} LIMIT 1`;
    console.debug(`  ${this.name} Load  ${sql}  ${JSON.stringify(values)}`);
    let stmt = DB.prepare(sql);
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
    let sql = `SELECT * FROM ${this.table_name} WHERE ${where_clause}`;
    console.debug(`  ${this.name} Load  ${sql}  ${JSON.stringify(values)}`);
    let stmt = DB.prepare(sql);
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
    return this.#_persisted
  };

  new_record() {
    return !this.#_persisted
  };

  get save() {
    if (!this.is_valid) return false;
    return this.#_persisted ? this.#do_update : this.#do_insert
  };

  // Access as getter
  update(attrs) {
    // Access as getter
    for (let key of Object.keys(attrs)) {
      this.#_attributes[key.toString()] = attrs[key]
    };

    return this.save
  };

  // Access as getter
  get destroy() {
    if (!this.#_persisted) return false;
    let sql = `DELETE FROM ${this.constructor.table_name} WHERE id = ?`;
    console.debug(`  ${this.constructor.name} Destroy  ${sql}  [["id", ${this.#_id}]]`);
    DB.run(sql, [this.#_id]);
    this.#_persisted = false;
    return true
  };

  get is_valid() {
    this.#_errors = [];
    this.validate();

    // Call as method - subclasses define validate()
    if (this.#_errors.length > 0) {
      console.warn("  Validation failed:", this.#_errors)
    };

    return this.#_errors.length == 0
  };

  get validate() {
    return null
  };

  // Override in subclasses
  // Validation helpers
  validates_presence_of(field) {
    let value = this.#_attributes[field.toString()];

    if (value == null || value.toString().trim().length == 0) {
      return this.#_errors.push(`${field} can't be blank`)
    }
  };

  validates_length_of(field, options) {
    let value = this.#_attributes[field.toString()].toString();

    if (options.minimum && value.length < options.minimum) {
      return this.#_errors.push(`${field} is too short (minimum is ${options.minimum} characters)`)
    }
  };

  get #do_insert() {
    let now = Time.now().toString();
    this.#_attributes.created_at = now;
    this.#_attributes.updated_at = now;
    let cols = [];
    let placeholders = [];
    let values = [];
    let bindings = [];

    for (let key of Object.keys(this.#_attributes)) {
      if (key == "id") continue;
      cols.push(key);
      placeholders.push("?");
      values.push(this.#_attributes[key]);
      bindings.push([key, this.#_attributes[key]])
    };

    let sql = `INSERT INTO ${this.constructor.table_name} (${cols.join(", ")}) VALUES (${placeholders.join(", ")})`;
    console.debug(`  ${this.constructor.name} Create  ${sql}  ${JSON.stringify(bindings)}`);
    DB.run(sql, values);
    let id_result = DB.exec("SELECT last_insert_rowid()");
    this.#_id = id_result[0].values[0][0];
    this.#_attributes.id = this.#_id;
    this.id = this.#_id;

    // Also set as direct property
    this.#_persisted = true;
    console.log(`  ${this.constructor.name} Create (id: ${this.#_id})`);
    return true
  };

  get #do_update() {
    this.#_attributes.updated_at = Time.now().toString();
    let sets = [];
    let values = [];
    let bindings = [];

    for (let key of Object.keys(this.#_attributes)) {
      if (key == "id") continue;
      sets.push(`${key} = ?`);
      values.push(this.#_attributes[key]);
      bindings.push([key, this.#_attributes[key]])
    };

    values.push(this.#_id);
    bindings.push(["id", this.#_id]);
    let sql = `UPDATE ${this.constructor.table_name} SET ${sets.join(", ")} WHERE id = ?`;
    console.debug(`  ${this.constructor.name} Update  ${sql}  ${JSON.stringify(bindings)}`);
    DB.run(sql, values);
    console.log(`  ${this.constructor.name} Update (id: ${this.#_id})`);
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