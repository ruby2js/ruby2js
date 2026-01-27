---
order: 665
title: Dictaphone Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

A voice recording app with AI transcription. Record audio clips, get automatic transcriptions via OpenAI Whisper, and store everything locally using Active Storage.

{% toc %}

## Create the App

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/dictaphone/create-dictaphone | bash -s dictaphone
cd dictaphone
```

This creates a Rails app with:

- **Clip model** — stores audio recordings with transcriptions
- **Active Storage** — manages audio file attachments
- **Dictaphone controller** — Stimulus controller written in Ruby
- **Whisper integration** — automatic transcription via OpenAI API
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

Open http://localhost:3000. Same app—but now Node.js serves requests, and audio files are stored on the local filesystem via Active Storage's disk adapter.

## Environment Variables

### OpenAI API Key (Required for Transcription)

Set your OpenAI API key to enable Whisper transcription:

```bash
export OPENAI_API_KEY=sk-...
```

Without this key, recordings will be saved but transcription will be skipped.

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

The dictaphone controller is written in Ruby. **Try it** — see how it transpiles:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["stimulus", "esm", "functions"]
}'></div>

```ruby
class DictaphoneController < Stimulus::Controller
  def startRecording
    stream = await navigator.mediaDevices.getUserMedia(audio: true)
    @mediaRecorder = MediaRecorder.new(stream)
    @chunks = []

    @mediaRecorder.ondataavailable = ->(e) { @chunks.push(e.data) }
    @mediaRecorder.onstop = -> { handleRecordingComplete() }
    @mediaRecorder.start()

    recordingTarget.classList.remove("hidden")
  end

  def stopRecording
    @mediaRecorder.stop()
    @mediaRecorder.stream.getTracks().each { |t| t.stop() }
  end

  def handleRecordingComplete
    blob = Blob.new(@chunks, type: "audio/webm")
    saveClip(blob)
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

  validates :audio, presence: true
end
```

## What This Demo Shows

### Audio Recording

- **MediaRecorder API** — captures audio from microphone
- **WebM format** — compressed audio for efficient storage
- **Chunk handling** — collects data as it streams

### Active Storage Integration

- **Browser** — IndexedDB adapter stores blobs locally
- **Node.js** — Disk adapter stores files on filesystem
- **Edge** — S3 adapter stores in cloud object storage
- **Same API** — `has_one_attached :audio` works everywhere

### AI Transcription

- **OpenAI Whisper** — speech-to-text via API
- **Audio preprocessing** — converts WebM to proper format
- **Async processing** — transcription runs after save

### Stimulus Controller

- **Written in Ruby** — transpiles to JavaScript
- **Async/await** — microphone access uses promises
- **State management** — tracks recording status, chunks

## What Works Differently

- **Browser audio** — uses MediaRecorder with WebM codec
- **Whisper API** — requires server-side call (not from browser)
- **Storage backend** — automatically selected based on target

## What Doesn't Work

- **Offline transcription** — requires OpenAI API (network)
- **Long recordings** — Whisper has a 25MB file limit
- **Real-time transcription** — currently processes after recording stops

## Next Steps

- Try the [Photo Gallery Demo](/docs/juntos/demos/photo-gallery) for camera integration
- Try the [Blog Demo](/docs/juntos/demos/blog) for CRUD patterns
- Read the [Architecture](/docs/juntos/architecture) to understand what gets generated
- Check [Deployment Guides](/docs/juntos/deploying/) for platform setup
