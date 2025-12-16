export const Schema = (() => {
  function create_tables(db) {
    db.run("CREATE TABLE IF NOT EXISTS articles (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,\n        title TEXT NOT NULL,\n        body TEXT,\n        created_at TEXT,\n        updated_at TEXT\n      )");
    return db.run("CREATE TABLE IF NOT EXISTS comments (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,\n        article_id INTEGER NOT NULL,\n        commenter TEXT,\n        body TEXT,\n        status TEXT DEFAULT 'pending',\n        created_at TEXT,\n        updated_at TEXT,\n        FOREIGN KEY (article_id) REFERENCES articles(id)\n      )")
  };

  return {create_tables}
})()