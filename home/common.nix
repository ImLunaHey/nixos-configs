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
      [ -d "/opt/homebrew/opt/libpq/bin" ] && export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
      [ -d "$HOME/.cache/lm-studio/bin" ]  && export PATH="$PATH:$HOME/.cache/lm-studio/bin"

      # deno env (sets PATH + DENO_INSTALL).
      [ -s "$HOME/.deno/env" ] && \. "$HOME/.deno/env"

      # nvm (if installed via brew or the install script).
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"

      # bun completions.
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

      # ── extra completions (deno/pnpm, grok, cf) ────────────────────
      for _cdir in "$HOME/.zsh/completions" "$HOME/.grok/completions/zsh"; do
        [ -d "$_cdir" ] && fpath=("$_cdir" $fpath)
      done
      autoload -Uz compinit && compinit
      [ -f "$HOME/.config/cf/completions/_cf.zsh" ] && source "$HOME/.config/cf/completions/_cf.zsh"
    '';
  };

  # ── starship prompt ─────────────────────────────────────────────────
  # Styled to look like oh-my-zsh's robbyrussell theme: `➜  dir git:(branch) ✗`
  # (bold green/red arrow, cyan dir, bold-blue "git:(" + red branch + blue ")",
  # yellow ✗ when dirty). Single line, no leading blank line.
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$character  $directory$git_branch$git_status ";

      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };

      directory = {
        style = "cyan";
        truncation_length = 1; # trailing path component only, like robbyrussell's %c
        truncate_to_repo = false;
        truncation_symbol = "";
        format = "[$path]($style)";
      };

      git_branch = {
        symbol = "";
        format = " [git:(](bold blue)[$branch](red)[)](blue)";
      };

      git_status = {
        style = "yellow";
        format = " [$all_status]($style)";
        conflicted = "✗";
        deleted = "✗";
        modified = "✗";
        renamed = "✗";
        staged = "✗";
        untracked = "✗";
        stashed = "";
        ahead = "";
        behind = "";
        diverged = "";
      };
    };
  };

  # ── git ─────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "luna";
        email = "luna@wvvw.me";
        # SSH-signed commits/tags.
        signingkey = "~/.ssh/id_ed25519.pub";
      };
      init.defaultBranch = "main";
      core.autocrlf = "input";
      gpg = {
        format = "ssh";
        ssh.allowedSignersFile = "~/.config/git/allowed_signers";
      };
      commit.gpgsign = true;
      tag.gpgsign = true;
      # difftastic (installed via brew as `difft`).
      diff.external = "difft";
    };
  };
}
