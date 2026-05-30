# Ralph Sandbox Naming

Ralph runs every iteration through a Docker Sandboxes (`sbx`) microVM and gives that sandbox a deterministic name so the same project + agent pair always reuses the same sandbox.

## Name format

```
ralph-<agent>-<current-dir>-<hash8>
```

- `<agent>` — the selected agent slug (`claude`, `codex`, `copilot`, `cursor`, `gemini`, `opencode`), lowercased.
- `<current-dir>` — basename of the project directory, sanitized to `[a-z0-9-]`.
- `<hash8>` — first 8 hex chars of `sha256(absolute project path)`. Falls back to `sha256sum` and then to `cksum` if `shasum` is unavailable.

Example: a project at `/Users/me/Work/My App` running Claude becomes `ralph-claude-my-app-a1b2c3d4`.

## Where it appears

- Printed at startup on the `Starting Ralph` line in `ralph.sh` so you can copy it directly.
- Used in the authentication-error message via `agent_login_command`. The actual command varies — see "Create vs attach lifecycle" below.
- Passed to every `sbx run` invocation that Ralph constructs in `build_agent_command`.
- Precomputed in `bin/cli.js` (via `bin/lib/sandbox-name.js`) at the end of `npx @pageai/ralph-loop`, so the install completion screen shows a copy-paste-ready login command per agent. The install screen always emits the **create form** because a fresh install has no sandbox yet; subsequent `./ralph.sh --login` runs print the correct form automatically.

## Create vs attach lifecycle

`sbx run --name <name> <agent> .` is **create-only** — passing `--name` for a sandbox that already exists fails with:

```
ERROR: sandbox '<name>' already exists; --name can only be used when creating a new sandbox
```

So Ralph emits two different commands depending on whether the deterministic sandbox already exists:

| Lifecycle | Command Ralph emits |
| --- | --- |
| Sandbox does not exist (first run) | `sbx run --name <name> <agent> . [-- AGENT_ARGS...]` |
| Sandbox exists (every subsequent run) | `sbx run <name> [-- AGENT_ARGS...]` |

The attach form drops the agent slug and workspace path because both are baked into the sandbox at creation time. Both forms accept the same `[-- AGENT_ARGS...]` tail, so per-agent flag plumbing in `build_agent_command` is unchanged.

The decision is made by `sandbox_exists` (in `scripts/lib/agents.sh`), which probes `sbx ls --quiet | grep -Fxq <name>`. The probe runs:

- once per loop iteration in `ralph.sh` (so iteration 1 creates, iteration 2+ attaches, and the loop self-heals if a user `sbx rm`'s the sandbox between iterations);
- once for the `--login` and `--ports` action paths;
- once for each call to `print_login_suggestions` / `print_ports_suggestions` (one `sbx ls --quiet` is captured and reused for all agents in the printout).

If `sbx` itself is missing, `check_sbx_available` (in `scripts/lib/preflight.sh`) exits with `EXIT_SBX_MISSING=6` and points at <https://docs.docker.com/ai/sandboxes/get-started/>. Transient `sbx ls` failures are treated as "sandbox does not exist" so the real `sbx run` error surfaces if anything is genuinely broken.

## Retrieving the name

- `./ralph.sh --print-name` prints the deterministic sandbox name for the selected agent and exits.
- `./ralph.sh --print-name --agent cursor` prints the Cursor sandbox name for the same project.
- `./ralph.sh --login` prints all supported login commands, then opens the selected agent inside its correctly named sandbox.
- `./ralph.sh --login --agent codex` does the same for Codex.

## Why deterministic

- Reusing the same name lets Docker Sandboxes reconnect to the existing sandbox between runs instead of creating a new one each iteration.
- The path-derived hash keeps two same-named directories on different paths from colliding (for example, `~/Work/app` and `/tmp/app`).
- Agent slug is part of the name, so switching `--agent` yields a separate sandbox for the same project, which avoids surprising Claude/Codex sandbox swaps.

## Cleanup behavior

- On normal exit, double Ctrl+C, or any other path that fires the `EXIT` trap, Ralph runs `sbx stop "$RALPH_SANDBOX_NAME"` and only that name.
- `cleanup` is guarded with `CLEANUP_DONE` so it runs at most once even if both the `EXIT` trap and an interrupt path call it.
- Sandboxes started for other agents in the same project are not touched.

## Inspecting and reusing the sandbox

- `sbx ls` lists sandboxes; the Ralph-managed name will follow the format above.
- `sbx exec -it <ralph-sandbox-name> bash` opens a shell into the same sandbox the loop uses.
- `sbx run <ralph-sandbox-name>` reattaches Ralph's sandbox for manual login or debugging. (Use `sbx run --name <ralph-sandbox-name> <agent> .` only the **first** time, before the sandbox exists — see "Create vs attach lifecycle" above.)

## Implementation pointers

The naming algorithm has **two implementations that must stay in sync** — Bash for the runtime loop and JavaScript for the install CLI:

- **Bash (runtime, source of truth at runtime)**: `scripts/lib/agents.sh` — `build_sandbox_name`, `sanitize_sandbox_name_segment`, `sandbox_path_hash`, `sandbox_exists`.
- **JavaScript (install-time precompute)**: `bin/lib/sandbox-name.js` — `buildSandboxName`, `sanitizeSandboxNameSegment`, `sandboxPathHash`. Used by `bin/cli.js` to render the login commands at the end of `npx @pageai/ralph-loop`. The JS twin always emits the **create form** because it runs at install time when no sandbox exists yet — only the Bash side branches on `sandbox_exists`.
- **Wire-up**: `ralph.sh` computes `RALPH_SANDBOX_NAME` after argument parsing, calls `check_sbx_available`, then probes `sandbox_exists` for the loop iteration / `--login` / `--ports` action and passes the result into `build_agent_command` / `agent_login_command`.
- **Cleanup**: `scripts/lib/cleanup.sh` runs `sbx stop "$RALPH_SANDBOX_NAME"` with a 5s timeout.
- **Tests**:
  - `tests/test-args-agents.sh` — Bash name format and command construction (paired create/attach assertions, `sandbox_exists` probe, `print_*_suggestions` per-agent branching).
  - `tests/test-cleanup-sandbox.sh` — single-sandbox cleanup and idempotency.
  - `tests/lib/fake-sbx.sh` — shared fake-`sbx`-on-PATH helper used by the agents and cleanup tests.
  - `tests/test-sandbox-name-js.js` — **parity test**: shells out to `build_sandbox_name` from `agents.sh` for every supported agent and asserts byte-for-byte equality with `bin/lib/sandbox-name.js`. Run this whenever you touch either implementation.

## Keeping Bash and JavaScript in sync

Both implementations must produce **byte-identical** sandbox names for the same `(agent, projectPath)` pair, because `bin/cli.js` precomputes commands that `ralph.sh` later reuses unchanged. If you change one, change the other in the same commit and re-run `node tests/test-sandbox-name-js.js`.

The contract is:

1. Lowercase the agent slug and the basename of the project directory.
2. Replace any run of non-`[a-z0-9]` characters with a single `-`, then trim leading/trailing `-`. Empty result becomes `sandbox`.
3. `hash8` = first 8 hex chars of `sha256(absolute_project_path)` (the **full path string**, not the basename).
4. Final name: `ralph-<safe_agent>-<safe_project>-<hash8>`.

The Bash side adds two fallbacks for the hash (`sha256sum`, then `cksum`) when `shasum` is missing; the JS side uses Node's `crypto` directly. As long as `shasum -a 256` is available (the default on macOS and most Linux CI images), both produce the same hash.
