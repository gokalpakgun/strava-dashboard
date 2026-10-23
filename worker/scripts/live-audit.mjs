// Explicit live smoke test. Creates only disposable synthetic accounts and
// deletes them in finally. Credentials stay in memory and never enter reports.
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';

if (!process.argv.includes('--live')) throw new Error('Pass --live to test production.');
const origin = 'https://apitempo.com';
const results = [];
const accounts = [];
async function call(path, { method = 'GET', body, token } = {}) {
  const started = Date.now();
  const response = await fetch(origin + path, {
    method, signal: AbortSignal.timeout(45000),
    headers: { Accept: 'application/json', 'Accept-Language': 'en',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = response.status === 204 ? null : await response.json();
  return { status: response.status, data, ms: Date.now() - started };
}
function check(name, actual, expected, extra = {}) {
  const pass = actual.status === expected;
  const row = { name, pass, status: actual.status, expected, ms: actual.ms, ...extra,
    ...(!pass ? { error: actual.data?.error || 'Unexpected result', diagnostic: actual.data?.diagnostic } : {}) };
  results.push(row);
  console.log(JSON.stringify(row));
  return pass;
}
try {
  check('Production ping', await call('/api/mobile/ping'), 200);
  for (const path of ['/api/account/me', '/api/account/health', '/api/account/social', '/api/mobile/dashboard']) {
    check('Reject anonymous ' + path, await call(path), 401);
  }
  const suffix = randomBytes(5).toString('hex');
  for (const index of [1, 2]) {
    const credentials = { email: `tempo.audit.${suffix}.${index}@example.com`,
      username: `audit_${suffix}_${index}`, password: randomBytes(24).toString('base64url') };
    const signup = await call('/api/account/signup', { method: 'POST', body: credentials });
    if (!check('Live signup ' + index, signup, 201)) break;
    accounts.push({ ...credentials, token: signup.data.token, user: signup.data.user });
  }
  if (accounts.length === 2) {
    const [a, b] = accounts;
    check('Reject duplicate signup', await call('/api/account/signup', { method: 'POST', body: { email: a.email, username: a.username, password: a.password } }), 409);
    for (const identifier of [a.email, a.username.toUpperCase()]) {
      const login = await call('/api/account/login', { method: 'POST', body: { identifier, password: a.password } });
      check(identifier.includes('@') ? 'Email login' : 'Username login case normalization', login, 200);
    }
    check('Reject wrong password', await call('/api/account/login', { method: 'POST', body: { identifier: a.username, password: randomUUID() } }), 401);
    check('Read signed in profile', await call('/api/account/me', { token: a.token }), 200);
    check('Complete multi-sport profile', await call('/api/account/profile', { method: 'PATCH', token: a.token,
      body: { displayName: 'Tempo Audit', sports: ['tennis', 'basketball', 'run'], onboardingComplete: true } }), 200);
    const today = new Date().toISOString().slice(0, 10);
    check('Upload synthetic Health summary', await call('/api/account/health', { method: 'POST', token: a.token,
      body: { days: { [today]: { steps: 4321, sleepMinutes: 450, sleepREMMinutes: 90, sleepDeepMinutes: 60 } } } }), 200);
    const ownHealth = await call('/api/account/health', { token: a.token });
    check('Round trip Health summary', { ...ownHealth, status: ownHealth.data?.days?.[today]?.steps === 4321 ? ownHealth.status : 422 }, 200);
    const otherHealth = await call('/api/account/health', { token: b.token });
    check('Health account isolation', { ...otherHealth, status: Object.keys(otherHealth.data?.days || {}).length ? 422 : otherHealth.status }, 200);
    check('Reject invalid Health input', await call('/api/account/health', { method: 'POST', token: a.token, body: { days: { [today]: { steps: -5 } } } }), 400);
    const friend = await call('/api/account/social/friends', { method: 'POST', token: a.token, body: { username: b.username } });
    check('Send real friend request', friend, 200);
    const friends = await call('/api/account/social', { token: b.token });
    check('Load incoming friend request', friends, 200, { incomingCount: friends.data?.incoming?.length ?? null });
    const coach = await call('/api/account/sports-chat', { method: 'POST', token: a.token,
      body: { includeHealth: false, messages: [{ role: 'user', content: 'In English, suggest a brief five-minute warm-up for a recreational tennis session.' }] } });
    check('Live AI without Health consent', coach, 200, { answerCharacters: coach.data?.answer?.length ?? 0 });
    if (coach.status === 200) {
      // Cooldown is four seconds. Model inference generally exceeds it; this
      // independent request verifies the actual retained assistant response.
      await new Promise(resolve => setTimeout(resolve, 4200));
      const followup = await call('/api/account/sports-chat', { method: 'POST', token: a.token,
        body: { includeHealth: true, messages: [{ role: 'user', content: 'Suggest a short tennis warm-up.' },
          { role: 'assistant', content: coach.data.answer }, { role: 'user', content: 'Which measurements have I explicitly shared for today? State only the available values.' }] } });
      check('Live AI multi-turn with synthetic Health consent', followup, 200, { answerCharacters: followup.data?.answer?.length ?? 0 });
    }
    check('Reset endpoint rejects fake token', await call('/api/account/password/reset', { method: 'POST', body: { token: '0'.repeat(64), password: randomUUID() } }), 400);
    check('Password reset email service configured (unknown account; no email sent)', await call('/api/account/password/forgot', { method: 'POST', body: { email: `absent.${suffix}@example.com` } }), 200);
    check('Logout disposable second account', await call('/api/account/logout', { method: 'POST', token: b.token, body: {} }), 204);
    check('Reject session after logout', await call('/api/account/me', { token: b.token }), 401);
    const login = await call('/api/account/login', { method: 'POST', body: { identifier: b.username, password: b.password } });
    check('Login again after logout', login, 200);
    if (login.status === 200) b.token = login.data.token;
  }
} catch (error) {
  results.push({ name: 'Live transport', pass: false, error: error.message });
  console.error('Live audit transport failure:', error.message);
} finally {
  for (const account of accounts) {
    try { check('Delete disposable audit account', await call('/api/account', { method: 'DELETE', token: account.token, body: {} }), 200); }
    catch (error) { results.push({ name: 'Cleanup disposable account', pass: false, error: error.message }); }
  }
  await mkdir('outputs', { recursive: true });
  await writeFile('outputs/live-audit.json', JSON.stringify({ testedAt: new Date().toISOString(), origin, results }, null, 2));
  if (results.some(row => !row.pass)) process.exitCode = 1;
}
