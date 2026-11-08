#!/usr/bin/env python3
"""Apply evaluated infrastructure/netbird-dns.nix to exact-name NetBird zones."""
import argparse
import ipaddress
import json
from pathlib import Path
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--token-file', required=True, type=Path)
    parser.add_argument('--apply', action='store_true', help='Write changes; default is a plan')
    args = parser.parse_args()
    token = args.token_file.read_text().strip()

    def api(path, method='GET', payload=None):
        request = urllib.request.Request(
            'https://netbird.flaked.org/api/' + path,
            data=json.dumps(payload).encode() if payload is not None else None,
            method=method,
            headers={'Authorization': 'Token ' + token, 'Content-Type': 'application/json'},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    groups = {g['name']: g['id'] for g in api('groups')}
    zones = {z['domain']: z for z in api('dns/zones')}
    services = json.loads(args.manifest.read_text())['services']
    # Validate the entire plan before writing anything. Existing unrelated zones
    # must be imported/reviewed explicitly, never silently taken over.
    for service in services:
        domain = service['domain']
        ipaddress.IPv4Address(service['address'])
        for group in service['groups']:
            if group not in groups:
                raise SystemExit('Missing NetBird group: ' + group)
        if domain in zones and zones[domain]['name'] != 'nixos:' + domain:
            raise SystemExit('Refusing to take over unmanaged zone: ' + domain)

    for service in services:
        domain = service['domain']
        desired = {'name': 'nixos:' + domain, 'domain': domain, 'enabled': True,
                   'enable_search_domain': False,
                   'distribution_groups': sorted(groups[g] for g in service['groups'])}
        record = {'name': domain, 'type': 'A', 'content': service['address'], 'ttl': 60}
        zone = zones.get(domain)
        print(f'{domain} -> {service["address"]} ({", ".join(service["groups"])})')
        if not args.apply:
            continue
        if zone is None:
            zone = api('dns/zones', 'POST', {**desired, 'enabled': False})
        path = 'dns/zones/' + zone['id']
        records = api(path + '/records')
        matching = [r for r in records if r['name'].rstrip('.') == domain and r['type'] == 'A']
        if len(records) != len(matching) or len(matching) > 1:
            raise SystemExit('Unexpected records in owned zone; inspect before changing: ' + domain)
        if not matching:
            api(path + '/records', 'POST', record)
        elif any(matching[0].get(k) != v for k, v in record.items()):
            api(path + '/records/' + matching[0]['id'], 'PUT', record)
        current = {k: zone.get(k) for k in desired}
        current['distribution_groups'] = sorted(current['distribution_groups'] or [])
        if current != desired:
            api(path, 'PUT', desired)
    desired_domains = {s['domain'] for s in services}
    for domain, zone in zones.items():
        if zone['name'].startswith('nixos:') and domain not in desired_domains:
            print('Stale owned zone requires explicit removal: ' + domain)


if __name__ == '__main__':
    main()
