# Ruby2JS Chat Demo
#
# Demonstrates real-time Turbo Streams broadcasting with WebSockets.
# Uses Ruby transpilation (not WASM-based selfhost) so Node 20 is sufficient.
#
# Build and run:
#   docker build -t ruby2js-chat .
#   docker run -p 3000:3000 ruby2js-chat
#
# Build with specific database/target:
#   docker build --build-arg DATABASE=dexie -t ruby2js-chat .
#   docker build --build-arg DATABASE=sqlite --build-arg TARGET=node -t ruby2js-chat .

FROM ruby

# Install Node.js (Trixie includes Node 20) and git
RUN apt-get update && apt-get install -y nodejs npm git && rm -rf /var/lib/apt/lists/*

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

# Run migrations (creates tables in database)
RUN bin/juntos migrate -d ${DATABASE} -t ${TARGET}

EXPOSE 3000

# Run server with specified database
CMD ["bin/juntos", "server"]
