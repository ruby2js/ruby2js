// Database schema - creates tables for the blog
function create_schema(db) {
  db.run("    CREATE TABLE IF NOT EXISTS articles (\n      id INTEGER PRIMARY KEY AUTOINCREMENT,\n      title TEXT NOT NULL,\n      body TEXT,\n      created_at TEXT,\n      updated_at TEXT\n    )\n");
  return db.run("    CREATE TABLE IF NOT EXISTS comments (\n      id INTEGER PRIMARY KEY AUTOINCREMENT,\n      article_id INTEGER NOT NULL,\n      commenter TEXT,\n      body TEXT,\n      status TEXT DEFAULT 'pending',\n      created_at TEXT,\n      FOREIGN KEY (article_id) REFERENCES articles(id)\n    )\n")
};

// Seed data for development
function seed_data() {
  if (Article.count > 0) return;

  let article1 = Article.create({
    title: "Hello Rails",
    body: "I am on Rails! This is my first blog post using the Rails-in-JS demo. It demonstrates that you can write Ruby code that transpiles to JavaScript and runs entirely in the browser."
  });

  let article2 = Article.create({
    title: "Getting Started with Ruby2JS",
    body: "Ruby2JS is a Ruby to JavaScript transpiler. It parses Ruby source code and generates equivalent JavaScript. This demo shows how you can build a full Rails-like application that runs in JavaScript."
  });

  Comment.create({
    article_id: article1.id,
    commenter: "Alice",
    body: "Great post! Welcome to the world of Rails-in-JS.",
    status: "approved"
  });

  return Comment.create({
    article_id: article1.id,
    commenter: "Bob",
    body: "This is really cool. Looking forward to more posts!",
    status: "approved"
  })
}