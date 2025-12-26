# Ideal SPA workflow: Generate offline SPA from Rails scaffold
#
# This tests the full workflow:
#   1. Create Rails app with scaffold
#   2. Install ruby2js SPA generator
#   3. Build SPA (generates package.json, Ruby source, config)
#   4. npm install && npm run build (transpiles to JS)
#   5. Serve static files (no Ruby runtime needed)
#
# Stage 1: Build the SPA using Rails
FROM ruby:3.4 AS builder

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs

WORKDIR /app

# Create Rails app with scaffold
RUN gem install rails && \
    rails new blog --skip-git --skip-docker

WORKDIR /app/blog

# Add ruby2js gem (from rubygems once published, or github for now)
RUN echo "gem 'ruby2js', github: 'ruby2js/ruby2js', require: ['ruby2js', 'ruby2js/spa']" >> Gemfile && \
    bundle install

# Generate scaffold
RUN rails generate scaffold Article title:string body:text && \
    rails db:migrate

# Install SPA generator and build
RUN rails generate ruby2js:spa:install --name blog && \
    rails ruby2js:spa:build

# Stage 2: Build and run with Node only (no Ruby)
FROM node:22-slim

WORKDIR /spa

# Copy the generated SPA
COPY --from=builder /app/blog/public/spa/blog /spa

# Install and build
RUN npm install && npm run build

# Create stub seeds.js (scaffolds don't have seeds)
RUN mkdir -p dist/db && \
    echo 'export class Seeds { static run() {} }' > dist/db/seeds.js

EXPOSE 3000

CMD ["npx", "serve", "-p", "3000"]
