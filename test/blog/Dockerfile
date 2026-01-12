# Ruby2JS Blog Demo
#
# Demonstrates running a Rails-generated blog with Juntos.
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
ARG DATABASE=sqlite
ARG TARGET=node
ARG RAILS_ENV=production

ENV RAILS_ENV=${RAILS_ENV}
ENV JUNTOS_DATABASE=${DATABASE}
ENV JUNTOS_TARGET=${TARGET}

# Build with specified database and target
RUN bin/juntos build -d ${DATABASE} -t ${TARGET} --verbose

# Run migrations (skip for browser targets - they migrate client-side)
RUN if [ "${TARGET}" != "browser" ]; then bin/juntos db prepare -d ${DATABASE} -t ${TARGET}; fi

EXPOSE 3000

# Run server with specified database
CMD ["bin/juntos", "server"]
