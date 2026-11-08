#!/usr/bin/env python3
"""Push an exact Git revision over SSH, build on the target, then activate it."""
import argparse
import pathlib
import re
import shlex
import subprocess
import tempfile

HOSTS = {
    "nova": "luna@nova", "gilbert": "luna@gilbert", "void": "luna@void",
    "lake": "luna@lake", "gateway": "luna@23.150.68.231",
    "pulsar": "xo@pulsar", "comet": "luna@comet",
}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", choices=HOSTS)
    parser.add_argument("--target", help="Override user@hostname SSH destination")
    parser.add_argument("--revision", default="HEAD", help="Committed Git revision (default HEAD)")
    parser.add_argument("--build-only", action="store_true", help="Build without activation")
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parent.parent
    target = args.target or HOSTS[args.host]
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.@:-]*", target):
        parser.error("Invalid SSH target")
    sha = subprocess.check_output(
        ["git", "rev-parse", "--verify", "--end-of-options", args.revision + "^{commit}"],
        cwd=repo, text=True,
    ).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=repo, text=True)
    if dirty:
        parser.error("Commit or stash local changes first; deployments use committed files only")
    # Use a fresh directory even for repeated deployments of the same revision.
    base = ".local/state/nixos-configs/releases"
    remote = subprocess.check_output(
        ["ssh", target, f"umask 077; mkdir -p {base}; mktemp -d {base}/{sha}.XXXXXX"],
        text=True,
    ).strip()
    if not re.fullmatch(re.escape(base + "/" + sha + ".") + r"[A-Za-z0-9]+", remote):
        raise RuntimeError("Unexpected remote release path")
    print(f"Deploying {sha} to {args.host} ({target})", flush=True)
    tree = f"{sha}:machines/gateway" if args.host == "gateway" else sha
    with tempfile.TemporaryDirectory(prefix="nixos-deploy-") as temporary:
        archive = pathlib.Path(temporary) / "source.tar"
        run("git", "archive", "--format=tar", "-o", str(archive), tree, cwd=repo)
        run("scp", str(archive), f"{target}:{remote}/source.tar")
    run("ssh", target, f"tar -xf {remote}/source.tar -C {remote} && rm {remote}/source.tar")
    tool = "darwin-rebuild" if args.host in {"pulsar", "comet"} else "nixos-rebuild"
    # Hosts resolve only pinned inputs. No git pull, --refresh, input overrides,
    # automatic dependency updates, automatic reboot, or unreviewed branch tip.
    shell = f'''set -eu
export PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin
cd {shlex.quote(remote)}
sudo {tool} build --flake "$PWD#{args.host}" --no-write-lock-file
'''
    if not args.build_only:
        shell += f'''sudo {tool} switch --flake "$PWD#{args.host}" --no-write-lock-file
printf '%s\\n' "$PWD" > "$HOME/.local/state/nixos-configs/last-deployment"
'''
    # A terminal allows sudo to prompt on Macs; source transfer is already done.
    run("ssh", "-t", target, "sh -c " + shlex.quote(shell))
    print(f"{'Built' if args.build_only else 'Activated'} {sha} on {args.host}")


if __name__ == "__main__":
    main()
