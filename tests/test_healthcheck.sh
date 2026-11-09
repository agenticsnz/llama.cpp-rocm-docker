#!/usr/bin/env bash
# Verifies the image's health check configuration:
#   - the Dockerfile declares a health check that probes port 8080 in exec form,
#     matching the official llama.cpp image (so the port cannot drift from the
#     server's default listening port);
#   - the server's default port (LLAMA_ARG_PORT) is 8080, keeping the two in
#     sync for the default case;
#   - when a model is available (LLAMA_TEST_MODEL), the check is exercised at
#     runtime both on the default port and with a remapped host port.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
DOCKERFILE="$SRC/Dockerfile.rocm"

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

echo "== healthcheck is declared in exec form on port 8080 =="
if grep -qxF 'HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]' "$DOCKERFILE"; then
    note_pass "Dockerfile healthcheck matches the official llama.cpp image"
else
    note_fail "Dockerfile healthcheck does not match the official form"
fi

echo
echo "== server default port is 8080 =="
if grep -qxF 'ENV LLAMA_ARG_PORT=8080' "$DOCKERFILE"; then
    note_pass "LLAMA_ARG_PORT defaults to 8080"
else
    note_fail "LLAMA_ARG_PORT is not 8080 by default"
fi

# Runtime checks are optional: they need docker, a built image and a model.
IMAGE="${LLAMA_TEST_IMAGE:-}"
MODEL="${LLAMA_TEST_MODEL:-}"

if [ -z "$IMAGE" ] || [ -z "$MODEL" ]; then
    echo
    echo "Skipping runtime checks (set LLAMA_TEST_IMAGE and LLAMA_TEST_MODEL to enable)."
    printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
    exit $?
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not available; skipping runtime checks"
    printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
    exit $?
fi

echo
echo "== runtime: default port 8080 =="
CONTAINER="hc-default-$$"
docker run -d --name "$CONTAINER" -p 18080:8080 "$IMAGE" \
    -m "$MODEL" --host 0.0.0.0 >/dev/null 2>&1
sleep 2
# Wait for the model to load (up to ~60s), then check health.
for _ in $(seq 1 30); do
    STATUS="$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null)"
    [ "$STATUS" = "healthy" ] && break
    sleep 2
done
STATUS="$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null)"
if [ "$STATUS" = "healthy" ]; then
    note_pass "container healthy on default port 8080"
else
    note_fail "container not healthy on default port (status: ${STATUS:-unknown})"
fi
docker rm -f "$CONTAINER" >/dev/null 2>&1

echo
echo "== runtime: remapped host port (9090 -> 8080) =="
CONTAINER="hc-remapped-$$"
docker run -d --name "$CONTAINER" -p 9090:8080 "$IMAGE" \
    -m "$MODEL" --host 0.0.0.0 >/dev/null 2>&1
sleep 2
for _ in $(seq 1 30); do
    STATUS="$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null)"
    [ "$STATUS" = "healthy" ] && break
    sleep 2
done
STATUS="$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null)"
if [ "$STATUS" = "healthy" ]; then
    note_pass "container healthy with remapped host port"
else
    note_fail "container not healthy with remapped host port (status: ${STATUS:-unknown})"
fi
docker rm -f "$CONTAINER" >/dev/null 2>&1

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]