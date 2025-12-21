// sql.js prototype - Stage 0 validation
// Tests basic CRUD operations with SQLite in JavaScript

import initSqlJs from 'sql.js';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Initialize sql.js with WASM (use local node_modules path for Node.js)
const SQL = await initSqlJs({
  locateFile: file => join(__dirname, 'node_modules', 'sql.js', 'dist', file)
});

// Create an in-memory database
const db = new SQL.Database();

console.log('=== sql.js CRUD Prototype ===\n');

// --- Schema ---
console.log('1. Creating tables...');
db.run(`
  CREATE TABLE articles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    body TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
  )
`);

db.run(`
  CREATE TABLE comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id INTEGER NOT NULL,
    commenter TEXT,
    body TEXT,
    status TEXT DEFAULT 'pending',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (article_id) REFERENCES articles(id)
  )
`);
console.log('   Tables created: articles, comments\n');

// --- CREATE ---
console.log('2. INSERT (Create)...');
db.run(`INSERT INTO articles (title, body) VALUES (?, ?)`,
  ['Hello Rails', 'I am on Rails!']);
db.run(`INSERT INTO articles (title, body) VALUES (?, ?)`,
  ['My Second Post', 'More content here']);

const articleId = db.exec('SELECT last_insert_rowid()')[0].values[0][0];
console.log(`   Created 2 articles, last id: ${articleId}\n`);

// Add comments
db.run(`INSERT INTO comments (article_id, commenter, body, status) VALUES (?, ?, ?, ?)`,
  [1, 'Alice', 'Great post!', 'approved']);
db.run(`INSERT INTO comments (article_id, commenter, body, status) VALUES (?, ?, ?, ?)`,
  [1, 'Bob', 'Thanks for sharing', 'pending']);
console.log('   Created 2 comments on article 1\n');

// --- READ ---
console.log('3. SELECT (Read)...');

// Find all
const allArticles = db.exec('SELECT * FROM articles');
console.log('   All articles:');
allArticles[0].values.forEach(row => {
  console.log(`     [${row[0]}] ${row[1]}`);
});

// Find by id
const stmt = db.prepare('SELECT * FROM articles WHERE id = ?');
stmt.bind([1]);
if (stmt.step()) {
  const article = stmt.getAsObject();
  console.log(`\n   Article.find(1): "${article.title}"`);
}
stmt.free();

// Where clause
const approved = db.exec(`SELECT * FROM comments WHERE status = 'approved'`);
console.log(`\n   Comments.where(status: 'approved'): ${approved[0]?.values.length || 0} found\n`);

// --- UPDATE ---
console.log('4. UPDATE...');
db.run(`UPDATE articles SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`,
  ['Hello Rails (Updated)', 1]);

const updated = db.exec('SELECT title, updated_at FROM articles WHERE id = 1');
console.log(`   Article 1 now: "${updated[0].values[0][0]}"\n`);

// --- DELETE ---
console.log('5. DELETE...');
db.run('DELETE FROM comments WHERE id = ?', [2]);
const remaining = db.exec('SELECT COUNT(*) FROM comments');
console.log(`   Deleted comment 2, ${remaining[0].values[0][0]} comments remaining\n`);

// --- Associations (JOIN) ---
console.log('6. JOIN (has_many association)...');
const articlesWithComments = db.exec(`
  SELECT a.title, c.commenter, c.body
  FROM articles a
  LEFT JOIN comments c ON c.article_id = a.id
  WHERE a.id = 1
`);
console.log('   Article 1 with comments:');
articlesWithComments[0].values.forEach(row => {
  console.log(`     "${row[0]}" - Comment by ${row[1]}: "${row[2]}"`);
});

// --- Cleanup ---
db.close();
console.log('\n=== Prototype complete ===');
