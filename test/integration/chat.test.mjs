// Integration tests for the chat demo
// Tests CRUD operations, validations, and controller actions
// Uses better-sqlite3 with :memory: for fast, isolated tests

import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIST_DIR = join(__dirname, 'workspace/chat/dist');

// Dynamic imports - loaded once in beforeAll
let Message;
let MessagesController;
let Application, initDatabase, migrations, modelRegistry;

describe('Chat Integration Tests', () => {
  beforeAll(async () => {
    // Import the active_record adapter (for initDatabase and modelRegistry)
    const activeRecord = await import(join(DIST_DIR, 'lib/active_record.mjs'));
    initDatabase = activeRecord.initDatabase;
    modelRegistry = activeRecord.modelRegistry;

    // Import Application from rails.js
    const rails = await import(join(DIST_DIR, 'lib/rails.js'));
    Application = rails.Application;

    // Import migrations
    const migrationsModule = await import(join(DIST_DIR, 'db/migrate/index.js'));
    migrations = migrationsModule.migrations;

    // Import models
    const models = await import(join(DIST_DIR, 'app/models/index.js'));
    Message = models.Message;

    // Import controllers
    const messagesCtrl = await import(join(DIST_DIR, 'app/controllers/messages_controller.js'));
    MessagesController = messagesCtrl.MessagesController;

    // Configure Application with migrations
    Application.configure({ migrations });
    Application.registerModels({ Message });

    // Register models with adapter's registry
    modelRegistry.Message = Message;
  });

  beforeEach(async () => {
    // Initialize fresh in-memory database for each test
    await initDatabase({ database: ':memory:' });

    // Get the adapter module for runMigrations
    const adapter = await import(join(DIST_DIR, 'lib/active_record.mjs'));

    // Run migrations using Application
    await Application.runMigrations(adapter);
  });

  describe('Message Model', () => {
    it('creates a message with valid attributes', async () => {
      const message = await Message.create({
        username: 'Alice',
        body: 'Hello, world!'
      });

      expect(message.id).toBeDefined();
      expect(message.username).toBe('Alice');
      expect(message.body).toBe('Hello, world!');
      expect(message.id).toBeGreaterThan(0);
    });

    it('validates username presence', async () => {
      const message = new Message({ username: '', body: 'Test message' });
      const saved = await message.save();

      expect(saved).toBe(false);
      expect(message.errors.username).toBeDefined();
    });

    it('validates body presence', async () => {
      const message = new Message({ username: 'Alice', body: '' });
      const saved = await message.save();

      expect(saved).toBe(false);
      expect(message.errors.body).toBeDefined();
    });

    it('finds message by id', async () => {
      const created = await Message.create({
        username: 'Bob',
        body: 'Find this message'
      });

      const found = await Message.find(created.id);
      expect(found.username).toBe('Bob');
      expect(found.body).toBe('Find this message');
    });

    it('lists all messages', async () => {
      await Message.create({ username: 'Alice', body: 'First message' });
      await Message.create({ username: 'Bob', body: 'Second message' });
      await Message.create({ username: 'Carol', body: 'Third message' });

      const messages = await Message.all();
      expect(messages.length).toBe(3);
    });

    it('updates a message', async () => {
      const message = await Message.create({
        username: 'Alice',
        body: 'Original message'
      });

      await message.update({ body: 'Updated message' });

      const reloaded = await Message.find(message.id);
      expect(reloaded.body).toBe('Updated message');
    });

    it('destroys a message', async () => {
      const message = await Message.create({
        username: 'Alice',
        body: 'To be deleted'
      });
      const id = message.id;

      await message.destroy();

      const found = await Message.findBy({ id });
      expect(found).toBeNull();
    });
  });

  describe('MessagesController', () => {
    it('index action returns message list', async () => {
      await Message.create({ username: 'Alice', body: 'Hello everyone!' });
      await Message.create({ username: 'Bob', body: 'Hi Alice!' });

      const context = {
        params: {},
        flash: { get: () => '', consumeNotice: () => '', consumeAlert: () => '' },
        contentFor: {},
        cookies: { chat_username: 'Guest' }
      };

      const html = await MessagesController.index(context);
      expect(html).toContain('Alice');
      expect(html).toContain('Hello everyone!');
      expect(html).toContain('Bob');
    });

    it('create action adds a new message', async () => {
      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {},
        cookies: {},
        request: { headers: { accept: 'text/html' } }
      };

      const params = {
        username: 'Carol',
        body: 'New message from controller'
      };

      const result = await MessagesController.create(context, params);

      // Should return redirect or turbo stream after successful create
      const messages = await Message.all();
      expect(messages.length).toBe(1);
      expect(messages[0].username).toBe('Carol');
      expect(messages[0].body).toBe('New message from controller');
    });

    it('destroy action removes a message', async () => {
      const message = await Message.create({
        username: 'Alice',
        body: 'Message to delete'
      });

      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {},
        request: { headers: { accept: 'text/html' } }
      };

      await MessagesController.destroy(context, message.id);

      const messages = await Message.all();
      expect(messages.length).toBe(0);
    });
  });

  describe('Query Interface', () => {
    beforeEach(async () => {
      await Message.create({ username: 'Alice', body: 'First message' });
      await Message.create({ username: 'Bob', body: 'Second message' });
      await Message.create({ username: 'Alice', body: 'Third message' });
    });

    it('where filters by attributes', async () => {
      const results = await Message.where({ username: 'Alice' });
      expect(results.length).toBe(2);
      results.forEach(m => expect(m.username).toBe('Alice'));
    });

    it('order sorts results', async () => {
      const results = await Message.order({ username: 'desc' });
      expect(results[0].username).toBe('Bob');
      expect(results[1].username).toBe('Alice');
    });

    it('limit restricts result count', async () => {
      const results = await Message.limit(2);
      expect(results.length).toBe(2);
    });

    it('first returns single record', async () => {
      const first = await Message.first();
      expect(first).toBeDefined();
      expect(first.body).toBe('First message');
    });

    it('count returns record count', async () => {
      const count = await Message.count();
      expect(count).toBe(3);
    });
  });

  describe('Path Helpers', () => {
    let messages_path, message_path;

    beforeAll(async () => {
      const paths = await import(join(DIST_DIR, 'config/paths.js'));
      messages_path = paths.messages_path;
      message_path = paths.message_path;
    });

    it('messages_path returns correct path', () => {
      expect(messages_path()).toBe('/messages');
    });

    it('message_path returns correct path with id', async () => {
      const message = await Message.create({
        username: 'Test',
        body: 'Test message'
      });
      expect(message_path(message)).toBe(`/messages/${message.id}`);
    });

    it('path helpers should not double the base path', () => {
      const path = messages_path();
      expect(path).not.toContain('/messages/messages');
    });
  });
});
