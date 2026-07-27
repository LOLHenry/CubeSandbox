# AGENTS Policy



## AI-Generated Code Policy

AI agents MUST NOT add Signed-off-by tags. Only humans can legally certify the Developer Certificate of Origin (DCO). The human submitter is responsible for:

- Reviewing all AI-generated code
- Ensuring compliance with licensing requirements
- Adding their own Signed-off-by tag to certify the DCO
- Taking full responsibility for the contribution

**MUST FOLLOW THIS**: When performing a `git commit` or submitting a GitHub PR, the commit message or PR description MUST include the following tag — this is required so that agent contributions remain visible and attributable in the project history:

- If the work was **human-assisted by an AI agent**, include:

```
Assisted-by: AGENT_NAME:MODEL_VERSION
```

- If the commit/PR was **fully completed autonomously by an AI agent** (without human authoring), include instead:

```
Autonomously-by: AGENT_NAME:MODEL_VERSION
```

Where:
- `AGENT_NAME` is the name of the AI tool or framework
- `MODEL_VERSION` is the specific model version used

## Cursor Cloud specific instructions

This repo is the **CubeSandbox** monorepo (Go + Rust + Web). Build/test/format
commands live in `.claude/skills/run-dev/SKILL.md`, the root `Makefile`, and
`web/README.md`; per-component details are in each component's README. The notes
below only capture non-obvious, environment-specific caveats.

### Environment limitations (important)
- **No `/dev/kvm` / nested virtualization** in the Cloud VM. You can *build* and
  *unit-test* everything, but you **cannot actually launch MicroVM sandboxes**.
  As a result the ~8 `agent` `sandbox::tests`/`cgroup` tests fail (read-only fs /
  "create cgroup v2"), and cluster/integration flows that need a live node
  (Cubelet + hypervisor) cannot run. These failures are environment limits, not
  code bugs — the other 102 `agent` tests pass.
- **Docker is required for all Go/Rust builds/tests** (they run inside the
  `cube-sandbox-builder:ubuntu2004` image via `make builder-*`), but Docker is
  **not** installed by the startup update script. If backend work is needed,
  install Docker (docker-in-docker: `storage-driver: fuse-overlayfs` with
  `features.containerd-snapshotter: false`, `iptables-legacy`), start `dockerd`,
  then `make builder-image` once. The web dashboard needs no Docker.

### Web dashboard (primary locally-runnable app)
- `make web-install` / `make web-dev` (Vite dev server on `:5173`) / `make
  web-lint` (`tsc -b --noEmit`) / `make web-build`.
- **Mock mode is currently broken**: `VITE_USE_MOCK=1` / `?mock=1` starts MSW,
  but its handlers use stale `/cubeapi/v1/*` paths while the client now calls the
  API root + `/opsapi/v1` (see `web/src/lib/api.ts`), and there is no mock
  `/auth/session` handler — so the app just bounces to `/login`. Run the real
  control plane instead of relying on mock mode.

### Running the dashboard end-to-end without KVM
The control plane runs fine without KVM (you just get 0 worker nodes). Minimal
stack to log into the dashboard and see live cluster data:
- MySQL (db `cube_mvp`, user `cube`/`cube_pass`) and Redis. **Redis must use
  password `ceuhvu123`** to match `CubeMaster/conf.yaml`.
- Build `make cubemaster` and `make cubeops` (host-runnable static binaries land
  in `_output/bin/`).
- Run CubeOps: `DATABASE_URL=mysql://cube:cube_pass@127.0.0.1:3306/cube_mvp
  JWT_SECRET=<any> CUBE_MASTER_ADDR=http://127.0.0.1:8089 CUBE_OPS_BIND=0.0.0.0:3010
  _output/bin/cubeops`. It auto-migrates the schema and seeds a default
  **`admin` / `admin`** WebUI login.
- Run CubeMaster: `CUBE_MASTER_CONFIG_PATH=CubeMaster/conf.yaml
  _output/bin/cubemaster` (HTTP `:8089`, Cubelet gRPC `:9999`). Its log dir
  `/data/log` must exist and be writable.
- Vite proxies `/opsapi`→CubeOps and the SDK paths→CubeAPI `:3000` (see
  `web/vite.config.ts`).

### Build/test gotchas beyond the run-dev skill
- `make builder-run` uses the **default bridge network** (no `--network host`),
  so processes inside the builder cannot reach host services (Redis/MySQL) via
  `localhost`. Run those services on the docker bridge, or run the built host
  binaries directly (as done above for cubeops/cubemaster).
- `agent`'s `make test` target does **not** generate `src/version.rs` (only the
  build target does); run `make src/version.rs` (or a full build) first, else
  `cargo test` fails with `E0583: mod version`.
- `make cubemaster` / `make proto` regenerate committed `*.pb.go` files; revert
  any such churn if it is not part of your change.
