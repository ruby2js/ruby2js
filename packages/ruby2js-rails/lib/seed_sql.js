import { Ruby2JS } from "ruby2js/ruby2js.js";

export class SeedSQL {
  // Generate SQL for a seeds.rb file
  // Returns a hash with :sql (SQL statements) and :inserts (count)
  static generate(seeds_path) {
    if (!File.exist(seeds_path)) return {sql: "", inserts: 0};
    let source = File.read(seeds_path);
    let [ast, _] = Ruby2JS.parse(source);
    if (!ast) return {sql: "", inserts: 0};
    let inserts = [];

    // Extract create statements
    extract_creates(ast, inserts);
    if (inserts.length == 0) return {sql: "", inserts: 0};
    let sql_parts = [];
    sql_parts.push("-- Ruby2JS Generated Seeds");
    sql_parts.push(`-- Generated at: ${Time.now.utc}`);
    sql_parts.push("");

    for (let insert of inserts) {
      sql_parts.push(generate_insert_sql(insert))
    };

    return {sql: sql_parts.join("\n"), inserts: inserts.length}
  };

  // Extract all Model.create/create! calls from the AST
  static extract_creates(node, inserts) {
    let target, method, args, model_name, underscored, table_name, attributes;
    if (!node) return;

    switch (node.type) {
    case "send":
      let [target, method, ...args] = node.children;

      if (["create", "create!"].includes(method) && target?.type == "const") {
        model_name = target.children[1].toString();

        // tableize: underscore + pluralize (e.g., "Message" -> "messages")
        underscored = model_name.replaceAll(/([a-z])([A-Z])/g, "$1_$2").toLowerCase();
        table_name = Ruby2JS.Inflector.pluralize(underscored);

        if (args[0]?.type == "hash") {
          attributes = extract_hash(args[0]);
          inserts.push({table: table_name, attributes})
        }
      };

      break;

    case "begin":
    case "block":
    case "if":

      for (let child of node.children) {
        if (child) extract_creates(child, inserts)
      }
    }
  };

  // Extract key-value pairs from a hash node
  static extract_hash(node) {
    let attributes = {};

    for (let pair of node.children) {
      if (pair.type != "pair") continue;
      let [key_node, value_node] = pair.children;

      let key = (() => {
        switch (key_node.type) {
        case "sym":
          return key_node.children[0].toString();

        case "str":
          return key_node.children[0];

        default:
          return
        }
      })();

      let value = extract_value(value_node);
      attributes[key] = value
    };

    return attributes
  };

  // Extract a Ruby value from an AST node
  static extract_value(node) {
    switch (node.type) {
    case "str":
      return node.children[0];

    case "int":
      return node.children[0];

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

  // Generate SQL INSERT statement
  static generate_insert_sql(insert) {
    let table = insert.table;
    let attrs = insert.attributes.dup();
    attrs.created_at = "now";
    attrs.updated_at = "now";
    let columns = attrs.keys;
    let values = attrs.values.map(v => sql_value(v));
    return `INSERT INTO ${table} (${columns.join(", ")}) VALUES (${values.join(", ")});`
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

    case "now":
      return "datetime('now')";

    default:
      return `'${value}'`
    }
  }
}
