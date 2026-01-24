# Ruby2JS Blog Demo
#
# Demonstrates running a Rails-generated blog with Juntos.
#
# Build and run (default: browser with Dexie/IndexedDB):
#   docker build -t ruby2js-blog .
#   docker run -p 3000:3000 ruby2js-blog
#
# Build with specific database/target:
#   docker build --build-arg NPM_INSTALL=dexie -t ruby2js-blog .
#   docker build --build-arg DATABASE=sqlite --build-arg TARGET=node --build-arg NPM_INSTALL=better-sqlite3 -t ruby2js-blog .
#   docker build --build-arg DATABASE=turso --build-arg TARGET=vercel -t ruby2js-blog .
#
# For CI testing with local artifacts, use the integration test infrastructure
# (test/integration/setup.mjs) instead of this Dockerfile.

FROM ruby

# Install Node.js 24 (LTS) from NodeSource and git
RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs git && \
    rm -rf /var/lib/apt/lists/*

# Install Rails
RUN gem install rails

WORKDIR /app

# Copy and run the blog creation script
COPY create-blog .
RUN chmod +x create-blog && ./create-blog blog

WORKDIR /app/blog

# Build args for Juntos
ARG DATABASE=dexie
ARG TARGET=browser
ARG RAILS_ENV=production
ARG NPM_INSTALL=""

ENV RAILS_ENV=${RAILS_ENV}
ENV JUNTOS_DATABASE=${DATABASE}
ENV JUNTOS_TARGET=${TARGET}

# Install database adapter package if specified
RUN if [ -n "${NPM_INSTALL}" ]; then npm install ${NPM_INSTALL}; fi

# Build with specified database and target
RUN bin/juntos build -d ${DATABASE} -t ${TARGET} --verbose

# Run migrations (skip for browser targets - they migrate client-side)
RUN if [ "${TARGET}" != "browser" ]; then bin/juntos db prepare -d ${DATABASE} -t ${TARGET}; fi

EXPOSE 3000

# Run server with specified database
CMD ["bin/juntos", "server"]
