# Build stage - compile the static site
FROM ruby:3.4-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    nodejs \
    npm \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the entire repo (needed because docs/Gemfile references ruby2js via path: "../")
COPY . .

# Install Ruby dependencies for the main gem
RUN bundle install

# Install docs dependencies
WORKDIR /app/docs
RUN bundle install
RUN yarn install

# Build the demo assets and static site
RUN bundle exec rake
RUN bundle exec rake deploy

# Production stage - serve static files with nginx
FROM nginx:alpine

# Copy the built static files
COPY --from=builder /app/docs/output /usr/share/nginx/html

# Copy custom nginx config for clean URLs and SPA-like routing
COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
    listen 80;
    listen [::]:80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Enable gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;

    # Clean URLs - serve index.html from directories
    location / {
        try_files $uri $uri/ $uri/index.html =404;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Custom error page
    error_page 404 /404.html;
}
EOF

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
