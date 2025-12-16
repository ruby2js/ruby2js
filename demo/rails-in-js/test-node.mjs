// Node.js test for transpiled models
// Tests basic module loading and class structure

import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Polyfills
globalThis.Time = {
  now() {
    return { toString() { return new Date().toISOString(); } };
  }
};

// Mock DB for testing
globalThis.DB = {
  exec(sql) {
    console.log(`  DB.exec: ${sql.slice(0, 50)}...`);
    return [{ columns: ['id', 'title', 'body', 'created_at', 'updated_at'], values: [] }];
  },
  prepare(sql) {
    console.log(`  DB.prepare: ${sql.slice(0, 50)}...`);
    return {
      bind(params) { console.log(`  stmt.bind: ${JSON.stringify(params)}`); },
      step() { return false; },
      getAsObject() { return {}; },
      free() {}
    };
  },
  run(sql, params) {
    console.log(`  DB.run: ${sql.slice(0, 50)}...`);
  }
};

async function test() {
  console.log('=== Testing Transpiled Models ===\n');

  try {
    console.log('1. Loading ApplicationRecord...');
    const { ApplicationRecord } = await import('./dist/models/application_record.js');
    console.log('   OK - ApplicationRecord loaded');

    console.log('\n2. Loading Article...');
    const { Article } = await import('./dist/models/article.js');
    console.log('   OK - Article loaded');
    console.log(`   table_name: ${Article.table_name}`);

    console.log('\n3. Loading Comment...');
    const { Comment } = await import('./dist/models/comment.js');
    console.log('   OK - Comment loaded');
    console.log(`   table_name: ${Comment.table_name}`);

    console.log('\n4. Testing Article instantiation...');
    const article = new Article({ id: 1, title: 'Test', body: 'Test body content here' });
    console.log(`   OK - Created article with id=${article.id}, title="${article.title}"`);

    console.log('\n5. Testing Article.all (getter)...');
    const all = Article.all;
    console.log(`   OK - Article.all returned ${all.length} items`);

    console.log('\n6. Testing Article.find...');
    try {
      Article.find(999);
    } catch (e) {
      console.log(`   OK - Article.find throws correctly: "${e}"`);
    }

    console.log('\n7. Testing validation...');
    const invalidArticle = new Article({ title: '', body: 'short' });
    const isValid = invalidArticle.is_valid;  // getter access
    console.log(`   is_valid returned: ${isValid}`);
    console.log(`   errors: ${JSON.stringify(invalidArticle.errors)}`);

    console.log('\n8. Testing Comment instantiation...');
    const comment = new Comment({ id: 1, article_id: 1, commenter: 'Alice', body: 'Nice post!' });
    console.log(`   OK - Created comment with id=${comment.id}, commenter="${comment.commenter}"`);

    console.log('\n=== All Tests Passed ===');
  } catch (e) {
    console.error('\n=== TEST FAILED ===');
    console.error(`Error: ${e.message}`);
    console.error(e.stack);
    process.exit(1);
  }
}

test();
