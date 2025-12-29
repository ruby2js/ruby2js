# Ruby2JS Blog Demo
#
# Demonstrates running a Rails-generated blog with Ruby2JS.
# Uses Ruby transpilation (not WASM-based selfhost) so Node 20 is sufficient.
#
# Build and run:
#   docker build -t ruby2js-blog .
#   docker run -p 3000:3000 ruby2js-blog

FROM ruby

# Install Node.js (Trixie includes Node 20) and git
RUN apt-get update && apt-get install -y nodejs npm git && rm -rf /var/lib/apt/lists/*

# Install Rails
RUN gem install rails

WORKDIR /app

# Copy and run the blog creation script
COPY create-blog .
RUN chmod +x create-blog && ./create-blog blog

WORKDIR /app/blog

# Install npm dependencies, build, and prepare for serving
RUN bundle exec ruby2js install
RUN bundle exec ruby2js build

EXPOSE 3000

CMD ["bundle", "exec", "ruby2js", "server"]
