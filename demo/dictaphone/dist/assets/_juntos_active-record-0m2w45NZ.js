import { A, C, a, b, c, d, e, f, g, h, i, j, k, l, m, o, q, r, n } from "./index-JvRCprRv.js";
const DB_CONFIG = { "adapter": "dexie", "max_connections": '<%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>', "timeout": 5e3, "database": "storage/development.sqlite3" };
export {
  A as ActiveRecord,
  C as CollectionProxy,
  DB_CONFIG,
  a as addColumn,
  b as addIndex,
  c as attr_accessor,
  d as closeDatabase,
  e as createTable,
  f as defineSchema,
  g as dropTable,
  h as execSQL,
  i as execute,
  j as getDatabase,
  k as initDatabase,
  l as insert,
  m as modelRegistry,
  o as openDatabase,
  q as query,
  r as registerSchema,
  n as removeColumn
};
//# sourceMappingURL=_juntos_active-record-0m2w45NZ.js.map
