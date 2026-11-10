# llama.cpp Port Axis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the image's listening port out of the duplicated `8080` literals in `Dockerfile.rocm` and into the llama.cpp version configuration file, so the server's port and the healthcheck probe are derived from one version-owned value.

**Architecture:** `conf/llamacpp-v0.5.0.env` gains `LLAMA_ARG_PORT=8080`; `build-rocm.sh` owns the key under the `llamacpp` axis and emits `--build-arg LLAMA_ARG_PORT=8080`; the runtime stage declares the `ARG`, derives the `ENV` from it, and a shell-form healthcheck expands the same variable at container runtime. `VERSION` iterates to `1.1.2` because `Dockerfile.rocm` changes.

**Tech Stack:** Bash build script, Dockerfile (BuildKit), Bash test suites. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-10-llamacpp-port-axis-design.md`

## Global Constraints

- The image remains a 1:1 drop-in for the official llama.cpp image: entrypoint `/app/llama-server`, default port `8080`, same HTTP API, no `CMD`.
- No `--port` argv is added; `ENV LLAMA_ARG_PORT` is upstream's own mechanism for `--port` (`.set_env("LLAMA_ARG_PORT")` in `common/arg.cpp`).
- The key name is exactly `LLAMA_ARG_PORT` everywhere: version file, `KEY_AXIS`, Dockerfile `ARG`/`ENV`, healthcheck, tests, docs.
- `Dockerfile.rocm` changes, so `VERSION` in `conf/build-config.env` increments its last component: `1.1.1` → `1.1.2`.
- Documentation is UK English, factual and technical.
- Tests live in `tests/`, never beside the build script.
- Every commit contains only that task's files and no `Co-Authored-By` line.

## Review Focus

- **A version file omits `LLAMA_ARG_PORT`.** The Dockerfile `ARG` default keeps direct builds serving 8080; the cross-file default test in Task 2 catches drift between the two sources.
- **A runtime `-e LLAMA_ARG_PORT=<port>` override.** The shell form moves the server and the probe together; the optional runtime scenario in Task 2 proves it when an image and model are available.
- **A `--port` CLI override.** The CLI wins for the server only, leaving the probe on the image's port; the build guide must direct readers to a healthcheck override, pinned by the Task 3 doc assertion.

---

## Task 1: Make the version file own the listening port

**Files:**
- Modify: `conf/llamacpp-v0.5.0.env`
- Modify: `build-rocm.sh` (`KEY_AXIS`, line 44)
- Test: `tests/test_build_args.sh`

**Interfaces:**
- Consumes: `KEY_AXIS[key]=axis` in `build-rocm.sh`; `conf_key`, `run_dry`, `expect_line`, `reject_line`, `expect_stderr` in the test suite; `RESOLVED_VALUE` and `emit_resolved_arguments` emit one `--build-arg` per resolved key.
- Produces: `--build-arg LLAMA_ARG_PORT=<value>` in dry-run and real builds for every build whose files resolve the key.

The version file's port reaches the build
```gherkin
Scenario: The version file's port reaches the build as a build argument
  Given conf/llamacpp-v0.5.0.env sets LLAMA_ARG_PORT=8080
  When build-rocm.sh resolves the four configuration files with --dry-run
  Then the emitted arguments contain --build-arg LLAMA_ARG_PORT=8080
```

A stray neutral copy loses
```gherkin
Scenario: A stray LLAMA_ARG_PORT in the neutral file loses to the version file
  Given a neutral configuration file sets LLAMA_ARG_PORT=9999
  And conf/llamacpp-v0.5.0.env sets LLAMA_ARG_PORT=8080
  When build-rocm.sh resolves the configuration
  Then the emitted arguments contain --build-arg LLAMA_ARG_PORT=8080
  And the emitted arguments do not contain --build-arg LLAMA_ARG_PORT=9999
  And stderr reports that the copy does not own the llamacpp axis
