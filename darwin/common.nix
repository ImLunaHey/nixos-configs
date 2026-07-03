{ pkgs, ... }:

# Shared configuration for all macOS (nix-darwin) hosts.
# Host-specific bits (hostname) live in darwin/<host>/default.nix.
{
  # User identity (system.primaryUser, users.users.<name>, home-manager.users.<name>)
  # is set per-host in darwin/<host>/default.nix, since the account name differs
  # per machine (mini = xo, MacBook = luna).

  # Nix settings (mirror common.nix for the NixOS hosts).
  #
  # NOTE: if you install Nix with the Determinate Systems installer, Determinate
  # manages the daemon itself — in that case set `nix.enable = false;` here so
  # nix-darwin doesn't fight it. With the upstream/nix-darwin-managed daemon,
  # leave this as-is.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  nixpkgs.config.allowUnfree = true;

  # Let nix-darwin manage the login shell so the Nix env is sourced in zsh.
  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  # Declarative Homebrew. nix-darwin runs `brew bundle` on activation; it does
  # NOT install Homebrew itself — install that once via https://brew.sh.
  #
  # cleanup = "none" is intentional: it will NOT uninstall anything you have
  # installed manually but haven't listed here. Switch to "uninstall" (or "zap")
  # once every formula/cask you want is declared and you want a fully managed,
  # reproducible brew state.
  homebrew = {
    enable = true;
    onActivation = {
      # Keep switches predictable: install what's declared, but don't run
      # `brew update` / mass-`brew upgrade` on every activation. Flip these on
      # once the brew state here is the source of truth.
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    taps = [
      "aprilnea/tap"
      "axiomhq/tap"
      "codecrafters-io/tap"
      "libsql/sqld"
      "minio/stable"
      "planetscale/tap"
      "rhettbull/osxphotos"
      "steipete/tap"
      "tursodatabase/tap"
      "twitchdev/twitch"
    ];

    # GUI apps — the high-value reproducible bits.
    casks = [
      "android-commandlinetools"
      "android-platform-tools"
      "axiom"
      "expo-orbit"
      "gstreamer-runtime"
      "orbstack"
      "retroarch"
      "swiftformat-for-xcode"

      # Intentionally omitted (present on the MacBook, can't install on the mini):
      #   "codexbar"    — requires macOS Sonoma; mini is on macOS 26.
      #   "openlogi"    — requires macOS Ventura; mini is on macOS 26.
      #   "wine-stable" — Intel-only + deprecated + upstream download 404s.
    ];

    # CLI formulae. These can migrate to nix (home/luna.nix) over time; kept in
    # brew for now so the mac mini reproduces the current macbook toolchain.
    brews = [
      "act"
      "age"
      "btop"
      "bundletool"
      "clang-format"
      "cloudflared"
      "cmake"
      "cocoapods"
      "coreutils"
      "ddrescue"
      "difftastic"
      "dnsmasq"
      "gh"
      "git"
      "git-lfs"
      "glew"
      "glfw"
      "glslang"
      "go"
      "htop"
      "hugo"
      "i686-elf-grub"
      "jpeg"
      "jq"
      "libdvdcss"
      "libimobiledevice"
      "libpq"
      "librsvg"
      "lima"
      "lld"
      "llvm@18"
      "mas"
      "md5sha1sum"
      "meson"
      "mkcert"
      "mkvtoolnix"
      "molten-vk"
      "mysql-client"
      "nano"
      "nixpacks"
      "nss"
      "nvm"
      "ollama"
      "parallel"
      "pkgconf"
      "protobuf"
      "python-setuptools"
      "python@3.10"
      "railway"
      "redis"
      "scrcpy"
      "sops"
      "sshpass"
      "tmux"
      "tree"
      "trufflehog"
      "vulkan-headers"
      "watchexec"
      "watchman"
      "websocat"
      "wget"
      "wireshark"
      "wrk"
      "yq"
      "yt-dlp"
    ];
  };

  # Sensible macOS defaults.
  system.defaults = {
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      # Fast key repeat, no press-and-hold accent popover (better for dev).
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      ApplePressAndHoldEnabled = false;
    };
    finder = {
      FXPreferredViewStyle = "Nlsv"; # list view
      ShowPathbar = true;
    };
    dock = {
      autohide = true;
      show-recents = false;
      mru-spaces = false;
    };
  };

  # Home-manager: user dotfiles (zsh, aliases, git, …) live in home/common.nix,
  # wired to the right account in darwin/<host>/default.nix.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    # On a machine with pre-existing dotfiles (e.g. the mini's old ~/.zshrc),
    # move them aside instead of aborting activation.
    backupFileExtension = "hm-backup";
  };

  # Used for backwards compatibility. Read the nix-darwin changelog before
  # changing: https://github.com/nix-darwin/nix-darwin/blob/master/CHANGELOG
  system.stateVersion = 6;
}
