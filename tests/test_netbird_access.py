import copy
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('access', Path(__file__).parents[1] / 'scripts/sync-netbird-access.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)


class AccessTests(unittest.TestCase):
    def setUp(self):
        self.manifest = {
            'peers': {'admin': {'id': 'peer-a', 'ip': '100.66.0.1'}},
            'groups': {'nixos:admins': ['admin']},
            'externalGroups': ['personal-devices'],
            'personalUser': 'user', 'personalAutoGroups': ['personal-devices'],
            'policies': [{'name': 'nixos:access', 'description': 'test', 'enabled': True,
                          'rules': [{'name': 'https', 'enabled': True, 'action': 'accept',
                                     'bidirectional': False, 'protocol': 'tcp', 'ports': ['443'],
                                     'sources': ['nixos:admins'], 'destinations': ['personal-devices']}]}],
            'retire': {'old': 'Legacy'},
        }
        self.state = {'groups': [{'id': 'personal', 'name': 'personal-devices', 'peers': []}],
                      'peers': [{'id': 'peer-a', 'ip': '100.66.0.1'}],
                      'users': [{'id': 'user', 'auto_groups': ['personal']}], 'setup-keys': [],
                      'policies': [{'id': 'old', 'name': 'Legacy', 'description': '', 'enabled': True, 'rules': []}]}
        self.writes = []

    def api(self, path, method='GET', payload=None):
        kind, _, identity = path.partition('/')
        if method == 'GET':
            return copy.deepcopy(self.state[kind])
        self.writes.append((path, method))
        if method == 'POST':
            obj = {**copy.deepcopy(payload), 'id': 'new-' + str(len(self.writes))}
            self.state[kind].append(obj)
            return obj
        obj = next(x for x in self.state[kind] if x['id'] == identity)
        if method == 'DELETE':
            self.state[kind].remove(obj)
            return None
        obj.update(copy.deepcopy(payload))
        return obj

    def test_prepares_before_disabling_and_is_idempotent(self):
        a.reconcile(self.manifest, copy.deepcopy(self.state), self.api, True, 'prepare')
        self.assertTrue(self.state['policies'][0]['enabled'])
        self.writes.clear()
        a.reconcile(self.manifest, copy.deepcopy(self.state), self.api, True, 'enforce')
        self.assertEqual(self.writes, [('policies/old', 'PUT')])
        self.writes.clear()
        self.assertEqual(a.reconcile(self.manifest, copy.deepcopy(self.state), self.api, True, 'enforce'), 0)
        self.assertEqual(self.writes, [])
        self.assertEqual(self.state['groups'][0]['peers'], [])

    def test_plan_has_no_writes(self):
        a.reconcile(self.manifest, copy.deepcopy(self.state), self.api)
        self.assertEqual(self.writes, [])

    def test_refuses_unreviewed_policy_and_identity_drift(self):
        self.state['policies'].append({'id': 'unknown', 'name': 'Unknown', 'enabled': True})
        with self.assertRaises(ValueError):
            a.reconcile(self.manifest, self.state, self.api, True)
        self.state['policies'].pop()
        self.state['peers'][0]['ip'] = '100.66.0.2'
        with self.assertRaises(ValueError):
            a.reconcile(self.manifest, self.state, self.api, True)
        self.assertEqual(self.writes, [])

    def test_refuses_automatic_administrator_membership(self):
        self.state['groups'].append({'name': 'nixos:admins', 'id': 'admins', 'peers': []})
        self.state['setup-keys'].append({'auto_groups': ['admins']})
        with self.assertRaises(ValueError):
            a.reconcile(self.manifest, self.state, self.api, True)
        self.assertEqual(self.writes, [])

    def test_refuses_ephemeral_static_peers(self):
        self.state['peers'][0]['ephemeral'] = True
        with self.assertRaises(ValueError):
            a.reconcile(self.manifest, self.state, self.api, True)
        self.assertEqual(self.writes, [])

    def test_refuses_multiple_rules_that_server_would_truncate(self):
        self.manifest['policies'][0]['rules'] *= 2
        with self.assertRaises(ValueError):
            a.reconcile(self.manifest, self.state, self.api, True)
        self.assertEqual(self.writes, [])

    def test_readback_failure_keeps_legacy_access(self):
        def broken_api(path, method='GET', payload=None):
            if method == 'GET' and path == 'policies':
                return []
            return self.api(path, method, payload)
        with self.assertRaises(ValueError):
            a.reconcile(self.manifest, copy.deepcopy(self.state), broken_api, True, 'enforce')
        self.assertTrue(self.state['policies'][0]['enabled'])

    def test_restore_reenables_old_policy_before_removing_new(self):
        saved = copy.deepcopy(self.state)
        saved.update(managed_groups=list(self.manifest['groups']), managed_policies=['nixos:access'])
        a.reconcile(self.manifest, copy.deepcopy(self.state), self.api, True, 'enforce')
        self.writes.clear()
        a.restore(saved, self.api)
        self.assertEqual(self.writes[0], ('policies/old', 'PUT'))
        self.assertTrue(self.state['policies'][0]['enabled'])
        self.assertEqual(len(self.state['groups']), 1)
        self.assertEqual(len(self.state['policies']), 1)


if __name__ == '__main__':
    unittest.main()