```

### Steps

- [ ] **Step 1: Write the failing tests in `tests/test_build_args.sh`.**

  Add the expectation after `EXPECTED_LLAMA_CPP_VERSION`:
  ```bash
  # Port the version file declares for the image's server and healthcheck.
  EXPECTED_LLAMA_ARG_PORT="$(conf_key llamacpp-v0.5.0.env LLAMA_ARG_PORT)"
  ```

  Add the happy-path line after the `LLAMA_CPP_VERSION` expectation:
  ```bash
  expect_line "$SCRATCH/o1" "--build-arg LLAMA_ARG_PORT=$EXPECTED_LLAMA_ARG_PORT"
  ```

  Add two sections after the `== a stray LLAMA_CPP_VERSION in the neutral file loses and warns ==` block and before the `== CMAKE_EXTRA_ARGS resolves to the version file's copy ==` block:
  ```bash
  echo
  echo "== LLAMA_ARG_PORT is owned by the version axis =="
  # Scenario: the listening port is version-owned, so the version file carries
  # LLAMA_ARG_PORT and the neutral file does not. One value then drives both the
  # server and the healthcheck.
  if grep -qE '^[[:space:]]*LLAMA_ARG_PORT[[:space:]]*=' "$CONF/llamacpp-v0.5.0.env"; then
      note_pass "llamacpp-v0.5.0.env carries LLAMA_ARG_PORT"
  else
      note_fail "llamacpp-v0.5.0.env does not carry LLAMA_ARG_PORT"
  fi
  if grep -qE '^[[:space:]]*LLAMA_ARG_PORT[[:space:]]*=' "$CONF/build-config.env"; then
      note_fail "build-config.env still carries LLAMA_ARG_PORT"
  else
      note_pass "build-config.env no longer carries LLAMA_ARG_PORT"
  fi

  echo
  echo "== a stray LLAMA_ARG_PORT in the neutral file loses and warns =="
  # Scenario: the version axis owns LLAMA_ARG_PORT, so a copy in the neutral file
  # is discarded with a warning naming the llamacpp axis. The emitted build
  # argument is the version file's value, never the stray one.
  cat > "$SCRATCH/stray-port.env" <<'ENV'
  CMAKE_BUILD_TYPE=Release
  REGISTRY=ghcr.io
  LLAMA_ARG_PORT=9999
  VERSION=1.1.1
  GGML_NATIVE=OFF
  ENV
  rc=$(run_dry "$SCRATCH/p1" "$SCRATCH/pe1" \
      "$CONF/amd-gfx1200.env" "$CONF/amd-7.14.1.env" "$SCRATCH/stray-port.env" \
      "$CONF/llamacpp-v0.5.0.env")
  [ "$rc" = "0" ] && note_pass "exit 0 on collision" || note_fail "exit was $rc, want 0"
  expect_line "$SCRATCH/p1" "--build-arg LLAMA_ARG_PORT=$EXPECTED_LLAMA_ARG_PORT"
  reject_line "$SCRATCH/p1" "--build-arg LLAMA_ARG_PORT=9999"
  expect_stderr "$SCRATCH/pe1" "llamacpp axis"
  ```

- [ ] **Step 2: Verify RED.**

  Run: `bash tests/test_build_args.sh`
  Expected failures, five in total:
  - `expected line: --build-arg LLAMA_ARG_PORT=` in the happy path (the expectation is empty because the key is absent, and nothing matches it)
  - `llamacpp-v0.5.0.env does not carry LLAMA_ARG_PORT`
  - `expected line: --build-arg LLAMA_ARG_PORT=` in the stray case (the same empty expectation, which the stray `9999` value does not match)
  - `unexpected line: --build-arg LLAMA_ARG_PORT=9999` (the unregistered key currently resolves from the neutral file and wins)
  - `expected warning containing: llamacpp axis`

  The stray case's `exit 0 on collision` assertion passes; do not mistake that for the test working. Do not implement until the suite fails for the reasons above.

