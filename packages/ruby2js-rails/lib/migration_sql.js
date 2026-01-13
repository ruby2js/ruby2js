import { Ruby2JS } from "ruby2js/ruby2js.js";

export class MigrationSQL {
  // Generate SQL for all migrations in a directory
  // Returns a hash with :sql (combined SQL) and :migrations (array of parsed migrations)
  static generate_all(migrate_dir) {
    if (!File.exist(migrate_dir)) return {sql: "", migrations: []};
    let migrations = [];
    let sql_parts = [];
    sql_parts.push("-- Ruby2JS Generated Migrations");
    sql_parts.push(`-- Generated at: ${Time.now.utc}`);
    sql_parts.push("");
    sql_parts.push("-- Schema migrations tracking table");
    sql_parts.push("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY);");
    sql_parts.push("");

    for (let path of Dir.glob(File.join(migrate_dir, "*.rb")).sort()) {
      let basename = File.basename(path, ".rb");
      let version = basename.split("_")[0];
      let migration = this.parse_migration(path);
      if (!migration) continue;
      let sql = this.generate_sql(migration.statements, version);
      if (sql && sql.length != 0) sql_parts.push(sql);
      migrations.push({version, filename: basename})
    };

    return {sql: sql_parts.join("\n"), migrations}
  };

  // Parse a single migration file and extract statements
  static parse_migration(path) {
    let source = File.read(path);
    let [ast, _] = Ruby2JS.parse(source);
    if (!ast) return null;
    let statements = [];
    this.extract_statements(ast, statements);
    return {path, statements}
  };

  // Generate SQL from migration statements
  static generate_sql(statements, version) {
    if (statements.length == 0) return "";
    let sql_lines = [];
    sql_lines.push(`-- Migration: ${version}`);

    for (let stmt of statements) {
      switch (stmt.type) {
      case "create_table":
        sql_lines.push(this.create_table_sql(stmt));
        break;

      case "add_index":
        sql_lines.push(this.add_index_sql(stmt));
        break;

      case "add_column":
        sql_lines.push(this.add_column_sql(stmt));
        break;

      case "remove_column":
        sql_lines.push(this.remove_column_sql(stmt));
        break;

      case "drop_table":
        sql_lines.push(this.drop_table_sql(stmt))
      }
    };

    // Add version tracking
    sql_lines.push(`INSERT INTO schema_migrations (version) VALUES ('${version}') ON CONFLICT DO NOTHING;`);
    sql_lines.push("");
    return sql_lines.join("\n")
  };

  static extract_statements(node, statements) {
    let name, parent, body;
    if (!node) return;

    switch (node.type) {
    case "class":

      // Check if this is a migration class
      let [name, parent, body] = node.children;

      if (this.migration_class(parent)) {
        return this.extract_from_body(body, statements)
      };

      break;

    case "begin":

      for (let child of node.children) {
        this.extract_statements(child, statements)
      }
    }
  };

  static migration_class(node) {
    if (!node) return false;

    if (node.type == "send" && node.children[1] == "[]") {
      let $const = node.children[0];
      return this.migration_const($const)
    } else if (node.type == "const") {
      return this.migration_const(node)
    };

    return false
  };

  static migration_const(node) {
    if (node?.type != "const") return false;
    let children = node.children;
    if (children.length != 2) return false;
    let parent = children[0];
    let name = children[1];
    return parent?.type == "const" && parent.children[0] == null && parent.children[1] == "ActiveRecord" && name == "Migration"
  };

  static extract_from_body(body, statements) {
    if (!body) return;
    let children = body.type == "begin" ? body.children : [body];

    for (let child of children) {
      if (!child) continue;

      if (child.type == "def") {
        let method_name = child.children[0];

        if (method_name == "change" || method_name == "up") {
          this.extract_from_method(child.children[2], statements)
        }
      }
    }
  };

  static extract_from_method(body, statements) {
    if (!body) return;
    let children = body.type == "begin" ? body.children : [body];

    for (let child of children) {
      if (!child) continue;

      switch (child.type) {
      case "block":
        this.extract_block(child, statements);
        break;

      case "send":
        this.extract_send(child, statements)
      }
    }
  };

  static extract_block(node, statements) {
    let [call, block_args, body] = node.children;
    if (call.type != "send") return;
    let [target, method, ...args] = call.children;
    if (target != null) return;

    switch (method) {
    case "create_table":
      return this.extract_create_table(args, block_args, body, statements)
    }
  };

