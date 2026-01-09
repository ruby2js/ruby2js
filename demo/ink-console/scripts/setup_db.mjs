#!/usr/bin/env node
// Setup script to create and seed the development database

import Database from 'better-sqlite3';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { mkdirSync, existsSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '..');
const DB_PATH = join(PROJECT_ROOT, 'db/development.sqlite3');

// Ensure db directory exists
const dbDir = dirname(DB_PATH);
if (!existsSync(dbDir)) {
  mkdirSync(dbDir, { recursive: true });
}

console.log(`Setting up database at ${DB_PATH}...`);

const db = new Database(DB_PATH);

// Create tables
console.log('Creating tables...');

db.exec(`
  DROP TABLE IF EXISTS comments;
  DROP TABLE IF EXISTS posts;
  DROP TABLE IF EXISTS users;

  CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    admin INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    body TEXT,
    published INTEGER DEFAULT 0,
    user_id INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );

  CREATE TABLE comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    body TEXT NOT NULL,
    post_id INTEGER NOT NULL,
    user_id INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
  );
`);

// Seed data
console.log('Seeding data...');

const insertUser = db.prepare(`
  INSERT INTO users (name, email, admin) VALUES (?, ?, ?)
`);

const insertPost = db.prepare(`
  INSERT INTO posts (title, body, published, user_id) VALUES (?, ?, ?, ?)
`);

const insertComment = db.prepare(`
  INSERT INTO comments (body, post_id, user_id) VALUES (?, ?, ?)
`);

// Users
insertUser.run('Alice', 'alice@example.com', 1);
insertUser.run('Bob', 'bob@example.com', 0);
insertUser.run('Charlie', 'charlie@example.com', 0);

// Posts
insertPost.run('Getting Started with Ruby2JS', 'This is an introduction to Ruby2JS...', 1, 1);
insertPost.run('Advanced Transpilation Tips', 'Here are some advanced techniques...', 1, 1);
insertPost.run('Draft: Upcoming Features', 'Working on new features...', 0, 2);
insertPost.run('Building CLI Apps with Ink', 'Ink is a React renderer for CLIs...', 1, 2);
insertPost.run('Testing Your Code', 'Unit testing best practices...', 1, 3);

// Comments
insertComment.run('Great introduction!', 1, 2);
insertComment.run('Very helpful, thanks!', 1, 3);
insertComment.run('Looking forward to more tips.', 2, 2);
insertComment.run('This is awesome!', 4, 1);
insertComment.run('Can you cover hooks next?', 4, 3);

// Verify
console.log('\nData created:');
console.log(`  Users: ${db.prepare('SELECT COUNT(*) as count FROM users').get().count}`);
console.log(`  Posts: ${db.prepare('SELECT COUNT(*) as count FROM posts').get().count}`);
console.log(`  Comments: ${db.prepare('SELECT COUNT(*) as count FROM comments').get().count}`);

db.close();
console.log('\nDatabase setup complete!');