- [ ] **Step 3: Implement.**

  In `build-rocm.sh`, add the axis entry after `[CMAKE_EXTRA_ARGS]=llamacpp`:
  ```bash
      [LLAMA_ARG_PORT]=llamacpp
  ```

  In `conf/llamacpp-v0.5.0.env`, append:
  ```
  # The port the v0.5.0 image serves on. llama-server reads LLAMA_ARG_PORT as its
  # --port; the official v0.5.0 build serves 8080. build-rocm.sh passes this
  # value to the build as --build-arg.
  LLAMA_ARG_PORT=8080
  ```

- [ ] **Step 4: Verify GREEN.**

  Run: `bash tests/test_build_args.sh`
  Expected: `=== 101 passed, 0 failed ===` (94 before this task plus the 7 added assertions; reconcile the added assertions if the count differs).

- [ ] **Step 5: Commit.**

  ```bash
  git add conf/llamacpp-v0.5.0.env build-rocm.sh tests/test_build_args.sh
  git commit -m "Own the listening port in the llama.cpp version config"
  ```
  Body:
  ```
  - Add LLAMA_ARG_PORT=8080 to the v0.5.0 version file
  - Register the key under the llamacpp axis so build-rocm.sh emits it
  - Cover emission and stray-copy resolution in the argument suite
  ```

---

## Task 2: Derive the runtime environment and healthcheck from the build argument

**Files:**
- Modify: `Dockerfile.rocm` (runtime stage, lines 318-324)
- Modify: `conf/build-config.env` (`VERSION`)
- Test: `tests/test_healthcheck.sh`

**Interfaces:**
- Consumes: `ARG LLAMA_ARG_PORT` supplied by `build-rocm.sh` (or the Dockerfile default when building directly).
- Produces: `ENV LLAMA_ARG_PORT` in the image, and a healthcheck whose command string carries `${LLAMA_ARG_PORT}` for the container shell to expand.

The environment comes from the argument
```gherkin
Scenario: The runtime stage derives LLAMA_ARG_PORT from a declared build argument
  Given the runtime stage of Dockerfile.rocm
  When the file is inspected
  Then it declares ARG LLAMA_ARG_PORT=8080
  And it contains ENV LLAMA_ARG_PORT=${LLAMA_ARG_PORT}
  And it contains no ENV LLAMA_ARG_PORT=8080 literal
```

The probe follows the variable
```gherkin
Scenario: The healthcheck probes the version-owned port
  Given the runtime stage of Dockerfile.rocm
  When the healthcheck instruction is inspected
  Then it contains HEALTHCHECK CMD curl -f "http://localhost:${LLAMA_ARG_PORT}/health"
  And no healthcheck instruction contains a numeric localhost port
```

The defaults agree
```gherkin
Scenario: The ARG default matches the version file
  Given conf/llamacpp-v0.5.0.env sets LLAMA_ARG_PORT=8080
  When the default of ARG LLAMA_ARG_PORT in Dockerfile.rocm is read
  Then it equals 8080
```

### Steps

- [ ] **Step 1: Write the failing tests in `tests/test_healthcheck.sh`.**

  Replace the header comment (lines 2-9) with:
  ```bash
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
  ```

  Replace the two static sections (currently lines 21-34) with:
  ```bash
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
  ```

  Append a third runtime block after the remapped-host-port block:
  ```bash
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
  ```

- [ ] **Step 2: Verify RED.**

  Run: `bash tests/test_healthcheck.sh`
  Expected failures, six in total (runtime checks remain skipped):
  - `runtime stage does not declare ARG LLAMA_ARG_PORT=8080`
  - `runtime stage does not derive LLAMA_ARG_PORT from the build argument`
  - `runtime stage still hardcodes ENV LLAMA_ARG_PORT=8080`
  - `healthcheck does not probe LLAMA_ARG_PORT in shell form`
  - `healthcheck still hardcodes a numeric port`
  - `ARG default '' does not match the version file '8080'`

