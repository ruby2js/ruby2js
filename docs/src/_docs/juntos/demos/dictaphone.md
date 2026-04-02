---
order: 665
title: Dictaphone Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

A voice recording app that demonstrates transparent RPC. The Stimulus controller calls `Clip.create()` and `clip.audio.attach()` directly — the same Ruby code works in the browser (IndexedDB) and on Node.js (SQLite via RPC). Audio transcription runs locally in the browser via Whisper (Transformers.js).

{% toc %}

## Create the App

[**Try it live**](https://ruby2js.github.io/ruby2js/dictaphone/) — no install required.

To run locally:

```bash
npx github:ruby2js/juntos --demo dictaphone
cd dictaphone
```

This creates a Rails app with:

- **Clip model** — stores audio recordings with transcriptions
- **Active Storage** — manages audio file attachments
- **Dictaphone controller** — Stimulus controller written in Ruby
- **Whisper integration** — local speech-to-text via Transformers.js
- **Tailwind CSS** — clean recording UI with waveform visualization

## Run with Rails

The demo includes a Stimulus controller written in Ruby (`app/javascript/controllers/dictaphone_controller.rb`). To transpile it automatically, install ruby2js:

```bash
bundle add ruby2js --github ruby2js/ruby2js --branch master
bin/rails generate ruby2js:install
RAILS_ENV=production bin/rails db:prepare
bin/rails server -e production
```

Open http://localhost:3000. Click "Start Recording" to begin capturing audio. Stop recording to save the clip and trigger transcription.

## Run in the Browser

Stop Rails. Run the same app in your browser:

```bash
bin/juntos dev -d dexie
```

Open http://localhost:3000. Same recording interface. Same transcription. But now:

- **No Ruby runtime** — the browser runs transpiled JavaScript
- **IndexedDB storage** — audio files persist in your browser via Active Storage's IndexedDB adapter
- **Hot reload** — edit a Ruby file, save, browser refreshes

### Microphone Permissions

The browser will request microphone access when you click "Start Recording". Grant permission to enable audio capture. Recordings are stored as WebM audio blobs in IndexedDB.

## Run on Node.js

```bash
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite
```

Open http://localhost:3000. Same app—but now Node.js serves requests, and audio files are stored on the local filesystem via Active Storage's disk adapter. The Stimulus controller's model operations (`Clip.create()`, `clip.audio.attach()`) are automatically routed through RPC to the server — no fetch calls or form submissions needed.

## Environment Variables

### S3 Storage (Edge Targets)

For edge deployments (Fly.io, Cloudflare Workers, Vercel Edge, Deno Deploy), configure S3-compatible storage:

```bash
export S3_BUCKET=my-bucket
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1
# For Cloudflare R2 or MinIO:
export AWS_ENDPOINT_URL=https://...
```

## The Code

The Stimulus controller imports a model and calls it directly. In the browser, this hits IndexedDB. On Node.js, the build automatically generates RPC so the same code calls the server:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["stimulus", "esm", "functions"]
}'></div>

```ruby
import ["Clip"], from: 'juntos:models'

class DictaphoneController < Stimulus::Controller
  async def save(event)
    event.preventDefault()
    return unless @audioBlob

    clip = await Clip.create(
      name: nameTarget.value || "Untitled Recording",
      transcript: transcriptTarget.value,
      duration: parseFloat(durationTarget.value)
    )

    extension = @audioBlob.type.include?('webm') ? 'webm' : 'm4a'
    await clip.audio.attach(@audioBlob,
      filename: "recording.#{extension}",
      content_type: @audioBlob.type
    )
  end
end
```

**Try it** — the model uses Active Storage:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

```ruby
class Clip < ApplicationRecord
  has_one_attached :audio

  validates :name, presence: true
  broadcasts_to -> { "clips" }, inserts_by: :prepend
end
```

## What This Demo Shows

### Transparent RPC

- **Direct model access** — `Clip.create()` in a Stimulus controller, no fetch or form submission
- **Automatic routing** — browser target uses IndexedDB, Node.js target uses RPC to the server
- **Build-time detection** — the build pipeline detects model imports and generates the RPC layer
- **Like React Server Functions** — but for Stimulus controllers and Ruby syntax

### Active Storage Integration

- **Browser** — IndexedDB adapter stores blobs locally
- **Node.js** — Disk adapter stores files on filesystem
- **Edge** — S3 adapter stores in cloud object storage
- **Same API** — `has_one_attached :audio` works everywhere

### AI Transcription

- **Local Whisper** — speech-to-text runs in the browser via Transformers.js
- **No API key needed** — the ~75MB model downloads on first use, then is cached
- **Progress indicator** — shows model download progress in the UI

### Audio Recording

- **MediaRecorder API** — captures audio from microphone
- **WebM format** — compressed audio for efficient storage
- **Waveform visualization** — real-time audio level display

## Next Steps

- Try the [Photo Gallery Demo](/docs/juntos/demos/photo-gallery) for camera integration
- Try the [Blog Demo](/docs/juntos/demos/blog) for CRUD patterns
- Read the [Architecture](/docs/juntos/architecture) to understand what gets generated
- Check [Deployment Guides](/docs/juntos/deploying/) for platform setup
