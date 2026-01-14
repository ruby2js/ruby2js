# syntax=docker/dockerfile:1.4
# Dockerfile for serving static Juntos demos
# Multi-stage build with parallel demo builds
#
# Usage:
#   cd test
#   docker build -t ruby2js-demos .
#   docker run --rm -p 8080:80 ruby2js-demos
#
# BuildKit builds the demo stages in parallel since they only depend on `base`.

# =============================================================================
# Base stage: Common dependencies for all demos
# =============================================================================
FROM ruby AS base

# Install Node.js 24 and git
RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs git && \
    rm -rf /var/lib/apt/lists/*

# Install Rails
RUN gem install rails

WORKDIR /app

# =============================================================================
# Blog demo build stage
# =============================================================================
FROM base AS blog

COPY blog/create-blog .
RUN chmod +x create-blog && ./create-blog blog

WORKDIR /app/blog
RUN bin/juntos build -d dexie -t browser -v --sourcemap --base /blog/

# =============================================================================
# Chat demo build stage
# =============================================================================
FROM base AS chat

COPY chat/create-chat .
RUN chmod +x create-chat && ./create-chat chat

WORKDIR /app/chat
RUN bin/juntos build -d dexie -t browser -v --sourcemap --base /chat/

# =============================================================================
# Photo Gallery demo build stage
# =============================================================================
FROM base AS photo_gallery

COPY photo_gallery/create-photo-gallery .
RUN chmod +x create-photo-gallery && ./create-photo-gallery photo_gallery

WORKDIR /app/photo_gallery
RUN bin/juntos build -d dexie -t browser -v --sourcemap --base /photo-gallery/

# =============================================================================
# Workflow Builder demo build stage
# =============================================================================
FROM base AS workflow

COPY workflow/create-workflow .
RUN chmod +x create-workflow && ./create-workflow workflow_builder

WORKDIR /app/workflow_builder
RUN bin/juntos build -d dexie -t browser -v --sourcemap --base /workflow/

# =============================================================================
# Final stage: nginx serving all static demos
# =============================================================================
FROM nginx:alpine

# Copy built demos from each stage
COPY --from=blog /app/blog/dist /usr/share/nginx/html/blog
COPY --from=chat /app/chat/dist /usr/share/nginx/html/chat
COPY --from=photo_gallery /app/photo_gallery/dist /usr/share/nginx/html/photo-gallery
COPY --from=workflow /app/workflow_builder/dist /usr/share/nginx/html/workflow

# Create index page listing all demos
COPY <<'EOF' /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Ruby2JS Demos</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
      max-width: 800px;
      margin: 0 auto;
      padding: 2rem;
      line-height: 1.6;
    }
    h1 { color: #1a202c; }
    .demos {
      display: grid;
      gap: 1rem;
      margin-top: 2rem;
    }
    .demo {
      padding: 1.5rem;
      background: #f7fafc;
      border-radius: 8px;
      border: 1px solid #e2e8f0;
    }
    .demo h2 {
      margin: 0 0 0.5rem 0;
      font-size: 1.25rem;
    }
    .demo h2 a {
      color: #2563eb;
      text-decoration: none;
    }
    .demo h2 a:hover {
      text-decoration: underline;
    }
    .demo p {
      margin: 0;
      color: #4a5568;
    }
  </style>
</head>
<body>
  <h1>Ruby2JS Juntos Demos</h1>
  <p>Live demos of Rails applications running entirely in the browser using Ruby2JS and Dexie (IndexedDB).</p>

  <div class="demos">
    <div class="demo">
      <h2><a href="/blog/">Blog</a></h2>
      <p>CRUD operations, nested routes, validations. Articles with comments demonstrating model associations.</p>
    </div>
    <div class="demo">
      <h2><a href="/chat/">Chat</a></h2>
      <p>Real-time Turbo Streams, Stimulus controllers. Live messaging between browser tabs.</p>
    </div>
    <div class="demo">
      <h2><a href="/photo-gallery/">Photo Gallery</a></h2>
      <p>Camera integration via getUserMedia. Capture photos from webcam and save to IndexedDB.</p>
    </div>
    <div class="demo">
      <h2><a href="/workflow/">Workflow Builder</a></h2>
      <p>React Flow integration, real-time collaboration. Visual workflow editor with drag-and-drop nodes.</p>
    </div>
  </div>
</body>
</html>
EOF

# nginx config for SPA routing
COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
    listen 80;
    listen [::]:80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    include /etc/nginx/mime.types;
    types {
        application/javascript mjs;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript application/wasm;

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location /blog {
        try_files $uri $uri/ /blog/index.html;
    }

    location /chat {
        try_files $uri $uri/ /chat/index.html;
    }

    location /photo-gallery {
        try_files $uri $uri/ /photo-gallery/index.html;
    }

    location /workflow {
        try_files $uri $uri/ /workflow/index.html;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
