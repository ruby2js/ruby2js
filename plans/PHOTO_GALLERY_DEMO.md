# Photo Gallery Demo - Capacitor Native Camera

A focused demo showcasing Capacitor's native camera integration with Juntos.

## Overview

| Demo | Pattern | What It Shows |
|------|---------|---------------|
| Blog | CRUD | Table stakes, Rails conventions |
| Chat | Real-time | Turbo Streams, WebSockets |
| **Photo Gallery** | Native API | Capacitor camera, binary storage |

### The Story

> Access native device capabilities from Ruby. Take photos with the device camera, store them locally, display in a gallery. Same code runs on iOS and Android.

## Architecture

```
┌─────────────────────────────────────────┐
│           Capacitor App                  │
│  ┌─────────────────────────────────────┐│
│  │  Ruby Stimulus Controller           ││
│  │  ├── takePhoto() → Camera.getPhoto()││
│  │  └── Stores base64 in IndexedDB     ││
│  └─────────────────────────────────────┘│
│                    ↓                     │
│  ┌─────────────────────────────────────┐│
│  │  Dexie (IndexedDB)                  ││
│  │  └── photos: id, image_data, caption││
│  └─────────────────────────────────────┘│
└─────────────────────────────────────────┘
```

## Data Model

### Photo

Simple, append-only. No updates, no deletes.

```ruby
class Photo < ApplicationRecord
  attribute :client_id, :string      # UUID (for future sync)
  attribute :image_data, :text       # Base64 encoded image
  attribute :caption, :string
  attribute :taken_at, :datetime

  validates :image_data, presence: true
  validates :taken_at, presence: true

  before_create do
    self.client_id ||= SecureRandom.uuid
    self.taken_at ||= Time.current
  end
end
```

## Implementation

### Stimulus Controller (Ruby)

```ruby
class CameraController < Stimulus::Controller
  targets [:imageData, :preview, :captionInput]

  def takePhoto
    # Call Capacitor Camera plugin
    result = await Camera.getPhoto(
      resultType: CameraResultType::Base64,
      source: CameraSource::Camera,
      quality: 80
    )

    # Store in hidden field
    imageDataTarget.value = result.base64String

    # Show preview
    previewTarget.src = "data:image/jpeg;base64,#{result.base64String}"
    previewTarget.classList.remove('hidden')

    # Focus caption input
    captionInputTarget.focus
  end

  def chooseFromGallery
    result = await Camera.getPhoto(
      resultType: CameraResultType::Base64,
      source: CameraSource::Photos,
      quality: 80
    )

    imageDataTarget.value = result.base64String
    previewTarget.src = "data:image/jpeg;base64,#{result.base64String}"
    previewTarget.classList.remove('hidden')
  end
end
```

### View (ERB)

```erb
<%# app/views/photos/index.html.erb %>
<div data-controller="camera">
  <h1>Photo Gallery</h1>

  <!-- Capture buttons -->
  <div class="actions">
    <button data-action="click->camera#takePhoto">
      Take Photo
    </button>
    <button data-action="click->camera#chooseFromGallery">
      Choose from Gallery
    </button>
  </div>

  <!-- New photo form -->
  <%= form_with model: Photo.new, data: { action: "turbo:submit-end->camera#reset" } do |f| %>
    <%= f.hidden_field :image_data, data: { camera_target: "imageData" } %>

    <img data-camera-target="preview" class="hidden preview" />

    <%= f.text_field :caption,
        placeholder: "Add a caption...",
        data: { camera_target: "captionInput" } %>

    <%= f.submit "Save" %>
  <% end %>

  <!-- Gallery grid -->
  <div id="photos" class="gallery">
    <%= render @photos %>
  </div>
</div>
```

```erb
<%# app/views/photos/_photo.html.erb %>
<div id="<%= dom_id(photo) %>" class="photo-card">
  <img src="data:image/jpeg;base64,<%= photo.image_data %>" />
  <p><%= photo.caption %></p>
  <time><%= photo.taken_at.strftime("%b %d, %Y") %></time>
</div>
```

### Controller

```ruby
class PhotosController < ApplicationController
  def index
    @photos = Photo.order(taken_at: :desc)
  end

  def create
    @photo = Photo.new(photo_params)

    if @photo.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to photos_path }
      end
    end
  end

  private

  def photo_params
    params.require(:photo).permit(:image_data, :caption)
  end
end
```

### Turbo Stream Response

```erb
<%# app/views/photos/create.turbo_stream.erb %>
<%= turbo_stream.prepend "photos", @photo %>
```

## Capacitor Setup

### Dependencies

```json
{
  "dependencies": {
    "@capacitor/core": "^5.0.0",
    "@capacitor/camera": "^5.0.0"
  }
}
```

### Capacitor Config

