#!/usr/bin/env bash
# Verifies the image's health check configuration:
#   - the listening port comes from the llama.cpp version configuration file
#     (LLAMA_ARG_PORT) and reaches the runtime stage as a build argument;
#   - the ENV is derived from that argument, so a direct docker build falls
#     back to the Dockerfile default while build-rocm.sh passes the version's
#     value;
#   - the healthcheck is a shell-form command that expands the same variable at
#     container runtime, so the probe cannot drift from the server's port;
#   - when an image and model are available (LLAMA_TEST_IMAGE and
#     LLAMA_TEST_MODEL), the check is exercised at runtime on the default port,
#     with a remapped host port, and with an LLAMA_ARG_PORT override that moves
#     both the server and the probe.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
DOCKERFILE="$SRC/Dockerfile.rocm"

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
note_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

echo "== the runtime stage consumes the version-owned port =="
# Scenario: the port the version file carries arrives as a build argument, and
# the runtime stage derives the environment from it. Direct docker builds that
# bypass build-rocm.sh keep the Dockerfile default.
if grep -qxF 'ARG LLAMA_ARG_PORT=8080' "$DOCKERFILE"; then
    note_pass "runtime stage declares ARG LLAMA_ARG_PORT=8080"
else
    note_fail "runtime stage does not declare ARG LLAMA_ARG_PORT=8080"
fi
if grep -qxF 'ENV LLAMA_ARG_PORT=${LLAMA_ARG_PORT}' "$DOCKERFILE"; then
    note_pass "runtime stage derives LLAMA_ARG_PORT from the build argument"
else
    note_fail "runtime stage does not derive LLAMA_ARG_PORT from the build argument"
fi
if grep -qxF 'ENV LLAMA_ARG_PORT=8080' "$DOCKERFILE"; then
    note_fail "runtime stage still hardcodes ENV LLAMA_ARG_PORT=8080"
else
    note_pass "runtime stage carries no hardcoded LLAMA_ARG_PORT value"
fi

echo
echo "== the healthcheck probes the version-owned port =="
# Scenario: the probe expands the same variable the server reads, at container
# runtime, so a version whose port changes needs no Dockerfile edit.
if grep -qxF 'HEALTHCHECK CMD curl -f "http://localhost:${LLAMA_ARG_PORT}/health"' "$DOCKERFILE"; then
    note_pass "healthcheck probes LLAMA_ARG_PORT in shell form"
else
    note_fail "healthcheck does not probe LLAMA_ARG_PORT in shell form"
fi
if grep -qE '^HEALTHCHECK.*localhost:[0-9]' "$DOCKERFILE"; then
    note_fail "healthcheck still hardcodes a numeric port"
else
    note_pass "healthcheck carries no numeric port"
fi

echo
echo "== the Dockerfile default matches the version file =="
# Scenario: a build that bypasses build-rocm.sh falls back to the ARG default,
# so the default and the version file must agree.
VERSION_FILE_PORT="$(sed -n 's/^LLAMA_ARG_PORT=//p' "$SRC/conf/llamacpp-v0.5.0.env")"
ARG_DEFAULT_PORT="$(sed -n 's/^ARG LLAMA_ARG_PORT=//p' "$DOCKERFILE")"
if [ -n "$VERSION_FILE_PORT" ] && [ "$VERSION_FILE_PORT" = "$ARG_DEFAULT_PORT" ]; then
    note_pass "ARG default matches the version file ($ARG_DEFAULT_PORT)"
else
    note_fail "ARG default '$ARG_DEFAULT_PORT' does not match the version file '$VERSION_FILE_PORT'"
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

echo
echo "== runtime: LLAMA_ARG_PORT override moves the probe =="
# Scenario: setting LLAMA_ARG_PORT at run time moves the server and the
# shell-form healthcheck together, so the container is healthy on the new port
# without a custom healthcheck. The official exec-form healthcheck would still
# probe 8080 here.
CONTAINER="hc-override-$$"
docker run -d --name "$CONTAINER" -e LLAMA_ARG_PORT=9090 -p 19090:9090 "$IMAGE" \
    -m "$MODEL" --host 0.0.0.0 >/dev/null 2>&1
sleep 2
for _ in $(seq 1 30); do
    STATUS="$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null)"
    [ "$STATUS" = "healthy" ] && break
    sleep 2
done
STATUS="$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null)"
if [ "$STATUS" = "healthy" ]; then
    note_pass "container healthy with an LLAMA_ARG_PORT override"
else
    note_fail "container not healthy with an LLAMA_ARG_PORT override (status: ${STATUS:-unknown})"
fi
docker rm -f "$CONTAINER" >/dev/null 2>&1

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]