{ pkgs, ... }:

# Shared user environment (home-manager). Imported by each darwin host, which
# supplies the account identity (home.username / home.homeDirectory) — the mini
# runs as `xo`, the MacBook as `luna`, but the shell/git/aliases are identical.
# Ported from the old ~/.zshrc + ~/code/imlunahey/dot-files/aliases, modernised.
{
  # Don't change without reading the home-manager release notes.
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  # A small set of tools managed by nix. Most CLI tooling still lives in
  # Homebrew (see darwin/common.nix) and can migrate here over time.
  home.packages = with pkgs; [
    ripgrep
    fd
    tree
  ];

  home.sessionVariables = {
    EDITOR = "nano";
    # Disable npm ad / funding noise.
    DISABLE_OPENCOLLECTIVE = "1";
    ADBLOCK = "1";
    SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
  };

  # ── zsh ─────────────────────────────────────────────────────────────
  # Replaces oh-my-zsh with home-manager's native zsh + plugins.
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 100000;
      save = 100000;
      ignoreDups = true;
      share = true;
    };

    shellAliases = {
      c = "clear";
      ear = "clear";
      reload = "source ~/.zshrc && clear";
      changed = "git diff -w HEAD --staged -- . ':!yarn.lock' ':!*package-lock.json'";
      commit = "npx git-cz";
      vlc = "/Applications/VLC.app/Contents/MacOS/VLC";
      claude-work = "CLAUDE_CONFIG_DIR=~/.claude-work claude";
      claude-personal = "CLAUDE_CONFIG_DIR=~/.claude-personal claude";
    };

    initContent = ''
      # ── functions ──────────────────────────────────────────────────
      # Clone a repo into ~/code/<org>/<repo> (matches how repos are laid out
      # on all my Macs).
      ghclone() {
        local url="''${1%/}"
        url="''${url%.git}"
        local path="''${url#*github.com/}"
        local dest="$HOME/code/$path"
        mkdir -p "''${dest%/*}"
        git clone "$url" "$dest"
        echo "Cloned into $dest"
      }

      branch_create() { git checkout -b "$1"; }
      branch_delete() { git branch -d "$1"; }

      # Run a command with the current .env loaded.
      load_env() { env $(cat .env | xargs) "$@"; }

      # Generate a short random id.
      gen() { node -p '[...Array(30)].map(() => Math.random().toString(36)[3]).join("");'; }

      # ── PATH / tool bootstraps (non-nix tools, guarded so they're safe on a
      #    fresh machine that doesn't have them yet) ────────────────────
      export PATH="$HOME/.local/bin:$PATH"
      [ -d "$HOME/.cargo/bin" ]     && export PATH="$HOME/.cargo/bin:$PATH"
      [ -d "$HOME/.bun/bin" ]       && export PATH="$HOME/.bun/bin:$PATH"
      [ -d "$HOME/.deno/bin" ]      && export PATH="$HOME/.deno/bin:$PATH"
      [ -d "$HOME/Library/pnpm" ]   && export PATH="$HOME/Library/pnpm:$PATH"
      [ -d "$HOME/.sst/bin" ]       && export PATH="$HOME/.sst/bin:$PATH"
      [ -d "$HOME/.opencode/bin" ]  && export PATH="$HOME/.opencode/bin:$PATH"
      [ -d "$HOME/.amp/bin" ]       && export PATH="$HOME/.amp/bin:$PATH"
      [ -d "$HOME/.grok/bin" ]      && export PATH="$HOME/.grok/bin:$PATH"

      # nvm (if installed via brew or the install script).
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"

      # bun completions.
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
    '';
  };

  # ── starship prompt ─────────────────────────────────────────────────
  programs.starship.enable = true;

  # ── git ─────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    userName = "luna";
    userEmail = "luna@wvvw.me";
    extraConfig = {
      init.defaultBranch = "main";
      core.autocrlf = "input";
      # SSH-signed commits/tags.
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";
      user.signingkey = "~/.ssh/id_ed25519.pub";
      commit.gpgsign = true;
      tag.gpgsign = true;
      # difftastic (installed via brew as `difft`).
      diff.external = "difft";
    };
  };
}
