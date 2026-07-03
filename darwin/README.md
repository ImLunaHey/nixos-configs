# macOS (nix-darwin) hosts

User dotfiles (zsh, aliases, git, starship) live in [`../home/common.nix`](../home/common.nix)
and are shared across every Mac. System-level config (Homebrew, macOS defaults,
Nix settings) lives here in `darwin/`.

| Host | Machine |
|------|---------|
| `pulsar` | Mac mini (Apple Silicon) |
| `comet`  | MacBook Pro — *not yet added* |

## First-time bootstrap on a fresh Mac

1. **Install Nix** using the official multi-user installer (nix-darwin manages the
   daemon it sets up — `nix.enable` is left at its default `true`):

   ```sh
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```

   > Do NOT use the Determinate Systems installer here — it owns the daemon itself
   > and would conflict with `nix.enable = true`. If you ever switch to it, set
   > `nix.enable = false;` in `darwin/common.nix`.

2. **Install Homebrew** (nix-darwin drives `brew bundle` but does not install brew):

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

3. **Build the host for the first time** (`pulsar` shown; substitute the real host):

   ```sh
   nix run nix-darwin -- switch --flake ~/code/imlunahey/nixos-configs#pulsar
   ```

   After this, `darwin-rebuild` is on your PATH.

4. **Set zsh as the login shell** (nix-darwin manages `/etc/zshrc`, but the account
   shell must be zsh — it is by default on modern macOS):

   ```sh
   chsh -s /bin/zsh
   ```

## Day-to-day

```sh
# Apply config changes
darwin-rebuild switch --flake ~/code/imlunahey/nixos-configs#pulsar

# Update flake inputs (nixpkgs, nix-darwin, home-manager)
nix flake update
```

## Adding a new Mac (e.g. the MacBook, `comet`)

1. `mkdir darwin/comet` and add a `default.nix` setting `networking.hostName` etc.
   (copy `darwin/pulsar/default.nix`).
2. Add a `darwinConfigurations.comet` entry in `flake.nix`.
3. Add `comet` to `darwin_purpose()` in `scripts/generate-readme.sh` so the README
   picks up a friendly name.
4. Bootstrap it with the steps above.

The user environment (`home/common.nix`) is shared automatically — no per-host dotfile
duplication.
