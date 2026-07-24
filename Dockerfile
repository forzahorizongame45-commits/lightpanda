# syntax=docker/dockerfile:1
#
# Lightpanda MCP server -- production image for Render.
#
# Base: debian:bookworm-slim (glibc). Lightpanda's Linux release binaries
# are linked against glibc, not musl -- an Alpine base will fail at
# runtime with "cannot execute: required file not found". Verified against
# the actual nightly binary before shipping this file.

FROM debian:bookworm-slim

# Only what's needed to fetch the binary and run it -- ca-certificates for
# TLS, curl for the one-time download. No compilers, no build toolchain,
# nothing that isn't needed at runtime.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Pinned via build arg so a rebuild is reproducible against a known URL;
# Lightpanda currently ships only a rolling "nightly" tag (no versioned
# releases as of this writing), so true immutability requires vendoring
# the binary yourself -- see the README note on this tradeoff.
ARG LIGHTPANDA_URL=https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux

RUN curl -fsSL -o /usr/local/bin/lightpanda "$LIGHTPANDA_URL" \
    && chmod 755 /usr/local/bin/lightpanda \
    && /usr/local/bin/lightpanda version

# Run as a dedicated non-root user -- never as root in production.
RUN groupadd --system lightpanda \
    && useradd --system --gid lightpanda --home-dir /home/lightpanda --create-home lightpanda

COPY --chown=lightpanda:lightpanda start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

USER lightpanda
WORKDIR /home/lightpanda

# Disabled by default -- see .env.example to re-enable if you want
# Lightpanda's own usage telemetry.
ENV LIGHTPANDA_DISABLE_TELEMETRY=true

# Informational only (Render ignores this and injects $PORT at runtime);
# keeps `docker run` locally consistent with Render's default.
EXPOSE 10000

ENTRYPOINT ["/usr/local/bin/start.sh"]
