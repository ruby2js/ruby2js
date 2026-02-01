import { describe, it, expect, beforeEach } from 'vitest';

// Initialize Active Storage before tests
import { initActiveStorage, purgeActiveStorage } from 'juntos:active-storage';

beforeEach(async () => {
  await initActiveStorage();
  await purgeActiveStorage();
});

describe('Clip Model', () => {
  it('creates a clip with valid attributes', async () => {
    const { Clip } = await import('../app/models/index.js');

    const clip = await Clip.create({
      name: 'Test Recording',
      transcript: 'Hello, this is a test.',
      duration: 5.5
    });

    expect(clip.id).toBeDefined();
    expect(clip.name).toBe('Test Recording');
    expect(clip.transcript).toBe('Hello, this is a test.');
    expect(clip.duration).toBe(5.5);
  });

  it('validates name presence', async () => {
    const { Clip } = await import('../app/models/index.js');

    const clip = new Clip({ name: '', transcript: 'Some text' });
    const saved = await clip.save();

    expect(saved).toBe(false);
    expect(clip.errors.name).toBeDefined();
  });

  it('allows clip without transcript', async () => {
    const { Clip } = await import('../app/models/index.js');

    const clip = await Clip.create({
      name: 'No transcript clip'
    });

    expect(clip.id).toBeDefined();
    expect(clip.transcript).toBeUndefined();
  });
});

describe('Clip Active Storage', () => {
  it('attaches audio to a clip', async () => {
    const { Clip } = await import('../app/models/index.js');

    const clip = await Clip.create({
      name: 'Audio Test',
      duration: 3.0
    });

    // Create a test audio blob
    const audioData = new Uint8Array([0, 1, 2, 3, 4, 5]);
    const audioBlob = new Blob([audioData], { type: 'audio/webm' });

    // Attach the audio
    await clip.audio.attach(audioBlob, {
      filename: 'test.webm',
      content_type: 'audio/webm'
    });

    // Verify attachment
    expect(await clip.audio.attached()).toBe(true);
    expect(await clip.audio.filename()).toBe('test.webm');
    expect(await clip.audio.contentType()).toBe('audio/webm');
    expect(await clip.audio.byteSize()).toBe(6);
  });

  it('downloads attached audio', async () => {
    const { Clip } = await import('../app/models/index.js');

    const clip = await Clip.create({ name: 'Download Test' });

    const originalData = new Uint8Array([10, 20, 30, 40, 50]);
    const audioBlob = new Blob([originalData], { type: 'audio/webm' });

    await clip.audio.attach(audioBlob);

    // Download and verify
    const downloaded = await clip.audio.download();
    expect(downloaded).toBeDefined();

    const downloadedArray = new Uint8Array(await downloaded.arrayBuffer());
    expect(downloadedArray.length).toBe(5);
    expect(downloadedArray[0]).toBe(10);
  });

  it('purges audio attachment', async () => {
    const { Clip } = await import('../app/models/index.js');

    const clip = await Clip.create({ name: 'Purge Test' });

    const audioBlob = new Blob([1, 2, 3], { type: 'audio/webm' });
    await clip.audio.attach(audioBlob);

    expect(await clip.audio.attached()).toBe(true);

    // Purge the attachment
    await clip.audio.purge();

    expect(await clip.audio.attached()).toBe(false);
  });

  it('replaces existing attachment', async () => {
    const { Clip } = await import('../app/models/index.js');

    const clip = await Clip.create({ name: 'Replace Test' });

    // Attach first audio
    const audio1 = new Blob([1, 1, 1], { type: 'audio/webm' });
    await clip.audio.attach(audio1, { filename: 'first.webm' });

    expect(await clip.audio.filename()).toBe('first.webm');

    // Attach second audio (should replace first)
    const audio2 = new Blob([2, 2, 2, 2], { type: 'audio/mp4' });
    await clip.audio.attach(audio2, { filename: 'second.m4a' });

    expect(await clip.audio.filename()).toBe('second.m4a');
    expect(await clip.audio.byteSize()).toBe(4);
  });
});

describe('ClipsController', () => {
  it('index action returns list', async () => {
    const { Clip } = await import('../app/models/index.js');
    const { ClipsController } = await import('../app/controllers/clips_controller.js');

    await Clip.create({ name: 'Test Clip', transcript: 'Test content' });

    const context = {
      params: {},
      flash: { get: () => '', consumeNotice: () => ({ present: false }), consumeAlert: () => '' },
      contentFor: {}
    };

    const html = await ClipsController.index(context);
    expect(html).toContain('Dictaphone');
  });

  it('create action adds a new clip', async () => {
    const { Clip } = await import('../app/models/index.js');
    const { ClipsController } = await import('../app/controllers/clips_controller.js');

    const context = {
      params: {},
      flash: { set: () => {} },
      contentFor: {},
      request: { headers: { get: () => 'text/html' } }
    };

    const params = {
      name: 'New Recording',
      transcript: 'This is the transcript.',
      duration: 10.0
    };

    const result = await ClipsController.create(context, params);

    expect(result.redirect).toBeDefined();

    const clips = await Clip.all();
    expect(clips.length).toBe(1);
    expect(clips[0].name).toBe('New Recording');
  });
});
