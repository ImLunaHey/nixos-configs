# Push deployments over NetBird

`.github/workflows/deploy.yml` deploys committed `main` revisions from GitHub
Actions. It checks out the triggering commit, installs a checksum-pinned NetBird
client, joins our self-hosted network, and pushes a source snapshot through SSH.
The target builds and activates it. Hosts do not poll GitHub or update inputs.
Pull requests never receive deployment credentials or trigger deployments.

The workflow is inactive until `NETBIRD_DEPLOY_TARGETS` is configured. Bootstrap:

1. Complete the initial NetBird and Pocket ID administrator setup and remove the
   temporary Caddy onboarding restriction as described in `machines/gateway/README.md`.
2. Deploy the NetBird client configuration to each Linux host over existing
   administrative SSH access, then enrol it with `sudo netbird up`. Install/enrol
   the NetBird macOS client before opting a Mac into CI. Keep Tailscale available.
3. The dedicated deployment public key is in `machines/gateway/deploy.pub`,
   included for `luna` on the VPS and Linux hosts. Its authorized-key options
   restrict source addresses to the current NetBird subnet (`100.66.0.0/16`) and
   disable forwarding, PTYs, and user startup scripts. When rotating it, generate
   a dedicated SSH key on a trusted machine, update this public-key file, and
   deploy it before replacing the GitHub secret. Update the source restriction
   too if the NetBird subnet changes.
   Do not reuse a personal private key in Actions. A deploy identity that can
   activate arbitrary Nix configurations is necessarily trusted with root access.
4. Set repository secret `DEPLOY_SSH_PRIVATE_KEY` to the private key and
   `DEPLOY_SSH_KNOWN_HOSTS` to independently verified SSH host keys indexed by
   each host's NetBird IP. Never populate trust by unverified scanning in CI.
   CI also needs noninteractive sudo for the rebuild command on every target;
   Linux admin users already have it, while Macs require explicit setup.
5. Create a reusable NetBird setup key with **ephemeral peers** enabled,
   auto-assigned to a `github-deploy` group. Store it as `NETBIRD_SETUP_KEY`.
   The current key has unlimited usage and no expiry. Permanent hosts use a
   separate `homelab` key/group with ephemeral peers disabled.
   NetBird access policies should allow `github-deploy` to initiate connections
   to `homelab` on TCP 22 only. Preserve host-to-host access with a separate
   `homelab` policy, then disable any broad default policy that overrides the
   CI restriction.
6. Set repository variable `NETBIRD_DEPLOY_TARGETS` to a JSON list of objects with
   `host` (the flake configuration name) and `target` (`user@NETBIRD_IP`). Add only
   enrolled, reachable hosts; do not enter public or Tailscale addresses. The
   workflow verifies the route uses `wt0` and refuses a public fallback.
7. Run the workflow manually on `main`, then review its result. Subsequent pushes
   to `main` deploy the same committed revision to each configured target.

The deployment job has read-only repository permissions, pinned checkout code,
strict SSH host-key verification, no persisted GitHub checkout credential, and
per-host concurrency. Hosts build their own architecture, so a Linux runner can
push to NixOS or nix-darwin. Pinned private flake inputs must be accessible to the
remote build user. The runner is disconnected at the end; ephemeral enrolment
prevents abandoned permanent peers.

This PR adds the workflow and client configuration. It does not provision GitHub
secrets, claim application admin accounts, enrol peers, or distribute a deploy
key automatically. Enable the target list only after those prerequisites exist.

For manual deployment or recovery, run `python3 scripts/deploy.py HOST` from a
clean checkout, using `--target` for the chosen SSH address. The successful
release path is recorded on the target under `.local/state/nixos-configs`.
