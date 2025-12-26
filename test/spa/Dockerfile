# Stage 1: Build the SPA using Rails
FROM ruby:3.4 AS builder

# Install Node.js for asset pipeline
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs

# Copy the ruby2js gem first (from build context which is ruby2js repo root)
COPY . /ruby2js

WORKDIR /app

# Create a new Rails app
RUN gem install rails && \
    rails new blog --skip-git --skip-docker

WORKDIR /app/blog

# Add ruby2js gem with path reference
RUN echo "gem 'ruby2js', path: '/ruby2js', require: ['ruby2js', 'ruby2js/spa']" >> Gemfile && \
    bundle install

# Generate scaffold and migrate
RUN rails generate scaffold Article title:string body:text && \
    rails db:migrate

# Install the SPA generator
RUN rails generate ruby2js:spa:install --name blog

# Build the SPA
RUN rails ruby2js:spa:build

# Build the fixed selfhost bundle and filters (these are excluded from .dockerignore)
# Note: erb_compiler.js is manually maintained, not transpiled
WORKDIR /ruby2js/demo/selfhost
RUN bundle install && \
    mkdir -p filters/rails && \
    bundle exec ruby scripts/transpile_bundle.rb > ruby2js.js && \
    bundle exec ruby scripts/transpile_filter.rb ../../lib/ruby2js/filter/rails/helpers.rb > filters/rails/helpers.js

# Stage 2: Run the SPA with Node only (no Ruby runtime)
FROM node:22-slim

WORKDIR /spa

# Copy only the built SPA from stage 1
COPY --from=builder /app/blog/public/spa/blog /spa

# Copy fixed ruby2js files from the repo
COPY --from=builder /ruby2js/demo/selfhost/ruby2js.js /ruby2js-fixes/ruby2js.js
COPY --from=builder /ruby2js/demo/selfhost/lib/erb_compiler.js /ruby2js-fixes/erb_compiler.js
COPY --from=builder /ruby2js/demo/selfhost/filters/rails/helpers.js /ruby2js-fixes/helpers.js

# Install npm dependencies
RUN npm install

# Apply fixes to node_modules
RUN cp /ruby2js-fixes/ruby2js.js node_modules/ruby2js/ruby2js.js && \
    cp /ruby2js-fixes/erb_compiler.js node_modules/ruby2js/lib/erb_compiler.js && \
    cp /ruby2js-fixes/helpers.js node_modules/ruby2js/filters/rails/helpers.js

# Build the SPA
RUN npm run build

# Create stub seeds.js if missing
RUN mkdir -p dist/db && \
    echo 'export class Seeds { static run() {} }' > dist/db/seeds.js

# Expose port
EXPOSE 3000

# Start the server
CMD ["npx", "serve", "-p", "3000"]
