# Ruby2JS Blog Demo
#
# Demonstrates running a Rails-generated blog with Juntos.
# Uses Ruby transpilation (not WASM-based selfhost) so Node 20 is sufficient.
#
# Build and run:
#   docker build -t ruby2js-blog .
#   docker run -p 3000:3000 ruby2js-blog
#
# Build with specific database/target:
#   docker build --build-arg DATABASE=dexie -t ruby2js-blog .
#   docker build --build-arg DATABASE=sqlite --build-arg TARGET=node -t ruby2js-blog .
#   docker build --build-arg DATABASE=turso --build-arg TARGET=vercel -t ruby2js-blog .

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

# Build args for Juntos
ARG DATABASE=sqlite
ARG TARGET=node
ARG RAILS_ENV=production

ENV RAILS_ENV=${RAILS_ENV}
ENV JUNTOS_DATABASE=${DATABASE}
ENV JUNTOS_TARGET=${TARGET}

# Build with specified database and target
RUN bin/juntos build -d ${DATABASE} -t ${TARGET}

EXPOSE 3000

# Run server with specified database
CMD ["bin/juntos", "server"]
