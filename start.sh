#!/bin/sh
# Lightpanda MCP server entrypoint for Render.
#
# Binds Lightpanda's native HTTP MCP transport to $PORT, applies
# bot-protection / resource-limit flags from environment variables, and
# supervises the process: forwards signals for graceful shutdown, and
# restarts on crash with a bounded retry window (Lightpanda is Beta and
# can crash on a hostile page — one bad site should not take the whole
# service down).

set -eu

PORT="${PORT:-10000}"
LOG_LEVEL="${LOG_LEVEL:-warn}"
LOG_FORMAT="${LOG_FORMAT:-logfmt}"
V8_MAX_HEAP_MB="${V8_MAX_HEAP_MB:-400}"
HTTP_MAX_CONCURRENT="${HTTP_MAX_CONCURRENT:-5}"
HTTP_MAX_HOST_OPEN="${HTTP_MAX_HOST_OPEN:-2}"
OBEY_ROBOTS="${OBEY_ROBOTS:-true}"
BLOCK_PRIVATE_NETWORKS="${BLOCK_PRIVATE_NETWORKS:-true}"

# Optional bot-identity / proxy settings. Unset by default; set these in
# Render's environment variables (and Secret Files for the key) to enable.
HTTP_PROXY_URL="${HTTP_PROXY_URL:-}"
PROXY_BEARER_TOKEN="${PROXY_BEARER_TOKEN:-}"
WEB_BOT_AUTH_DOMAIN="${WEB_BOT_AUTH_DOMAIN:-}"
WEB_BOT_AUTH_KEY_FILE="${WEB_BOT_AUTH_KEY_FILE:-}"
WEB_BOT_AUTH_KEYID="${WEB_BOT_AUTH_KEYID:-}"
USER_AGENT_SUFFIX="${USER_AGENT_SUFFIX:-}"

set -- lightpanda mcp \
  --host 0.0.0.0 \
  --port "$PORT" \
  --log-level "$LOG_LEVEL" \
  --log-format "$LOG_FORMAT" \
  --v8-max-heap-mb "$V8_MAX_HEAP_MB" \
  --http-max-concurrent "$HTTP_MAX_CONCURRENT" \
  --http-max-host-open "$HTTP_MAX_HOST_OPEN"

[ "$OBEY_ROBOTS" = "true" ] && set -- "$@" --obey-robots
[ "$BLOCK_PRIVATE_NETWORKS" = "true" ] && set -- "$@" --block-private-networks

[ -n "$HTTP_PROXY_URL" ] && set -- "$@" --http-proxy "$HTTP_PROXY_URL"
[ -n "$PROXY_BEARER_TOKEN" ] && set -- "$@" --proxy-bearer-token "$PROXY_BEARER_TOKEN"
[ -n "$USER_AGENT_SUFFIX" ] && set -- "$@" --user-agent-suffix "$USER_AGENT_SUFFIX"

if [ -n "$WEB_BOT_AUTH_DOMAIN" ] && [ -n "$WEB_BOT_AUTH_KEY_FILE" ] && [ -n "$WEB_BOT_AUTH_KEYID" ]; then
  if [ -f "$WEB_BOT_AUTH_KEY_FILE" ]; then
    set -- "$@" \
      --web-bot-auth-domain "$WEB_BOT_AUTH_DOMAIN" \
      --web-bot-auth-key-file "$WEB_BOT_AUTH_KEY_FILE" \
      --web-bot-auth-keyid "$WEB_BOT_AUTH_KEYID"
  else
    echo "WARNING: WEB_BOT_AUTH_KEY_FILE ($WEB_BOT_AUTH_KEY_FILE) not found -- starting without Web Bot Auth." >&2
  fi
fi

echo "Starting: $*" >&2

CHILD_PID=""
SHUTTING_DOWN=0

term_handler() {
  SHUTTING_DOWN=1
  if [ -n "$CHILD_PID" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -TERM "$CHILD_PID" 2>/dev/null
    wait "$CHILD_PID" 2>/dev/null
  fi
  exit 0
}
trap term_handler TERM INT

MAX_RESTARTS=5
RESTART_WINDOW=60
restart_count=0
window_start=$(date +%s)

while true; do
  "$@" &
  CHILD_PID=$!
  EXIT_CODE=0
  wait "$CHILD_PID" || EXIT_CODE=$?
  CHILD_PID=""

  [ "$SHUTTING_DOWN" = "1" ] && exit 0

  now=$(date +%s)
  if [ $((now - window_start)) -gt "$RESTART_WINDOW" ]; then
    window_start="$now"
    restart_count=0
  fi
  restart_count=$((restart_count + 1))

  echo "lightpanda exited with code $EXIT_CODE (restart $restart_count/$MAX_RESTARTS in ${RESTART_WINDOW}s window)" >&2

  if [ "$restart_count" -ge "$MAX_RESTARTS" ]; then
    echo "FATAL: too many crashes in ${RESTART_WINDOW}s window -- exiting so Render flags the deploy unhealthy." >&2
    exit 1
  fi

  sleep 1
done
