# Ruby2JS Chat Demo
#
# Demonstrates real-time Turbo Streams broadcasting with WebSockets.
#
# Build and run:
#   docker build -t ruby2js-chat .
#   docker run -p 3000:3000 ruby2js-chat
#
# Build with specific database/target:
#   docker build --build-arg DATABASE=dexie -t ruby2js-chat .
#   docker build --build-arg DATABASE=sqlite --build-arg TARGET=node -t ruby2js-chat .

FROM ruby

# Install Node.js 24 (LTS) from NodeSource and git
RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs git && \
    rm -rf /var/lib/apt/lists/*

# Install Rails
RUN gem install rails

WORKDIR /app

# Copy and run the chat creation script
COPY create-chat .
RUN chmod +x create-chat && ./create-chat chat

WORKDIR /app/chat

# Build args for Juntos
ARG DATABASE=sqlite
ARG TARGET=node
ARG RAILS_ENV=production

ENV RAILS_ENV=${RAILS_ENV}
ENV JUNTOS_DATABASE=${DATABASE}
ENV JUNTOS_TARGET=${TARGET}

# Build with specified database and target
RUN bin/juntos build -d ${DATABASE} -t ${TARGET}

# Run migrations (skip for browser targets - they migrate client-side)
RUN if [ "${TARGET}" != "browser" ]; then bin/juntos db prepare -d ${DATABASE} -t ${TARGET}; fi

EXPOSE 3000

# Run server with specified database
CMD ["bin/juntos", "server"]