  static extract_send(node, statements) {
    let [target, method, ...args] = node.children;
    if (target != null) return;

    switch (method) {
    case "add_index":
      return this.extract_add_index(args, statements);

    case "add_column":
      return this.extract_add_column(args, statements);

    case "remove_column":
      return this.extract_remove_column(args, statements);

    case "drop_table":
      return this.extract_drop_table(args, statements)
    }
  };

  static extract_create_table(args, block_args, body, statements) {
    if (args.length == 0) return;
    let table_name = this.extract_string_value(args[0]);
    if (!table_name) return;
    let options = this.extract_table_options(args);
    let columns = [];
    let foreign_keys = [];

    // Add primary key unless id: false
    if (options.id != false) {
      columns.push({
        name: "id",
        type: "integer",
        primaryKey: true,
        autoIncrement: true
      })
    };

    // Process column definitions
    if (body) {
      let column_children = body.type == "begin" ? body.children : [body];

      for (let child of column_children) {
        if (child?.type != "send") continue;
        let result = this.extract_column(child, table_name);

        if (result) {
          if (result.column) columns.push(result.column);
          if (result.columns) columns.push(...result.columns);
          if (result.foreign_key) foreign_keys.push(result.foreign_key)
        }
      }
    };

    statements.push({
      type: "create_table",
      table: table_name,
      columns,
      foreign_keys
    })
  };

  static extract_column(node, table_name) {
    let [target, method, ...args] = node.children;
    if (target?.type != "lvar" || target.children[0] != "t") return null;

    switch (method) {
    case "timestamps":

      return {columns: [
        {name: "created_at", type: "datetime", null: false},
        {name: "updated_at", type: "datetime", null: false}
      ]};

    case "references":
    case "belongs_to":
      return this.extract_references(args, table_name);

    default:
      return this.extract_regular_column(method, args)
    }
  };

  static extract_regular_column(type, args) {
    if (args.length == 0) return null;
    let column_name = this.extract_string_value(args[0]);
    if (!column_name) return null;
    let column = {name: column_name, type: type.toString()};

    for (let arg of args.slice(1)) {
      if (arg.type != "hash") continue;

      for (let pair of arg.children) {
        let key = pair.children[0];
        let value = pair.children[1];
        if (key.type != "sym") continue;

        switch (key.children[0]) {
        case "null":
          column.null = value.type != "false";
          break;

        case "default":
          column.default = this.extract_default_value(value);
          break;

        case "limit":
          if (value.type == "int") column.limit = value.children[0]
        }
      }
    };

    return {column}
  };

  static extract_references(args, table_name) {
    if (args.length == 0) return null;
    let ref_name = this.extract_string_value(args[0]);
    if (!ref_name) return null;
    let column_name = `${ref_name}_id`;
    let column = {name: column_name, type: "integer", null: false};
    let foreign_key = null;

    for (let arg of args.slice(1)) {
      if (arg.type != "hash") continue;

      for (let pair of arg.children) {
        let key = pair.children[0];
        let value = pair.children[1];
        if (key.type != "sym") continue;

        switch (key.children[0]) {
        case "null":
          if (value.type == "true") column.null = true;
          break;

        case "foreign_key":

          if (value.type == "true") {
            let ref_table = Ruby2JS.Inflector.pluralize(ref_name);

            foreign_key = {
              column: column_name,
              references_table: ref_table,
              references_column: "id"
            }
          }
        }
      }
    };

    return {column, foreign_key}
  };

  static extract_add_index(args, statements) {
    if (args.length < 2) return;
    let table_name = this.extract_string_value(args[0]);
    if (!table_name) return;

    let columns = args[1].type == "array" ? args[1].children.map(c => (
      this.extract_string_value(c)
    )).filter(x => x != null) : [this.extract_string_value(args[1])].filter(x => (
      x != null
    ));

    if (columns.length == 0) return;
    let options = {};

    for (let arg of args.slice(2)) {
      if (arg?.type != "hash") continue;

      for (let pair of arg.children) {
        let key = pair.children[0];
        let value = pair.children[1];
        if (key.type != "sym") continue;

        switch (key.children[0]) {
        case "name":
          options.name = this.extract_string_value(value);
          break;

        case "unique":
          options.unique = value.type == "true"
        }
      }
    };

    statements.push({
      type: "add_index",
      table: table_name,
      columns,
      options
    })
  };

