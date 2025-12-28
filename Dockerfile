# Build stage - compile the static site
FROM ruby:3.4-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    libyaml-dev \
    nodejs \
    npm \
    && npm install -g yarn \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy gemspec and Gemfiles first for better layer caching
COPY ruby2js.gemspec Gemfile Gemfile.lock ./
COPY lib/ruby2js/version.rb lib/ruby2js/version.rb
RUN bundle install

# Copy docs yarn dependencies and install
COPY docs/package.json docs/yarn.lock ./docs/
WORKDIR /app/docs
RUN yarn install

# Copy demo package files for better layer caching
# These npm installs happen before COPY . . so they're cached when source changes
WORKDIR /app
COPY demo/selfhost/package.json demo/selfhost/package-lock.json ./demo/selfhost/
WORKDIR /app/demo/selfhost
RUN npm install

WORKDIR /app
# Copy the full ruby2js-rails package (demo uses file: dependency which creates symlinks)
COPY packages/ruby2js-rails/ ./packages/ruby2js-rails/
WORKDIR /app/packages/ruby2js-rails
RUN npm install

WORKDIR /app
COPY demo/ruby2js-on-rails/package.json demo/ruby2js-on-rails/package-lock.json ./demo/ruby2js-on-rails/
WORKDIR /app/demo/ruby2js-on-rails
RUN npm install

# Now copy the rest of the source code (node_modules dirs already populated)
# Remove symlink created by file: dependency before COPY to avoid conflict
WORKDIR /app
RUN rm -rf demo/ruby2js-on-rails/node_modules/ruby2js-rails
COPY . .

# Install docs bundle (needs full ruby2js source for path: "../")
WORKDIR /app/docs
RUN bundle install

# Build the demo assets and static site
# The esbuild ruby2js plugin runs `bundle exec ruby2js`
WORKDIR /app/docs
ENV BRIDGETOWN_ENV=production
RUN bundle exec rake && bundle exec rake deploy

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

    # Include default MIME types and add extras for ES modules and WebAssembly
    include /etc/nginx/mime.types;
    types {
        application/javascript mjs;
        application/wasm wasm;
    }

    # Enable gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript application/wasm;

    # Upgrade insecure requests - fixes mixed content when behind HTTPS proxy
    add_header Content-Security-Policy "upgrade-insecure-requests" always;

    # Always revalidate - with HTTP/2 and 304 responses, overhead is negligible
    add_header Cache-Control "no-cache, must-revalidate" always;

    # Strip trailing slashes (per Bridgetown docs)
    # Use $scheme://$http_host to preserve the port in redirects
    rewrite ^(.+)/+$ $scheme://$http_host$1 permanent;

    # Clean URLs - serve index.html from directories, or .html files
    location / {
        try_files $uri $uri/index.html $uri.html /index.html;
    }

    # Custom error page
    error_page 404 /404.html;
}
EOF

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