```typescript
// capacitor.config.ts
import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.photogallery',
  appName: 'Photo Gallery',
  webDir: 'dist',
  plugins: {
    Camera: {
      // iOS: Add to Info.plist automatically
      // Android: Add to AndroidManifest.xml automatically
    }
  }
};

export default config;
```

### Platform Permissions

**iOS (Info.plist)** - Added automatically by Capacitor:
```xml
<key>NSCameraUsageDescription</key>
<string>Take photos for your gallery</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Select photos from your library</string>
```

**Android (AndroidManifest.xml)** - Added automatically by Capacitor:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

## Build & Run

```bash
# Create the app
curl -sL .../create-photo-gallery | bash -s photo_gallery
cd photo_gallery

# Build for Capacitor
bin/juntos build -t capacitor -d dexie

# Add platforms
cd dist
npm install
npx cap add ios      # Requires Xcode
npx cap add android  # Requires Android Studio

# Run on device
npx cap run ios      # Opens Xcode, run on device/simulator
npx cap run android  # Opens Android Studio, run on device/emulator
```

## Demo Flow

1. **Launch app** on phone
2. **Tap "Take Photo"** → Native camera opens
3. **Take picture** → Returns to app with preview
4. **Add caption** → Optional
5. **Tap "Save"** → Stored in IndexedDB
6. **See gallery** → Photo appears at top
7. **Repeat** → Build up a gallery

## What This Proves

| Capability | Demonstrated |
|------------|--------------|
| Capacitor plugin integration | Camera API |
| Ruby calling native APIs | `Camera.getPhoto()` in Stimulus |
| Binary data in IndexedDB | Base64 image storage |
| Turbo Streams on Capacitor | Real-time UI updates |
| Cross-platform | Same code on iOS + Android |

## What This Doesn't Do (Yet)

- No server sync (local only)
- No user authentication
- No delete functionality
- No image editing
- No sharing

These are intentionally deferred. This demo focuses on **native camera integration**.

## Future: Social Feed Integration

This demo becomes a building block:

```
Blog (text posts)
    +
Chat (real-time)
    +
Photo Gallery (images)
    =
Social Feed (combined, with sync)
```

The `Photo` model's `client_id` field enables future sync:

```ruby
# Future sync endpoint
def sync
  # Get new photos from server
  new_photos = fetch("/api/photos?since=#{last_sync_at}")
  new_photos.each { |p| Photo.create(p) }

  # Push local photos to server
  local_photos = Photo.where('created_at > ?', last_push_at)
  post("/api/photos", photos: local_photos)
end
```

No conflicts because:
- Append-only (no updates)
- No deletes
- `client_id` ensures uniqueness

## Files to Generate

```
photo_gallery/
├── app/
│   ├── models/
│   │   └── photo.rb
│   ├── controllers/
│   │   └── photos_controller.rb
│   ├── views/
│   │   └── photos/
│   │       ├── index.html.erb
│   │       ├── _photo.html.erb
│   │       └── create.turbo_stream.erb
│   └── javascript/
│       └── controllers/
│           └── camera_controller.rb
├── config/
│   ├── routes.rb
│   └── database.yml
├── db/
│   └── schema.rb
└── package.json
```

## Implementation Checklist

### Phase 1: Basic Gallery (Browser)

- [ ] Create Photo model
- [ ] Create PhotosController with index/create
- [ ] Create views (index, _photo partial, turbo_stream)
- [ ] Test in browser with file input fallback

### Phase 2: Capacitor Integration

- [ ] Add CameraController (Stimulus)
- [ ] Configure Capacitor camera plugin
- [ ] Test on iOS simulator
- [ ] Test on Android emulator

### Phase 3: Polish

- [ ] Add loading states
- [ ] Handle camera permission denial gracefully
- [ ] Add "Choose from Gallery" option
- [ ] Responsive grid layout

### Phase 4: Documentation

- [ ] Create docs/src/_docs/juntos/demos/photo-gallery.md
- [ ] Add to demos index
- [ ] Create test/photo_gallery/create-photo-gallery script

## Success Criteria

1. **Native camera works** - Tap button, camera opens, photo captured
2. **Photos persist** - Survive app restart (IndexedDB)
3. **Cross-platform** - Same code runs on iOS and Android
4. **Ruby throughout** - Model, controller, Stimulus all in Ruby
5. **Turbo integration** - New photos appear without page reload

## References

- [Capacitor Camera Plugin](https://capacitorjs.com/docs/apis/camera)
- [Dexie.js](https://dexie.org/) - IndexedDB wrapper
- [Blog Demo](../docs/src/_docs/juntos/demos/blog.md) - CRUD patterns
- [Chat Demo](../docs/src/_docs/juntos/demos/chat.md) - Real-time patterns
