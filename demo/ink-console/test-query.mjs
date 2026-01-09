#!/usr/bin/env node
// Test the query evaluator with Ruby2JS selfhost

import { initQueryEvaluator, evaluateQuery, formatResult } from './lib/query_evaluator.mjs';

// Mock model for testing
class Post {
  static records = [
    { id: 1, title: 'Getting Started', published: true },
    { id: 2, title: 'Advanced Tips', published: true },
    { id: 3, title: 'Draft Post', published: false }
  ];

  static all() {
    return this.records.map(r => new Post(r));
  }

  static where(conditions) {
    const filtered = this.records.filter(r => {
      return Object.entries(conditions).every(([k, v]) => r[k] === v);
    });
    return filtered.map(r => new Post(r));
  }

  static find(id) {
    const record = this.records.find(r => r.id === id);
    return record ? new Post(record) : null;
  }

  static count() {
    return this.records.length;
  }

  constructor(attrs) {
    this.attributes = attrs;
    this.id = attrs.id;
    this.title = attrs.title;
    this.published = attrs.published;
  }
}

async function runTests() {
  console.log('=== Query Evaluator Tests ===\n');

  console.log('Initializing Ruby2JS selfhost...');
  await initQueryEvaluator();
  console.log('Done!\n');

  const models = { Post };

  const tests = [
    { query: 'Post.all', description: 'Get all records' },
    { query: 'Post.count', description: 'Count records' },
    { query: 'Post.find(1)', description: 'Find by ID' },
    { query: 'Post.where(published: true)', description: 'Where clause' },
    { query: '1 + 2', description: 'Simple expression' },
    { query: '"hello".upcase', description: 'String method' },
  ];

  for (const { query, description } of tests) {
    console.log(`Test: ${description}`);
    console.log(`  Query: ${query}`);

    try {
      const result = await evaluateQuery(query, models);
      const formatted = formatResult(result);
      console.log(`  Type: ${formatted.type}`);
      console.log(`  Result: ${JSON.stringify(formatted.data, null, 2).split('\n').join('\n          ')}`);
    } catch (e) {
      console.log(`  Error: ${e.message}`);
    }
    console.log();
  }

  console.log('=== Tests Complete ===');
}

runTests().catch(console.error);
