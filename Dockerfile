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

# Now copy the rest of the source code
WORKDIR /app
COPY . .

# Install docs bundle (needs full ruby2js source for path: "../")
WORKDIR /app/docs
RUN bundle install

# Build the demo assets and static site
# The esbuild ruby2js plugin runs `bundle exec ruby2js`
ENV BRIDGETOWN_ENV=production
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

    # Add trailing slash to directories (needed for ES module relative imports)
    # Without this, /demo/selfhost serves index.html but browser resolves
    # ./dist/runtime.mjs relative to /demo/ instead of /demo/selfhost/
    # But first check if a .html file exists (e.g., /docs -> docs.html)
    location ~ ^([^.]*[^/])$ {
        if (-f $document_root$uri.html) {
            rewrite ^(.*)$ $1.html last;
        }
        if (-d $document_root$uri) {
            return 301 $scheme://$http_host$uri/$is_args$args;
        }
        try_files $uri $uri.html /index.html;
    }

    # Clean URLs - serve index.html from directories, or .html files
    location / {
        try_files $uri $uri/index.html $uri.html /index.html;
    }

    # Cache static assets (including ES modules and WebAssembly)
    location ~* \.(js|mjs|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|wasm)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Custom error page
    error_page 404 /404.html;
}
EOF

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
