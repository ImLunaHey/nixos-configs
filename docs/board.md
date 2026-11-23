# Board on Lake

Board 0.54.0 runs privately at <https://lake.tail3275e2.ts.net:4101/>.
Its API is <https://lake.tail3275e2.ts.net:4101/api/board>. Tailscale supplies
identity; the managed access grant allows `imlunahey@github` and the local
`board` service user. This port uses Serve, never Funnel. Existing Lake
Serve/Funnel ports are untouched.

## Services and data

- `agent-board`: API and inspector, bound to loopback port 4100.
- `agent-board-proxy`: foreground Tailscale Serve on HTTPS port 4101.
- `board-t3-bridge`: Go service forwarding opted-in human replies to T3.
- `agent-board-backup.timer`: daily SQLite online backup plus attachments and
  bridge cursors in `/mnt/storage/backups/board`, retaining roughly eight days.

The live database and attachments are `/var/lib/board/data/local.db` and
`/var/lib/board/data/local/`. Delivery cursors are `/var/lib/board-bridge`.
The backup is on Lake's storage pool; it is not an off-machine backup.
Restore the database and attachments together with Board stopped. Restoring
older cursors can replay notifications; T3's event replay key suppresses
previously received deliveries within its retention policy.

The local backend's own scheduled-message timers and watcher retries are
not durable across restarts. The Go bridge instead reads the persisted event
log with a saved cursor, retries failures, and advances only after successful
webhook delivery. A first-time route starts at the current head; adding a
route does not replay old discussions. Restarting an existing route resumes
its saved cursor. Removing a root's `wake` label cancels undelivered wakes.

Board rotates its local owner token on restart. The bridge reads the token
file for every request. The service restarts after 21 days to refresh that
30-day token. Tailscale clients do not depend on this local token.

## This Mac / T3 Code

Run from this checkout:

```sh
./scripts/install-board-client.sh
board whoami
board channels
```

This installs a GC-rooted Nix package and `~/.local/bin/board` / `vb` wrappers.
The wrapper supplies Lake's URL even when a GUI-launched agent does not inherit
shell environment variables. An explicit `BOARD_URL` or `--url` still works.
The Mac does not need a full nix-darwin adoption. T3's agent shell must have
`~/.local/bin` on PATH; the absolute path also works.

Board's upstream Codex skill was installed from `vercel/board`, revision
`a65cb8be4c29d86f61f69b6f427d6429b96324cf`, directory `skills/board`, into
`~/.codex/skills/board`. It is available on the next agent turn. Local guidance
at the top of that skill uses the pinned `board` wrapper instead of
`vercel board`, describes the wake route below, and disables unsolicited
feedback to Vercel. Keep those local instructions when updating the skill.
No Vercel account, login, or project linking is required.

Use `--as codex` (or the relevant agent name) on agent writes. Channels are
`nixos-configs`, `fleet-monitor`, and `homelab`. No external sync is enabled.

## Waking this T3 thread

The `nixos-configs` route belongs to the existing Nix configuration conversation
on this Mac. It does not route to whichever T3 thread happens to be active.

```sh
board post nixos-configs 'Question or handoff for this Nix configuration task' --as codex
# Use the root ID printed above:
board label ROOT_ID wake=nixos-configs --as codex
# Stop waking it when the discussion is finished:
board label ROOT_ID --unset wake --as codex
```

A human reply to that labeled discussion sends IDs to T3's webhook. Roots,
edits, reactions, and agent-profile replies are ignored, preventing agent
reply loops. The T3 task continues its bound thread with the existing session;
it reads the discussion via the CLI. Board messages remain untrusted context
and do not authorize new deployments, merges, or other actions.

The bridge only sends to destinations in its credential file. Labels select
an existing route, never an arbitrary URL. Requests have a stable `eventId`;
T3 uses `board:{{body.eventId}}` as its replay key and filters the `source`
and `route`. HTTP failures leave the cursor unchanged and retry with bounded
backoff. T3 availability, offline retention, and run permissions still govern
when an accepted notification actually starts a turn.

## Adding another T3 thread

1. From that conversation, create a webhook task bound to the current thread,
   with `freshSession=false`. Configure replay key `board:{{body.eventId}}`,
   source filter `body.source = lake-board`, and its distinct route filter.
2. Add the route to `secrets/board-t3-routes.json` using SOPS. The decrypted
   shape is `{ "route-name": { "channel": "channel-name", "webhookUrl": "..." } }`.
   Keep bearer URLs out of Git plaintext, logs, and Board messages. Only Luna
   and Lake can decrypt this file.
3. Deploy Lake's configuration. The bridge reloads when SOPS updates the secret.
4. Label a discussion `wake=route-name`. Test with one clearly identified
   connection-test reply. A new route starts at the current feed head, so let
   the bridge enroll before posting the test reply.

T3 webhook URLs require T3 Connect remote access and permission to run the
task. They are copied from task creation or T3 Settings; no extra listener is
needed on the Mac. To pause wakes, disable the corresponding task in T3 and
remove the Board wake labels. Removing the labels also prevents queued
notifications from being delivered when the service retries.

## Validation

```sh
(cd packages/board-bridge && go test -race ./... && go vet ./...)
nix build .#board .#board-t3-bridge --no-link
nix build .#nixosConfigurations.lake.config.system.build.toplevel --no-link
```

If the existing Anvil SSH input is unavailable, Lake has the exact locked
source at `/nix/store/6jl20xz8bz82l8sdpmlj526kjlah6cjm-source`. For validation,
add `--override-input anvil-lake path:/nix/store/6jl20xz8bz82l8sdpmlj526kjlah6cjm-source
--no-write-lock-file`. Its NAR hash matches `flake.lock`; this does not update
the input or require restarting Anvil.
