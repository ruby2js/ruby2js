import { execSQL } from "../lib/active_record.mjs";

export const Schema = (() => {
  function create_tables() {
    return execSQL("CREATE TABLE IF NOT EXISTS posts (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,\n        title TEXT NOT NULL,\n        body TEXT,\n        author TEXT DEFAULT 'Anonymous',\n        created_at TEXT,\n        updated_at TEXT\n      )")
  };

  return {create_tables}
})()

// Database schema - idiomatic Rails
//# sourceMappingURL=schema.js.map
