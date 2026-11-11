# Number Guessing Game
FROM node:22-alpine

ENV NODE_ENV=production \
    PORT=3000 \
    DATA_DIR=/app/data

WORKDIR /app

# Non-root user with a FIXED uid/gid (1001) so the host dir /var/lib/app-data
RUN addgroup -S -g 1001 appuser && adduser -S -u 1001 -G appuser appuser

# Dependencies first so this layer is cached when only source code changes
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY healthcheck.js ./
COPY src ./src
RUN mkdir -p /app/data && chown appuser:appuser /app/data

# Build metadata shown in the page footer
ARG BUILD_NUMBER=dev
ARG GIT_COMMIT=local
ENV BUILD_NUMBER=$BUILD_NUMBER \
    GIT_COMMIT=$GIT_COMMIT
LABEL org.opencontainers.image.title="guessgame" \
      org.opencontainers.image.revision=$GIT_COMMIT \
      org.opencontainers.image.version=$BUILD_NUMBER

USER appuser
EXPOSE 3000
VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "healthcheck.js"]

CMD ["node", "src/server.js"]
