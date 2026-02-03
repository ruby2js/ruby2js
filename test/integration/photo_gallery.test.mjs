// Integration tests for the photo gallery demo
// Tests CRUD operations, validations, and controller actions
// Uses better-sqlite3 with :memory: for fast, isolated tests

import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIST_DIR = join(__dirname, 'workspace/photo_gallery/dist');

// Dynamic imports - loaded once in beforeAll
let Photo;
let PhotosController;
let Application, initDatabase, migrations, modelRegistry;

// Sample base64 image data (tiny 1x1 red PNG)
const SAMPLE_IMAGE_DATA = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==';

describe('Photo Gallery Integration Tests', () => {
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
    Photo = models.Photo;

    // Import controllers
    const photosCtrl = await import(join(DIST_DIR, 'app/controllers/photos_controller.js'));
    PhotosController = photosCtrl.PhotosController;

    // Configure Application with migrations
    Application.configure({ migrations });
    Application.registerModels({ Photo });

    // Register models with adapter's registry
    modelRegistry.Photo = Photo;
  });

  beforeEach(async () => {
    // Initialize fresh in-memory database for each test
    await initDatabase({ database: ':memory:' });

    // Get the adapter module for runMigrations
    const adapter = await import(join(DIST_DIR, 'lib/active_record.mjs'));

    // Run migrations using Application
    await Application.runMigrations(adapter);
  });

  describe('Photo Model', () => {
    it('creates a photo with valid attributes', async () => {
      const photo = await Photo.create({
        client_id: 'test-uuid-123',
        image_data: SAMPLE_IMAGE_DATA,
        caption: 'Test photo',
        taken_at: new Date().toISOString()
      });

      expect(photo.id).toBeDefined();
      expect(photo.client_id).toBe('test-uuid-123');
      expect(photo.image_data).toBe(SAMPLE_IMAGE_DATA);
      expect(photo.caption).toBe('Test photo');
      expect(photo.id).toBeGreaterThan(0);
    });

    it('validates image_data presence', async () => {
      const photo = new Photo({
        client_id: 'test-uuid',
        image_data: '',
        caption: 'No image'
      });
      const saved = await photo.save();

      expect(saved).toBe(false);
      expect(photo.errors.image_data).toBeDefined();
    });

    it('creates photo without caption (optional)', async () => {
      const photo = await Photo.create({
        client_id: 'test-uuid-456',
        image_data: SAMPLE_IMAGE_DATA,
        taken_at: new Date().toISOString()
      });

      expect(photo.id).toBeDefined();
      expect(photo.caption).toBeFalsy();
    });

    it('finds photo by id', async () => {
      const created = await Photo.create({
        client_id: 'find-me-uuid',
        image_data: SAMPLE_IMAGE_DATA,
        caption: 'Find this photo'
      });

      const found = await Photo.find(created.id);
      expect(found.caption).toBe('Find this photo');
      expect(found.client_id).toBe('find-me-uuid');
    });

    it('lists all photos', async () => {
      await Photo.create({ client_id: 'uuid-1', image_data: SAMPLE_IMAGE_DATA });
      await Photo.create({ client_id: 'uuid-2', image_data: SAMPLE_IMAGE_DATA });
      await Photo.create({ client_id: 'uuid-3', image_data: SAMPLE_IMAGE_DATA });

      const photos = await Photo.all();
      expect(photos.length).toBe(3);
    });

    it('updates a photo', async () => {
      const photo = await Photo.create({
        client_id: 'update-uuid',
        image_data: SAMPLE_IMAGE_DATA,
        caption: 'Original caption'
      });

      await photo.update({ caption: 'Updated caption' });

      const reloaded = await Photo.find(photo.id);
      expect(reloaded.caption).toBe('Updated caption');
    });

    it('destroys a photo', async () => {
      const photo = await Photo.create({
        client_id: 'delete-uuid',
        image_data: SAMPLE_IMAGE_DATA
      });
      const id = photo.id;

      await photo.destroy();

      const found = await Photo.findBy({ id });
      expect(found).toBeNull();
    });
  });

  describe('PhotosController', () => {
    it('index action returns photo gallery', async () => {
      await Photo.create({
        client_id: 'gallery-uuid',
        image_data: SAMPLE_IMAGE_DATA,
        caption: 'Gallery photo',
        taken_at: new Date().toISOString()
      });

      const context = {
        params: {},
        flash: { get: () => '', consumeNotice: () => '', consumeAlert: () => '' },
        contentFor: {}
      };

      const html = await PhotosController.index(context);
      expect(html).toContain('Photo Gallery');
      expect(html).toContain('Gallery photo');
    });

    it('create action adds a new photo', async () => {
      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {},
        request: { headers: { accept: 'text/html' } }
      };

      const params = {
        photo: {
          image_data: SAMPLE_IMAGE_DATA,
          caption: 'Controller photo'
        }
      };

      await PhotosController.create(context, params);

      const photos = await Photo.all();
      expect(photos.length).toBe(1);
      expect(photos[0].caption).toBe('Controller photo');
      // Controller should set client_id and taken_at
      expect(photos[0].client_id).toBeDefined();
    });

    it('index shows empty state message when no photos', async () => {
      const context = {
        params: {},
        flash: { get: () => '', consumeNotice: () => '', consumeAlert: () => '' },
        contentFor: {}
      };

      const html = await PhotosController.index(context);
      expect(html).toContain('No photos yet');
    });
  });

  describe('Query Interface', () => {
    beforeEach(async () => {
      await Photo.create({
        client_id: 'uuid-a',
        image_data: SAMPLE_IMAGE_DATA,
        caption: 'Alpha',
        taken_at: '2024-01-01T10:00:00Z'
      });
      await Photo.create({
        client_id: 'uuid-b',
        image_data: SAMPLE_IMAGE_DATA,
        caption: 'Beta',
        taken_at: '2024-01-02T10:00:00Z'
      });
      await Photo.create({
        client_id: 'uuid-c',
        image_data: SAMPLE_IMAGE_DATA,
        caption: 'Gamma',
        taken_at: '2024-01-03T10:00:00Z'
      });
    });

    it('where filters by attributes', async () => {
      const results = await Photo.where({ caption: 'Beta' });
      expect(results.length).toBe(1);
      expect(results[0].caption).toBe('Beta');
    });

    it('order sorts results', async () => {
      const results = await Photo.order({ caption: 'desc' });
      expect(results[0].caption).toBe('Gamma');
      expect(results[2].caption).toBe('Alpha');
    });

    it('limit restricts result count', async () => {
      const results = await Photo.limit(2);
      expect(results.length).toBe(2);
    });

    it('first returns single record', async () => {
      const first = await Photo.first();
      expect(first).toBeDefined();
    });

    it('count returns record count', async () => {
      const count = await Photo.count();
      expect(count).toBe(3);
    });

    it('findBy returns matching record', async () => {
      const photo = await Photo.findBy({ client_id: 'uuid-b' });
      expect(photo.caption).toBe('Beta');
    });
  });

  describe('Path Helpers', () => {
    let photos_path;

    beforeAll(async () => {
      const paths = await import(join(DIST_DIR, 'config/paths.js'));
      photos_path = paths.photos_path;
    });

    it('photos_path returns correct path', () => {
      // Use String() since path helpers return objects with toString() methods
      expect(String(photos_path())).toBe('/photos');
    });

    it('path helpers should not double the base path', () => {
      const path = String(photos_path());
      expect(path).not.toContain('/photos/photos');
    });
  });
});
