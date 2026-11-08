#!/usr/bin/env python3
"""Plan/apply NetBird access inventory; stage replacements before retiring rules."""
import argparse
import copy
import json
import os
from pathlib import Path
import urllib.request

PREFIX = 'nixos:'


def ids(values):
    return sorted(v['id'] if isinstance(v, dict) else v for v in (values or []))


def policy_body(policy):
    result = {k: policy[k] for k in ('name', 'description', 'enabled', 'rules')}
    result = copy.deepcopy(result)
    result['source_posture_checks'] = ids(policy.get('source_posture_checks'))
    for rule in result['rules']:
        rule.pop('id', None)
        rule['description'] = rule.get('description', '')
        for field in ('sources', 'destinations', 'ports'):
            rule[field] = ids(rule.get(field))
    return result


def desired_policies(manifest, groups):
    result = []
    for policy in manifest['policies']:
        body = copy.deepcopy(policy)
        for rule in body['rules']:
            for field in ('sources', 'destinations'):
                rule[field] = [groups[name]['id'] for name in rule[field]]
        result.append(policy_body(body))
    return result


def validate(manifest, state):
    groups = {g['name']: g for g in state['groups']}
    peers = {p['id']: p for p in state['peers']}
    if len(groups) != len(state['groups']):
        raise ValueError('Duplicate group names; resolve ambiguity first')
    for alias, expected in manifest['peers'].items():
        if expected['id'] not in peers or peers[expected['id']]['ip'] != expected['ip']:
            raise ValueError('Peer identity/address mismatch: ' + alias)
        if peers[expected['id']].get('ephemeral', False):
            raise ValueError('Static infrastructure/admin peer must not be ephemeral: ' + alias)
    for name, members in manifest['groups'].items():
        if not name.startswith(PREFIX):
            raise ValueError('Managed groups must use nixos: prefix')
        if any(alias not in manifest['peers'] for alias in members):
            raise ValueError('Unknown peer in group: ' + name)
        if name in groups and groups[name].get('resources'):
            raise ValueError('Managed peer group has unexpected network resources: ' + name)
    for name in manifest['externalGroups']:
        if name not in groups:
            raise ValueError('Missing enrolment group: ' + name)
    desired_names = [p['name'] for p in manifest['policies']]
    if len(set(desired_names)) != len(desired_names) or not all(n.startswith(PREFIX) for n in desired_names):
        raise ValueError('Invalid or duplicate policy names')
    live_names = [p['name'] for p in state['policies']]
    if len(set(live_names)) != len(live_names):
        raise ValueError('Duplicate live policy names')
    known_groups = set(manifest['groups']) | set(manifest['externalGroups'])
    for policy in manifest['policies']:
        if len(policy['rules']) != 1:
            raise ValueError('This NetBird server supports one rule per policy')
        for rule in policy['rules']:
            if not set(rule['sources'] + rule['destinations']) <= known_groups:
                raise ValueError('Unknown rule group')
            if rule['action'] != 'accept' or rule['protocol'] not in ('all', 'icmp', 'tcp', 'udp'):
                raise ValueError('Unsupported rule')
    for policy in state['policies']:
        if policy['id'] in manifest['retire']:
            if policy['name'] != manifest['retire'][policy['id']]:
                raise ValueError('Legacy policy identity changed: ' + policy['id'])
        elif policy['name'] not in desired_names and policy['enabled']:
            raise ValueError('Unmanaged enabled policy requires review: ' + policy['name'])
    # Never let login propagation or a setup key grant elevated static membership.
    static_ids = {groups[n]['id'] for n in manifest['groups'] if n in groups}
    for owner in state['users'] + state['setup-keys']:
        if static_ids.intersection(owner.get('auto_groups') or []):
            raise ValueError('A user/setup key automatically grants a managed static group')
    user = next(u for u in state['users'] if u['id'] == manifest['personalUser'])
    expected = sorted(groups[n]['id'] for n in manifest['personalAutoGroups'])
    if sorted(user.get('auto_groups') or []) != expected:
        raise ValueError('Personal user automatic groups differ from the reviewed inventory')


def snapshot(path, manifest, state):
    # Setup-key API responses contain credentials: retain only the group/policy
    # data necessary for rollback, never API tokens or setup-key responses.
    data = {key: state[key] for key in ('groups', 'policies')}
    data['managed_groups'] = list(manifest['groups'])
    data['managed_policies'] = [p['name'] for p in manifest['policies']]
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
        json.dump(data, stream, indent=2)