- [ ] **Step 3: Implement.**

  In `Dockerfile.rocm`, replace the final block with:
  ```dockerfile
  # The listening port is owned by the llama.cpp version file and arrives as a
  # build argument. LLAMA_ARG_PORT is upstream's own mechanism for --port, and
  # the shell-form healthcheck below expands the same value at container runtime,
  # so the server and the probe cannot disagree.
  ARG LLAMA_ARG_PORT=8080
  ENV LLAMA_ARG_HOST=0.0.0.0
  ENV LLAMA_ARG_PORT=${LLAMA_ARG_PORT}
  WORKDIR /app


  HEALTHCHECK CMD curl -f "http://localhost:${LLAMA_ARG_PORT}/health"
  ENTRYPOINT ["/app/llama-server"]
  ```

  In `conf/build-config.env`, change `VERSION=1.1.1` to `VERSION=1.1.2`.

- [ ] **Step 4: Verify GREEN.**

  Run: `bash tests/test_healthcheck.sh`
  Expected: `=== 6 passed, 0 failed ===` with the runtime checks skipped.

  Run: `bash tests/test_build_args.sh`
  Expected: `=== 101 passed, 0 failed ===`. The guard now also accepts `LLAMA_ARG_PORT` because the Dockerfile declares the `ARG`.

- [ ] **Step 5: Commit.**

  ```bash
  git add Dockerfile.rocm conf/build-config.env tests/test_healthcheck.sh
  git commit -m "Derive the image port from the llama.cpp version config"
  ```
  Body:
  ```
  - Declare ARG LLAMA_ARG_PORT and derive the runtime ENV from it
  - Probe the same variable with a shell-form healthcheck
  - Iterate the image version to 1.1.2 for the Dockerfile change
  ```

---

## Task 3: Document the version-owned port

**Files:**
- Modify: `docs/local-build-guide.md` (`### Ports and the healthcheck`)
- Modify: `README.md` (llama.cpp versions table)
- Test: `tests/test_docs.sh`

**Interfaces:**
- Consumes: nothing at runtime; pins the prose that explains the mechanism shipped by Tasks 1 and 2.
- Produces: two documented statements used by the doc assertions: the port's source, and the behaviour of an `LLAMA_ARG_PORT` override.

The guide states the source
```gherkin
Scenario: The build guide documents the version-owned port
  Given docs/local-build-guide.md
  When the Ports and the healthcheck section is read
  Then it states the port comes from the llama.cpp version configuration file
```

The guide states the override behaviour
```gherkin
Scenario: The build guide documents that an override moves the probe
  Given docs/local-build-guide.md
  When the Ports and the healthcheck section is read
  Then it states that the healthcheck expands the same variable as the server
```

### Steps

- [ ] **Step 1: Write the failing tests in `tests/test_docs.sh`.**

  Add before the final summary:
  ```bash
  echo
  echo "== the guide documents the version-owned port =="
  # Scenario: the guide states where the image's listening port comes from.
  if grep -qF -- 'comes from the llama.cpp version configuration file' "$BUILD_GUIDE"; then
      note_pass "guide states the port comes from the version configuration file"
  else
      note_fail "guide does not state the port's version-file source"
  fi
  # Scenario: the guide states that a runtime LLAMA_ARG_PORT override moves the
  # healthcheck probe as well as the server.
  if grep -qF -- 'the healthcheck expands the same variable' "$BUILD_GUIDE"; then
      note_pass "guide states that the healthcheck follows an LLAMA_ARG_PORT override"
  else
      note_fail "guide does not state that the healthcheck follows an env override"
  fi
  ```

- [ ] **Step 2: Verify RED.**

  Run: `bash tests/test_docs.sh`
  Expected failures:
  - `guide does not state the port's version-file source`
  - `guide does not state that the healthcheck follows an env override`

