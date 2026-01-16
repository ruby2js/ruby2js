// Integration tests for the notes demo
// Tests CRUD operations, validations, and JSON API responses
// Uses better-sqlite3 with :memory: for fast, isolated tests
// Uses jsdom environment (default) for React component testing

import { describe, it, expect, beforeAll, beforeEach, afterEach } from 'vitest';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { render, screen, cleanup } from '@testing-library/react';
import React from 'react';

const __dirname = dirname(fileURLToPath(import.meta.url));
// Use workspace/notes for CI, fall back to demo/notes for local testing
const WORKSPACE_DIR = join(__dirname, 'workspace/notes');
const DEMO_DIR = join(__dirname, '../../demo/notes');
import { existsSync } from 'fs';
const DIST_DIR = existsSync(join(WORKSPACE_DIR, 'dist'))
  ? join(WORKSPACE_DIR, 'dist')
  : join(DEMO_DIR, 'dist');

// Dynamic imports - loaded once in beforeAll
let Note;
let NotesController;
let NoteViews;  // For direct view testing
let Application, initDatabase, migrations, modelRegistry;
let notes_path, note_path;

describe('Notes Integration Tests', () => {
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
    Note = models.Note;

    // Import controllers
    const notesCtrl = await import(join(DIST_DIR, 'app/controllers/notes_controller.js'));
    NotesController = notesCtrl.NotesController;

    // Import views for direct React component testing
    // Each RBX file becomes a separate .js file with default export
    const indexView = await import(join(DIST_DIR, 'app/views/notes/index.js'));
    const showView = await import(join(DIST_DIR, 'app/views/notes/show.js'));
    NoteViews = {
      Index: indexView.default,
      Show: showView.default
    };

    // Import path helpers
    const paths = await import(join(DIST_DIR, 'config/paths.js'));
    notes_path = paths.notes_path;
    note_path = paths.note_path;

    // Configure Application with migrations
    Application.configure({ migrations });
    Application.registerModels({ Note });

    // Register models with adapter's registry
    modelRegistry.Note = Note;
  });

  beforeEach(async () => {
    // Initialize fresh in-memory database for each test
    await initDatabase({ database: ':memory:' });

    // Get the adapter module for runMigrations
    const adapter = await import(join(DIST_DIR, 'lib/active_record.mjs'));

    // Run migrations
    await Application.runMigrations(adapter);
  });

  describe('Note Model', () => {
    it('creates a note with valid attributes', async () => {
      const note = await Note.create({
        title: 'Test Note',
        body: 'This is the body of the test note.'
      });

      expect(note.id).toBeDefined();
      expect(note.title).toBe('Test Note');
      expect(note.id).toBeGreaterThan(0);
    });

    it('validates title presence', async () => {
      const note = new Note({ title: '', body: 'Valid body content.' });
      const saved = await note.save();

      expect(saved).toBe(false);
      expect(note.errors.title).toBeDefined();
    });

    it('validates body presence', async () => {
      const note = new Note({ title: 'Valid Title', body: '' });
      const saved = await note.save();

      expect(saved).toBe(false);
      expect(note.errors.body).toBeDefined();
    });

    it('finds note by id', async () => {
      const created = await Note.create({
        title: 'Find Me',
        body: 'This note should be findable by its ID.'
      });

      const found = await Note.find(created.id);
      expect(found.title).toBe('Find Me');
    });

    it('lists all notes', async () => {
      await Note.create({ title: 'Note 1', body: 'First note body.' });
      await Note.create({ title: 'Note 2', body: 'Second note body.' });

      const notes = await Note.all();
      expect(notes.length).toBe(2);
    });

    it('updates a note', async () => {
      const note = await Note.create({
        title: 'Original Title',
        body: 'Original body content.'
      });

      await note.update({ title: 'Updated Title' });

      const reloaded = await Note.find(note.id);
      expect(reloaded.title).toBe('Updated Title');
    });

    it('destroys a note', async () => {
      const note = await Note.create({
        title: 'To Delete',
        body: 'This note will be deleted.'
      });
      const id = note.id;

      await note.destroy();

      const found = await Note.findBy({ id });
      expect(found).toBeNull();
    });
  });

  describe('Note Ordering', () => {
    it('order method sorts by updated_at desc', async () => {
      // Create notes in order
      await Note.create({ title: 'First Note', body: 'Created first.' });
      await Note.create({ title: 'Second Note', body: 'Created second.' });
      await Note.create({ title: 'Third Note', body: 'Created third.' });

      const notes = await Note.order({ updated_at: 'desc' });
      expect(notes.length).toBe(3);
      // Most recently created should be first (since updated_at == created_at initially)
      expect(notes[0].title).toBe('Third Note');
    });

    it('where method filters by attributes', async () => {
      await Note.create({ title: 'Find This', body: 'Should be found.' });
      await Note.create({ title: 'Other Note', body: 'Not this one.' });

      const results = await Note.where({ title: 'Find This' });
      expect(results.length).toBe(1);
      expect(results[0].title).toBe('Find This');
    });
  });

  describe('NotesController', () => {
    // Cleanup React Testing Library after each test
    afterEach(() => {
      cleanup();
    });

    // Helper to create mock context
    const createContext = (overrides = {}) => ({
      params: {},
      flash: {
        get: () => '',
        set: () => {},
        consumeNotice: () => ({ present: false }),
        consumeAlert: () => ''
      },
      contentFor: {},
      request: {
        headers: { accept: 'text/html' }
      },
      ...overrides
    });

    it('index view renders with React Testing Library', async () => {
      // Create test data
      await Note.create({ title: 'Listed Note', body: 'This should appear in the index.' });

      // Render the Index component directly using React Testing Library
      // The Index component uses hooks (useState, useEffect) so we must render it properly
      render(React.createElement(NoteViews.Index));

      // The component should render its basic structure
      // Note: The actual data fetching happens async via useEffect
      expect(screen.getByText('Notes')).toBeDefined();
      expect(screen.getByRole('button', { name: 'New Note' })).toBeDefined();
    });

    it('show view renders note details', async () => {
      // Create test data
      const note = await Note.create({
        title: 'View Test Note',
        body: 'This note body should be visible.',
        updated_at: new Date().toISOString()
      });

      // Render the Show component with note prop
      render(React.createElement(NoteViews.Show, { note }));

      // The component should render the note details
      expect(screen.getByText('View Test Note')).toBeDefined();
      expect(screen.getByText('This note body should be visible.')).toBeDefined();
      expect(screen.getByRole('button', { name: 'Back to Notes' })).toBeDefined();
    });

    it('show action returns note details', async () => {
      const note = await Note.create({
        title: 'Show This Note',
        body: 'The full note body should be visible.'
      });

      const context = createContext({ params: { id: note.id } });
      const result = await NotesController.show(context, note.id);

      // RBX views return objects (React components), not strings
      expect(result).toBeDefined();
      expect(typeof result).toBe('object');
    });

    it('create action adds a new note', async () => {
      const context = createContext();
      const params = {
        title: 'New Note via Controller',
        body: 'Created through the controller action.'
      };

      const result = await NotesController.create(context, params);

      // Should return redirect after successful create
      expect(result.redirect).toBeDefined();

      const notes = await Note.all();
      expect(notes.length).toBe(1);
      expect(notes[0].title).toBe('New Note via Controller');
    });

    it('update action modifies existing note', async () => {
      const note = await Note.create({
        title: 'Original',
        body: 'Original body.'
      });

      const context = createContext();
      const result = await NotesController.update(context, note.id, { title: 'Modified' });

      expect(result.redirect).toBeDefined();

      const updated = await Note.find(note.id);
      expect(updated.title).toBe('Modified');
    });

    it('destroy action removes note', async () => {
      const note = await Note.create({
        title: 'To Delete',
        body: 'Will be deleted.'
      });
      const id = note.id;

      const context = createContext();
      const result = await NotesController.destroy(context, id);

      expect(result.redirect).toBeDefined();

      const found = await Note.findBy({ id });
      expect(found).toBeNull();
    });
  });

  describe('JSON API Responses', () => {
    // Helper to create mock context with JSON Accept header
    const createJsonContext = (overrides = {}) => ({
      params: {},
      flash: {
        get: () => '',
        set: () => {},
        consumeNotice: () => ({ present: false }),
        consumeAlert: () => ''
      },
      contentFor: {},
      request: {
        headers: { accept: 'application/json' }
      },
      ...overrides
    });

    it('index returns JSON when Accept header is application/json', async () => {
      await Note.create({ title: 'JSON Note 1', body: 'First note.' });
      await Note.create({ title: 'JSON Note 2', body: 'Second note.' });

      const context = createJsonContext();
      const result = await NotesController.index(context);

      // Should return { json: data } object for JSON request
      expect(result).toHaveProperty('json');
      // The json property should be the notes data (array or query result)
    });

    it('show returns JSON when Accept header is application/json', async () => {
      const note = await Note.create({
        title: 'JSON Show Note',
        body: 'Note for JSON show test.'
      });

      const context = createJsonContext({ params: { id: note.id } });
      const result = await NotesController.show(context, note.id);

      expect(result).toHaveProperty('json');
    });

    it('create returns JSON on success when Accept is application/json', async () => {
      const context = createJsonContext();
      const params = {
        title: 'JSON Created Note',
        body: 'Created via JSON API.'
      };

      const result = await NotesController.create(context, params);

      // For successful JSON create, should return { json: note, status: 201 } or similar
      // The exact structure depends on how respond_to transpiles
      expect(result.json || result.redirect).toBeDefined();
    });
  });

  describe('Path Helpers', () => {
    it('notes_path returns correct path', () => {
      expect(String(notes_path())).toBe('/notes');
    });

    it('note_path returns correct path with id', async () => {
      const note = await Note.create({
        title: 'Path Test Note',
        body: 'Testing path helper.'
      });
      expect(String(note_path(note))).toBe(`/notes/${note.id}`);
    });

    it('controller redirect uses path helpers', async () => {
      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {},
        request: { headers: { accept: 'text/html' } }
      };

      const params = {
        title: 'Redirect Test Note',
        body: 'Testing redirect path.'
      };

      const result = await NotesController.create(context, params);

      expect(result.redirect).toBeDefined();

      const notes = await Note.all();
      const createdNote = notes[0];
      expect(String(result.redirect)).toBe(String(note_path(createdNote)));
    });

    it('path helpers should not double paths', () => {
      const path = String(notes_path());
      expect(path).not.toContain('/notes/notes');
    });
  });

  describe('Query Interface', () => {
    beforeEach(async () => {
      await Note.create({ title: 'Alpha', body: 'First alphabetically.' });
      await Note.create({ title: 'Beta', body: 'Second alphabetically.' });
      await Note.create({ title: 'Gamma', body: 'Third alphabetically.' });
    });

    it('where filters by attributes', async () => {
      const results = await Note.where({ title: 'Beta' });
      expect(results.length).toBe(1);
      expect(results[0].title).toBe('Beta');
    });

    it('order sorts results', async () => {
      const results = await Note.order({ title: 'desc' });
      expect(results[0].title).toBe('Gamma');
      expect(results[2].title).toBe('Alpha');
    });

    it('limit restricts result count', async () => {
      const results = await Note.limit(2);
      expect(results.length).toBe(2);
    });

    it('first returns single record', async () => {
      const first = await Note.first();
      expect(first).toBeDefined();
      expect(first.title).toBe('Alpha');
    });

    it('count returns record count', async () => {
      const count = await Note.count();
      expect(count).toBe(3);
    });
  });
});
