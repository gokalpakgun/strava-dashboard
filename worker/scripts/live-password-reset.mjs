// Explicit, disposable live reset test. Never changes a person's account.
// Secrets remain in a git-ignored local state file and are never printed.
import { randomBytes } from 'node:crypto';
import { readFile, writeFile, unlink, mkdir } from 'node:fs/promises';
const origin = 'https://apitempo.com';
const statePath = new URL('../.env.live-reset-test.json', import.meta.url);
const reportPath = new URL('../../outputs/live-password-reset.json', import.meta.url);
const mode = process.argv[2];
if (!['begin', 'finish', 'cleanup'].includes(mode) || !process.argv.includes('--live')) throw Error('Use begin|finish|cleanup --live.');
async function call(path, { body, token, method = 'POST' } = {}) {
  const response = await fetch(origin + path, { method, signal: AbortSignal.timeout(45000),
    headers: { 'Accept-Language': 'en', 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}) });
  return { status: response.status, data: response.status === 204 ? null : await response.json() };
}
let state;
async function save() { await writeFile(statePath, JSON.stringify(state), { mode: 0o600 }); }
function check(name, result, expected) {
  const row = { name, status: result.status, expected, pass: result.status === expected };
  state.results.push(row); console.log(JSON.stringify(row));
  if (!row.pass) throw Error(name + ' returned ' + result.status);
}
if (mode === 'begin') {
  try { await readFile(statePath); throw Error('A reset test already exists; finish or clean it first.'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const suffix = randomBytes(6).toString('hex');
  const mailbox = process.env.TEMPO_RESET_TEST_MAILBOX;
  if (!/^[A-Za-z0-9._-]+@gmail\.com$/.test(mailbox || '')) throw Error('Set TEMPO_RESET_TEST_MAILBOX to a controlled Gmail inbox; only a disposable plus alias is used.');
  state = { email: mailbox.replace('@', '+tempoaudit' + suffix + '@'), username: 'reset_' + suffix,
    password: randomBytes(24).toString('base64url'), results: [] };
  const signup = await call('/api/account/signup', { body: { email: state.email, username: state.username, password: state.password } });
  check('Disposable email account registration', signup, 201);
  state.token = signup.data.token;
  await save();
  const email = await call('/api/account/password/forgot', { body: { email: state.email } });
  check('Real password-reset email accepted', email, 200);
  await save();
  console.log('Reset email requested for the disposable Gmail alias; verify delivery in Resend.');
} else {
  state = JSON.parse(await readFile(statePath, 'utf8'));
  if (mode === 'finish') {
    if (!state.resetLink) throw Error('Add the delivered reset link to the ignored state file first.');
    const link = new URL(state.resetLink);
    if (link.origin !== origin || link.pathname !== '/reset-password') throw Error('Unexpected reset origin.');
    const resetToken = link.searchParams.get('token');
    const page = await fetch(link, { signal: AbortSignal.timeout(15000) });
    const html = await page.text();
    check('Delivered reset page opens in English', { status: page.ok && html.includes('lang="en"') ? 200 : 422 }, 200);
    state.newPassword = randomBytes(24).toString('base64url');
    await save();
    check('Delivered token changes only the disposable password', await call('/api/account/password/reset', { body: { token: resetToken, password: state.newPassword } }), 200);
    check('Pre-reset session rejected', await call('/api/account/me', { method: 'GET', token: state.token }), 401);
    check('Old password rejected', await call('/api/account/login', { body: { identifier: state.email, password: state.password } }), 401);
    const login = await call('/api/account/login', { body: { identifier: state.email, password: state.newPassword } });
    check('New password signs in', login, 200);
    state.token = login.data.token; await save();
    check('Used delivered token cannot be reused', await call('/api/account/password/reset', { body: { token: resetToken, password: randomBytes(24).toString('base64url') } }), 400);
    if (state.previousResetLink) {
      const previous = new URL(state.previousResetLink);
      check('Earlier delivered reset link also revoked', await call('/api/account/password/reset', { body: { token: previous.searchParams.get('token'), password: randomBytes(24).toString('base64url') } }), 400);
    }
    check('Delete disposable email test account', await call('/api/account', { method: 'DELETE', token: state.token, body: {} }), 200);
    await mkdir(new URL('../../outputs/', import.meta.url), { recursive: true });
    await writeFile(reportPath, JSON.stringify({ timestamp: new Date().toISOString(), results: state.results }, null, 2));
    await unlink(statePath);
  } else {
    const login = await call('/api/account/login', { body: { identifier: state.email, password: state.newPassword || state.password } });
    if (login.status === 200) state.token = login.data.token;
    check('Delete disposable email test account', await call('/api/account', { method: 'DELETE', token: state.token, body: {} }), 200);
    await unlink(statePath);
  }
}
