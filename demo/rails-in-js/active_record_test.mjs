// Test the ActiveRecord wrapper
// Demonstrates Ruby-like ActiveRecord API

import initSqlJs from 'sql.js';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { ActiveRecord, setDatabase, attr_accessor } from './active_record.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Initialize sql.js
const SQL = await initSqlJs({
  locateFile: file => join(__dirname, 'node_modules', 'sql.js', 'dist', file)
});

const db = new SQL.Database();
setDatabase(db);

// --- Define Models (what transpiled Ruby would look like) ---

class Article extends ActiveRecord {
  static tableName = 'articles';

  // has_many :comments
  get comments() {
    return this.hasMany(Comment, 'article_id');
  }
}
attr_accessor(Article, 'title', 'body', 'created_at', 'updated_at');

class Comment extends ActiveRecord {
  static tableName = 'comments';

  // belongs_to :article
  get article() {
    return this.belongsTo(Article, 'article_id');
  }
}
attr_accessor(Comment, 'article_id', 'commenter', 'body', 'status', 'created_at');

// --- Setup Schema ---
console.log('=== ActiveRecord Wrapper Test ===\n');

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

// --- Test CRUD with ActiveRecord API ---

console.log('1. Article.create (INSERT)');
const article1 = Article.create({ title: 'Hello Rails', body: 'I am on Rails!' });
console.log(`   Created: Article#${article1.id} "${article1.title}"`);

const article2 = Article.create({ title: 'My Second Post', body: 'More content' });
console.log(`   Created: Article#${article2.id} "${article2.title}"\n`);

console.log('2. Article.find(1)');
const found = Article.find(1);
console.log(`   Found: "${found.title}"\n`);

console.log('3. Article.all');
const all = Article.all();
console.log(`   All articles (${all.length}):`);
all.forEach(a => console.log(`     [${a.id}] ${a.title}`));
console.log();

console.log('4. article.update (UPDATE)');
article1.title = 'Hello Rails (Updated)';
article1.save();
console.log(`   Updated: "${Article.find(1).title}"\n`);

console.log('5. Comment.create with association');
const comment1 = Comment.create({ article_id: article1.id, commenter: 'Alice', body: 'Great post!', status: 'approved' });
const comment2 = Comment.create({ article_id: article1.id, commenter: 'Bob', body: 'Thanks!', status: 'pending' });
console.log(`   Created ${Comment.count()} comments\n`);

console.log('6. article.comments (has_many)');
const comments = article1.comments;
console.log(`   Article "${article1.title}" has ${comments.length} comments:`);
comments.forEach(c => console.log(`     - ${c.commenter}: "${c.body}" [${c.status}]`));
console.log();

console.log('7. comment.article (belongs_to)');
const parentArticle = comment1.article;
console.log(`   Comment by ${comment1.commenter} belongs to: "${parentArticle.title}"\n`);

console.log('8. Comment.where (query)');
const approved = Comment.where({ status: 'approved' });
console.log(`   Approved comments: ${approved.length}`);
approved.forEach(c => console.log(`     - ${c.commenter}: "${c.body}"`));
console.log();

console.log('9. Article.first / Article.last');
console.log(`   First: "${Article.first().title}"`);
console.log(`   Last: "${Article.last().title}"\n`);

console.log('10. comment.destroy (DELETE)');
comment2.destroy();
console.log(`   Deleted comment by Bob, remaining: ${Comment.count()}\n`);

console.log('11. Article.count');
console.log(`   Total articles: ${Article.count()}`);
console.log(`   Total comments: ${Comment.count()}\n`);

db.close();
console.log('=== Test complete ===');
