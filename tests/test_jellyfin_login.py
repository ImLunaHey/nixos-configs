import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location(
    "login", Path(__file__).parents[1] / "scripts/configure-jellyfin-login.py"
)
login = importlib.util.module_from_spec(spec)
spec.loader.exec_module(login)


class LoginConfigurationTests(unittest.TestCase):
    def test_full_update_preserves_custom_css_and_trusts_only_exact_proxy_addresses(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "branding.xml").write_text('<BrandingConfiguration><CustomCss>.keep { color: red; }</CustomCss></BrandingConfiguration>')
            (root / "network.xml").write_text('<NetworkConfiguration><Other>keep</Other></NetworkConfiguration>')
            (root / "login.html").write_text('<section>Sign in</section>')
            (root / "login.css").write_text('.flaked-login { color: green; }')
            args = ['configure-login', '--html', str(root / 'login.html'), '--css', str(root / 'login.css'), '--config', str(root), '--backups', str(root / 'backups'), '--proxy-address', '172.20.0.1']
            with patch('sys.argv', args):
                login.main()
                first = (root / 'branding.xml').read_bytes()
                login.main()
            self.assertEqual(first, (root / 'branding.xml').read_bytes())
            css = ET.parse(root / 'branding.xml').findtext('CustomCss')
            self.assertIn('.keep { color: red; }', css)
            self.assertEqual(css.count('flaked-login:start'), 1)
            self.assertEqual([x.text for x in ET.parse(root / 'network.xml').findall('KnownProxies/string')], ['127.0.0.1', '::1', '172.20.0.1'])

    def test_preserves_other_settings_and_backs_up_only_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "branding.xml"
            original = b'<BrandingConfiguration><Other>keep</Other><LoginDisclaimer>old</LoginDisclaimer></BrandingConfiguration>'
            config.write_bytes(original)
            backup = root / "backups"
            fields = {"LoginDisclaimer": '<a href="/sso/OID/start/pocketid">Sign in</a>'}
            login.update_xml(config, fields, backup)
            saved = ET.parse(config).getroot()
            self.assertEqual(saved.findtext("Other"), "keep")
            self.assertEqual(saved.findtext("LoginDisclaimer"), fields["LoginDisclaimer"])
            self.assertEqual(next(backup.iterdir()).read_bytes(), original)
            self.assertEqual(config.stat().st_mode & 0o777, 0o600)
            first = config.read_bytes()
            login.update_xml(config, fields, backup)
            self.assertEqual(config.read_bytes(), first)
            self.assertEqual(len(list(backup.iterdir())), 1)

    def test_proxy_allowlist_replaces_broad_trust_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "network.xml"
            config.write_text('<NetworkConfiguration><KnownProxies><string>0.0.0.0/0</string></KnownProxies></NetworkConfiguration>')
            fields = {"KnownProxies": ["127.0.0.1", "::1"]}
            login.update_xml(config, fields, root / "backups")
            self.assertEqual([x.text for x in ET.parse(config).findall("KnownProxies/string")], fields["KnownProxies"])
            first = config.read_bytes()
            login.update_xml(config, fields, root / "backups")
            self.assertEqual(config.read_bytes(), first)


if __name__ == "__main__":
    unittest.main()
