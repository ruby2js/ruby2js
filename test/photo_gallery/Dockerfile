# Ruby2JS Photo Gallery Demo
#
# Demonstrates camera integration with browser getUserMedia API.
# Uses Ruby transpilation (not WASM-based selfhost) so Node 20 is sufficient.
#
# Build and run:
#   docker build -t ruby2js-photo-gallery .
#   docker run -p 3000:3000 ruby2js-photo-gallery
#
# Build with specific database/target:
#   docker build --build-arg DATABASE=dexie -t ruby2js-photo-gallery .
#   docker build --build-arg DATABASE=sqlite --build-arg TARGET=node -t ruby2js-photo-gallery .

FROM ruby

# Install Node.js (Trixie includes Node 20) and git
RUN apt-get update && apt-get install -y nodejs npm git && rm -rf /var/lib/apt/lists/*

# Install Rails
RUN gem install rails

WORKDIR /app

# Copy and run the photo gallery creation script
COPY create-photo-gallery .
RUN chmod +x create-photo-gallery && ./create-photo-gallery photo_gallery

WORKDIR /app/photo_gallery

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