  static extract_add_column(args, statements) {
    if (args.length < 3) return;
    let table_name = this.extract_string_value(args[0]);
    let column_name = this.extract_string_value(args[1]);
    let column_type = this.extract_string_value(args[2]);
    if (!table_name || !column_name || !column_type) return;

    statements.push({
      type: "add_column",
      table: table_name,
      column: column_name,
      column_type
    })
  };

  static extract_remove_column(args, statements) {
    if (args.length < 2) return;
    let table_name = this.extract_string_value(args[0]);
    let column_name = this.extract_string_value(args[1]);
    if (!table_name || !column_name) return;

    statements.push({
      type: "remove_column",
      table: table_name,
      column: column_name
    })
  };

  static extract_drop_table(args, statements) {
    if (args.length == 0) return;
    let table_name = this.extract_string_value(args[0]);
    if (!table_name) return;
    statements.push({type: "drop_table", table: table_name})
  };

  static extract_table_options(args) {
    let options = {};

    for (let arg of args.slice(1)) {
      if (arg?.type != "hash") continue;

      for (let pair of arg.children) {
        let key = pair.children[0];
        let value = pair.children[1];
        if (key.type != "sym") continue;

        switch (key.children[0]) {
        case "id":
          options.id = value.type != "false"
        }
      }
    };

    return options
  };

  static extract_string_value(node) {
    switch (node?.type) {
    case "str":
      return node.children[0];

    case "sym":
      return node.children[0].toString();

    default:
      return null
    }
  };

  static extract_default_value(node) {
    switch (node.type) {
    case "str":
      return node.children[0];

    case "int":
    case "float":
      return node.children[0];

    case "true":
      return true;

    case "false":
      return false;

    case "nil":
      return null;

    default:
      return null
    }
  };

  // SQL generation methods
  static create_table_sql(stmt) {
    let columns_sql = stmt.columns.map(col => this.column_def_sql(col));

    // Add foreign key constraints
    for (let fk of stmt.foreign_keys.filter(x => x != null)) {
      columns_sql.push(`FOREIGN KEY (${fk.column}) REFERENCES ${fk.references_table}(${fk.references_column})`)
    };

    return `CREATE TABLE IF NOT EXISTS ${stmt.table} (\n  ${columns_sql.join(",\n  ")}\n);`
  };

  static column_def_sql(col) {
    let parts = [col.name];
    parts.push(this.sql_type(col.type));

    if (col.primaryKey) {
      parts.push("PRIMARY KEY");
      if (col.autoIncrement) parts.push("AUTOINCREMENT")
    };

    if ("null" in col && col.null == false) parts.push("NOT NULL");
    if ("default" in col) parts.push(`DEFAULT ${this.sql_value(col.default)}`);
    return parts.join(" ")
  };

  static sql_type(type) {
    switch (type.toString()) {
    case "string":
      return "TEXT";

    case "text":
      return "TEXT";

    case "integer":
      return "INTEGER";

    case "float":
    case "decimal":
      return "REAL";

    case "boolean":
      return "INTEGER";

    case "datetime":
    case "timestamp":
      return "TEXT";

    case "date":
      return "TEXT";

    case "time":
      return "TEXT";

    case "binary":
    case "blob":
      return "BLOB";

    default:
      return "TEXT"
    }
  };

  static sql_value(value) {
    switch (value) {
    case String:
      return `'${value.replaceAll("'", "''")}'`;

    case Integer:
    case Float:
      return value.toString();

    case true:
      return "1";

    case false:
      return "0";

    case null:
      return "NULL";

    default:
      return `'${value}'`
    }
  };

  static add_index_sql(stmt) {
    let unique = stmt.options.unique ? "UNIQUE " : "";
    let name = stmt.options.name ?? `index_${stmt.table}_on_${stmt.columns.join("_")}`;
    let columns = stmt.columns.join(", ");
    return `CREATE ${unique}INDEX IF NOT EXISTS ${name} ON ${stmt.table} (${columns});`
  };

  static add_column_sql(stmt) {
    return `ALTER TABLE ${stmt.table} ADD COLUMN ${stmt.column} ${this.sql_type(stmt.column_type)};`
  };

  static remove_column_sql(stmt) {
    return `-- Note: SQLite may not support DROP COLUMN\n-- ALTER TABLE ${stmt.table} DROP COLUMN ${stmt.column};`
  };

  static drop_table_sql(stmt) {
    return `DROP TABLE IF EXISTS ${stmt.table};`
  }
}
