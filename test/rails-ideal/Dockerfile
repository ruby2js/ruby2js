# Ideal developer experience: Node-only, download and run
#
# This tests the published tarball workflow:
#   curl -L https://www.ruby2js.com/demo/ruby2js-on-rails.tar.gz | tar xz
#   cd ruby2js-on-rails
#   npm install
#   bin/dev
#
# No Ruby required - everything runs in JavaScript.

FROM node:22-slim

WORKDIR /app

# Download and extract the published demo
RUN apt-get update && apt-get install -y curl && \
    curl -L https://www.ruby2js.com/demo/ruby2js-on-rails.tar.gz | tar xz && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app/ruby2js-on-rails

# Install dependencies
RUN npm install

# Expose port
EXPOSE 3000

# Start the development server
CMD ["bin/dev"]