def reconcile(manifest, state, api, apply=False, phase='prepare'):
    validate(manifest, state)
    groups = {g['name']: g for g in state['groups']}
    changes = 0
    for name, aliases in manifest['groups'].items():
        desired = {'name': name, 'peers': sorted(manifest['peers'][a]['id'] for a in aliases), 'resources': []}
        current = groups.get(name)
        if current is None or ids(current.get('peers')) != desired['peers']:
            changes += 1
            print(('Create' if current is None else 'Update') + ' group: ' + name)
            if apply:
                groups[name] = api('groups' + ('/' + current['id'] if current else ''),
                                   'PUT' if current else 'POST', desired)
            elif current is None:
                groups[name] = {'id': 'planned:' + name}
    current_policies = {p['name']: p for p in state['policies']}
    for desired in desired_policies(manifest, groups):
        current = current_policies.get(desired['name'])
        if current is None or policy_body(current) != desired:
            changes += 1
            print(('Create' if current is None else 'Update') + ' policy: ' + desired['name'])
            if apply:
                api('policies' + ('/' + current['id'] if current else ''),
                    'PUT' if current else 'POST', desired)
    if phase == 'enforce':
        # Read back replacements before withdrawing the existing grants.
        if apply:
            actual = {p['name']: policy_body(p) for p in api('policies')}
            for desired in desired_policies(manifest, groups):
                if actual.get(desired['name']) != desired:
                    raise ValueError('Replacement policy verification failed: ' + desired['name'])
        for policy in state['policies']:
            if policy['id'] in manifest['retire'] and policy['enabled']:
                changes += 1
                print('Disable legacy policy: ' + policy['name'])
                if apply:
                    api('policies/' + policy['id'], 'PUT', {**policy_body(policy), 'enabled': False})
    print(f'{changes} change(s)' + ('' if apply else ' planned; no writes'))
    return changes


def restore(saved, api):
    # Restore access first, then remove only objects created by this migration.
    live = {p['id']: p for p in api('policies')}
    original_ids = {p['id'] for p in saved['policies']}
    for policy in saved['policies']:
        if policy['id'] not in live:
            raise ValueError('Original policy missing; manual recovery required')
        if policy_body(live[policy['id']]) != policy_body(policy):
            api('policies/' + policy['id'], 'PUT', policy_body(policy))
    for policy in live.values():
        if policy['id'] not in original_ids and policy['name'] in saved['managed_policies']:
            api('policies/' + policy['id'], 'DELETE')
    originals = {g['name']: g for g in saved['groups']}
    for group in api('groups'):
        if group['name'] not in saved['managed_groups']:
            continue
        original = originals.get(group['name'])
        if original is None:
            api('groups/' + group['id'], 'DELETE')
        else:
            api('groups/' + group['id'], 'PUT', {'name': original['name'],
                'peers': ids(original.get('peers')), 'resources': original.get('resources') or []})
    print('Restored saved policies and managed static groups; enrolment groups untouched')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--token-file', required=True, type=Path)
    parser.add_argument('--phase', choices=['prepare', 'enforce'], default='prepare')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--snapshot', type=Path, help='New private rollback file, required with --apply')
    parser.add_argument('--restore', type=Path, help='Restore a snapshot instead of applying a manifest')
    args = parser.parse_args()
    token = args.token_file.read_text().strip()

    def api(path, method='GET', payload=None):
        request = urllib.request.Request('https://netbird.flaked.org/api/' + path,
            method=method, data=json.dumps(payload).encode() if payload is not None else None,
            headers={'Authorization': 'Token ' + token, 'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else None

    if args.restore:
        if not args.apply:
            parser.error('--restore requires --apply')
        restore(json.loads(args.restore.read_text()), api)
        return
    if not args.manifest or (args.apply and not args.snapshot):
        parser.error('--manifest required; --apply also requires --snapshot')
    manifest = json.loads(args.manifest.read_text())
    state = {path: api(path) for path in ('groups', 'policies', 'peers', 'users', 'setup-keys')}
    validate(manifest, state)
    if args.apply:
        snapshot(args.snapshot, manifest, state)
    reconcile(manifest, state, api, args.apply, args.phase)


if __name__ == '__main__':
    main()