- [ ] **Step 3: Implement.**

  In `docs/local-build-guide.md`, replace the paragraph at lines 56-59 with a single-line paragraph:
  ```
  The listening port comes from the llama.cpp version configuration file: `conf/llamacpp-v0.5.0.env` sets `LLAMA_ARG_PORT=8080`, which `build-rocm.sh` passes to the build. The runtime stage derives its `LLAMA_ARG_PORT` environment from that value, and the healthcheck expands the same variable inside the container, so the probe cannot drift from the port the server reads. The image keeps the official llama.cpp image's default: the internal port stays 8080, and you remap to a different host port rather than changing `--port`.
  ```

  Replace the override paragraph at lines 81-83 with a single-line paragraph:
  ```
  If you must run the server on a different internal port, prefer setting `LLAMA_ARG_PORT`, for example `-e LLAMA_ARG_PORT=9090`: the healthcheck expands the same variable, so it follows the server without any custom configuration. A `--port` argument overrides the environment for the server only, leaving the healthcheck on the image's port; in that case override the healthcheck yourself, for example:
  ```

  In `README.md`, add this row to the llama.cpp versions table after the `CMAKE_EXTRA_ARGS` row:
  ```
  | `LLAMA_ARG_PORT` | Port the image serves on; upstream reads it for `--port`, and the healthcheck expands the same value |
  ```

- [ ] **Step 4: Verify GREEN.**

  Run: `bash tests/test_docs.sh`
  Expected: `=== 20 passed, 0 failed ===` (18 before this task plus the 2 added assertions).

  Run: `bash tests/test_contributing.sh`
  Expected: unchanged pass; the versioning rule already covers the `1.1.1` → `1.1.2` iteration.

- [ ] **Step 5: Commit.**

  ```bash
  git add docs/local-build-guide.md README.md tests/test_docs.sh
  git commit -m "Document the version-owned listening port"
  ```
  Body:
  ```
  - Record the version file as the port's source in the build guide
  - Explain how an LLAMA_ARG_PORT override moves the probe
  - List LLAMA_ARG_PORT in the llama.cpp versions table
  ```

---

## Final verification

- [ ] Run every fast suite from the repository root:
  ```bash
  bash tests/test_build_args.sh
  bash tests/test_healthcheck.sh
  bash tests/test_docs.sh
  bash tests/test_contributing.sh
  bash tests/test_issue_forms.sh
  bash tests/test_matrix_discovery.sh
  ```
  Every suite must report `0 failed`. The healthcheck runtime block is skipped without `LLAMA_TEST_IMAGE` and `LLAMA_TEST_MODEL`.

- [ ] Run a dry run against the real four files and confirm the emitted argument:
  ```bash
  ./build-rocm.sh --arch-env conf/amd-gfx1200.env --rocm-env conf/amd-7.14.1.env \
      --config-env conf/build-config.env --llamacpp-env conf/llamacpp-v0.5.0.env \
      --source llama.cpp/v0.8.0 --dry-run | grep LLAMA_ARG_PORT
  ```
  Expected: `--build-arg LLAMA_ARG_PORT=8080`.

- [ ] Confirm the working tree holds only the intended changes:
  ```bash
  git status --short
  git log --oneline -4
  ```

- [ ] Optional image proof (needs the multi-minute build and an AMD host):
  ```bash
  docker inspect <image> --format '{{json .Config.Env}}'
  docker inspect <image> --format '{{json .Config.Healthcheck.Test}}'
  ```
  Expected: an environment entry `LLAMA_ARG_PORT=8080`, and a healthcheck test of `["CMD-SHELL","curl -f \"http://localhost:${LLAMA_ARG_PORT}/health\""]`. Report this as unverified if the build is not run.

- [ ] Do not push and do not open the pull request unless the user asks.
