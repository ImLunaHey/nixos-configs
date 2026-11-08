#!/usr/bin/env python3
"""Apply the managed Pocket ID login branding while Jellyfin is stopped."""
import argparse
import ipaddress
import os
import re
from pathlib import Path
import shutil
import tempfile
import xml.etree.ElementTree as ET


def update_xml(path, fields, backup_dir):
    tree = ET.parse(path)
    root = tree.getroot()
    changed = False
    for name, value in fields.items():
        node = root.find(name)
        if isinstance(value, list):
            current = [] if node is None else [child.text for child in node]
        else:
            current = None if node is None else node.text
        if current == value:
            continue
        changed = True
        if node is None:
            node = ET.SubElement(root, name)
        if isinstance(value, list):
            node.clear()
            for item in value:
                ET.SubElement(node, "string").text = item
        else:
            node.text = value
    if not changed:
        return
    backup_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=path.name + ".", dir=backup_dir, delete=False) as backup:
        with path.open("rb") as source:
            shutil.copyfileobj(source, backup)
    stat = path.stat()
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            tree.write(output, encoding="utf-8", xml_declaration=True)
        os.chown(temporary, stat.st_uid, stat.st_gid)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--html", type=Path, required=True)
    parser.add_argument("--css", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=Path("/var/lib/jellyfin/config/config"))
    parser.add_argument("--backups", type=Path, default=Path("/var/backups/jellyfin/login-config"))
    parser.add_argument("--proxy-address", action="append", default=["127.0.0.1", "::1"])
    args = parser.parse_args()
    proxies = [str(ipaddress.ip_address(address)) for address in args.proxy_address]
    branding = ET.parse(args.config / "branding.xml").getroot()
    existing_css = branding.findtext("CustomCss") or ""
    existing_css = re.sub(r"/\* flaked-login:start \*/.*?/\* flaked-login:end \*/", "", existing_css, flags=re.S).rstrip()
    managed_css = existing_css + "\n/* flaked-login:start */\n" + args.css.read_text().rstrip() + "\n/* flaked-login:end */\n"
    update_xml(args.config / "branding.xml", {
        "LoginDisclaimer": args.html.read_text(), "CustomCss": managed_css,
    }, args.backups)
    # Docker translates the host's loopback connection to its bridge gateway.
    # Trust that exact address, never an entire private subnet.
    update_xml(args.config / "network.xml", {"KnownProxies": proxies}, args.backups)


if __name__ == "__main__":
    main()
