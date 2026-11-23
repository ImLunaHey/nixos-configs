// Reconcile the default grant before Tailscale exposes the board. Preserve
// grants people create separately; g1 is the explicitly managed access list.
import { execFileSync } from 'node:child_process';
const [cli, ...logins] = process.argv.slice(2);
const run = (...args) => execFileSync(cli, args, { encoding: 'utf8' });
const { grants } = JSON.parse(run('grants', '--json'));
const grant = grants.find(({ id }) => id === 'g1');
if (!grant) throw new Error('Managed grant g1 is missing');
const desired = new Set(['board', ...logins]);
const existing = new Set();
const args = ['grants', 'update', 'g1'];
for (const principal of grant.principals) {
  if (principal.kind === 'all-users') args.push('--remove-all-users');
  else if (principal.kind === 'user') {
    existing.add(principal.userId);
    if (!desired.has(principal.userId)) args.push('--remove-user', principal.userId);
  } else throw new Error('Unexpected principal in managed grant g1');
}
for (const login of desired) if (!existing.has(login)) args.push('--add-user', login);
run(...args, '--can', '*=all');
for (const channel of ['nixos-configs', 'fleet-monitor', 'homelab']) {
  run('channels', 'create', channel);
}
console.log('Board access and channels configured');
