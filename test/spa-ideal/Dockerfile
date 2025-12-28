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

WORKDIR /app

# Create Rails app with scaffold and Tailwind CSS
RUN gem install rails && \
    rails new blog --skip-git --skip-docker --css tailwind

WORKDIR /app/blog

# Add ruby2js gem (from rubygems once published, or github for now)
RUN bundle add ruby2js --github ruby2js/ruby2js --require ruby2js/spa

# Generate scaffold
RUN rails generate scaffold Article title:string body:text && \
    rails db:migrate

# Set root route to articles#index (common for Rails demos)
RUN sed -i 's/# root "posts#index"/root "articles#index"/' config/routes.rb

# Install SPA generator and build
# Auto-detects: name=blog, scaffolds=Article, root from routes.rb
# Defaults: runtime=browser, database=dexie
RUN rails generate ruby2js:spa:install && \
    rails ruby2js:spa:build

# Stage 2: Build and run with Node only (no Ruby)
FROM node:22-slim

WORKDIR /spa

# Copy the generated SPA
COPY --from=builder /app/blog/public/spa/blog /spa

# Install and build
RUN npm install && npm run build

EXPOSE 3000

CMD ["npx", "serve", "-s", "-p", "3000"]
