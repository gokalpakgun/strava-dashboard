import assert from "node:assert/strict";
import test from "node:test";
import { webcrypto } from "node:crypto";
import { handleAccountRequest, handlePasswordResetPage } from "../src/account.js";

globalThis.crypto ||= webcrypto;

class MemoryKV {
  values = new Map();
  writes = new Map();
  expirations = new Map();
  now = Date.now();
  async get(key, type) {
    if (this.expirations.has(key) && this.expirations.get(key) <= this.now) await this.delete(key);
    const value = this.values.get(key);
    return value === undefined ? null : type === "json" ? JSON.parse(value) : value;
  }
  async put(key, value, options = {}) {
    this.values.set(key, String(value));
    this.writes.set(key, (this.writes.get(key) || 0) + 1);
    if (options.expirationTtl !== undefined) this.expirations.set(key, this.now + options.expirationTtl * 1000);
    else this.expirations.delete(key);
  }
  async delete(key) { this.values.delete(key); this.expirations.delete(key); }
  async list({ prefix = "" } = {}) {
    for (const [key, expiry] of this.expirations) if (expiry <= this.now) await this.delete(key);
    return { keys: [...this.values.keys()].filter(key => key.startsWith(prefix)).map(name => ({ name })), list_complete: true };
  }
}

const password = "AccountAuditPass123";
function environment() {
  return { TOKEN_STORE: new MemoryKV(), AUTH_PEPPER: "local-test-only-pepper-with-at-least-32-characters", AI: { run: async () => ({ response: "safe" }) } };
}
function request(path, body, { token, method = "POST", headers = {} } = {}) {
  return new Request("https://apitempo.com" + path, {
    method,
    headers: { "CF-Connecting-IP": "192.0.2.81", ...(body ? { "Content-Type": "application/json" } : {}), ...(token ? { Authorization: "Bearer " + token } : {}), ...headers },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}
async function call(env, path, body, options) {
  const req = request(path, body, options);
  const response = await handleAccountRequest(req, env, new URL(req.url));
  return { response, data: response.status === 204 ? null : await response.json() };
}
async function signup(env) {
  const created = await call(env, "/api/account/signup", { email: " AccountAudit@Example.com ", username: " Account_Audit ", password });
  assert.equal(created.response.status, 201);
  return created.data;
}
async function hash(value) {
  return Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))).toString("hex");
}

test("account lifecycle: normalized signup, username/email login, onboarding, rename, logout and delete", async () => {
  const env = environment();
  const created = await signup(env);
  assert.equal(created.user.email, "accountaudit@example.com");
  assert.equal(created.user.username, "account_audit");
  assert.equal(created.user.passwordHash, undefined);
  for (const identifier of [" ACCOUNT_AUDIT ", " ACCOUNTAUDIT@EXAMPLE.COM "]) {
    const login = await call(env, "/api/account/login", { identifier, password });
    assert.equal(login.response.status, 200);
    assert.equal(login.data.user.id, created.user.id);
  }
  const invalidLogin = await call(env, "/api/account/login", { identifier: "account_audit", password: "IncorrectPass123" });
  assert.equal(invalidLogin.response.status, 401);
  const incomplete = await call(env, "/api/account/profile", { onboardingComplete: true }, { token: created.token, method: "PATCH" });
  assert.equal(incomplete.response.status, 400);
  const update = await call(env, "/api/account/profile", { displayName: "Account Tester", username: "renamed_audit", sports: ["tennis", "basketball", "run"], onboardingComplete: true }, { token: created.token, method: "PATCH" });
  assert.equal(update.response.status, 200);
  const oldLogin = await call(env, "/api/account/login", { identifier: "account_audit", password });
  assert.equal(oldLogin.response.status, 401);
  const renamedLogin = await call(env, "/api/account/login", { identifier: "renamed_audit", password });
  assert.equal(renamedLogin.response.status, 200);
  const logout = await call(env, "/api/account/logout", {}, { token: created.token });
  assert.equal(logout.response.status, 204);
  assert.equal((await call(env, "/api/account/me", null, { token: created.token, method: "GET" })).response.status, 401);
  const deletion = await call(env, "/api/account", {}, { token: renamedLogin.data.token, method: "DELETE" });
  assert.equal(deletion.response.status, 200);
  assert.equal((await call(env, "/api/account/me", null, { token: renamedLogin.data.token, method: "GET" })).response.status, 401);
  assert.equal([...env.TOKEN_STORE.values.keys()].some(key => key.startsWith("account-user:")), false);
});

test("legacy accounts remain usable when a short pepper was accidentally configured", async () => {
  const env = environment();
  const created = await signup(env);
  const userKey = "account-user:" + created.user.id;
  const user = await env.TOKEN_STORE.get(userKey, "json");
  const material = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  user.passwordHash = Buffer.from(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: Buffer.from(user.passwordSalt, "base64"), iterations: 100000 }, material, 256)).toString("base64");
  delete user.passwordPepperVersion;
  await env.TOKEN_STORE.put(userKey, JSON.stringify(user));
  env.AUTH_PEPPER = "short";
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const login = await call(env, "/api/account/login", { identifier: "account_audit", password });
    assert.equal(login.response.status, 200);
  }
  assert.equal((await env.TOKEN_STORE.get(userKey, "json")).passwordPepperVersion, undefined);
});

test("password reset mail transport failure returns a handled error and removes the unused token", async () => {
  const env = { ...environment(), RESEND_API_KEY: "local-test-only-resend" };
  await signup(env);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new TypeError("simulated connection reset"); };
  try {
    const result = await call(env, "/api/account/password/forgot", { email: "accountaudit@example.com" });
    assert.equal(result.response.status, 502);
    assert.equal([...env.TOKEN_STORE.values.keys()].some(key => key.startsWith("account-reset:")), false);
  } finally { globalThis.fetch = originalFetch; }
});

test("a reset form validation error preserves the link so the user can correct and submit it", async () => {
  const env = environment();
  const created = await signup(env);
  const token = "d".repeat(64);
  await env.TOKEN_STORE.put("account-reset:" + await hash(token), created.user.id);
  const form = new Request("https://apitempo.com/reset-password", { method: "POST", body: new URLSearchParams({ token, password: "short", confirmation: "short" }) });
  const response = await handlePasswordResetPage(form, env, new URL(form.url));
  const html = await response.text();
  assert.match(html, /name="password"/);
  assert.ok(html.includes('name="token" value="' + token + '"'));
  const corrected = await call(env, "/api/account/password/reset", { token, password: "CorrectedPassword123" });
  assert.equal(corrected.response.status, 200);
});

test("password reset email, token use, old-session invalidation and single use work together", async () => {
  const env = { ...environment(), RESEND_API_KEY: "local-test-only-resend" };
  const created = await signup(env);
  let resetLink;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, options) => {
    assert.equal(String(input), "https://api.resend.com/emails");
    const email = JSON.parse(options.body);
    assert.deepEqual(email.to, ["accountaudit@example.com"]);
    resetLink = email.text.match(/https:\/\/apitempo.com\/reset-password\?token=[a-f0-9]+/)[0];
    return new Response('{"id":"local-mail"}', { status: 200 });
  };
  try {
    const sent = await call(env, "/api/account/password/forgot", { email: "accountaudit@example.com" });
    assert.equal(sent.response.status, 200);
  } finally { globalThis.fetch = originalFetch; }
  const token = new URL(resetLink).searchParams.get("token");
  assert.equal((await call(env, "/api/account/password/reset", { token, password: "ReplacedPassword123" })).response.status, 200);
  assert.equal((await call(env, "/api/account/password/reset", { token, password: "AnotherPassword123" })).response.status, 400);
  assert.equal((await call(env, "/api/account/me", null, { token: created.token, method: "GET" })).response.status, 401);
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password })).response.status, 401);
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password: "ReplacedPassword123" })).response.status, 200);
});

test("profile edits do not rewrite the unchanged username index", async () => {
  const env = environment();
  const created = await signup(env);
  const key = "account-username:" + created.user.username;
  const before = env.TOKEN_STORE.writes.get(key);
  const update = await call(env, "/api/account/profile", { sports: ["tennis"] }, { token: created.token, method: "PATCH" });
  assert.equal(update.response.status, 200);
  assert.equal(env.TOKEN_STORE.writes.get(key), before);
});

test("a strong v2 pepper enables signup with an unchanged short historical v1 secret", async () => {
  const env = { ...environment(), AUTH_PEPPER: "historical-short", AUTH_PEPPER_V2: "new-version-two-test-pepper-at-least-32-characters" };
  const created = await signup(env);
  const stored = await env.TOKEN_STORE.get("account-user:" + created.user.id, "json");
  assert.equal(stored.passwordPepperVersion, 2);
  assert.equal(env.AUTH_PEPPER, "historical-short");
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password })).response.status, 200);
  delete env.AUTH_PEPPER_V2;
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password })).response.status, 503);
});

test("historical short-v1 hashes verify with the original secret and migrate only after correct login", async () => {
  const env = environment();
  const created = await signup(env);
  const userKey = "account-user:" + created.user.id;
  const original = await env.TOKEN_STORE.get(userKey, "json");
  const historicalSecret = "historical-short";
  const material = await crypto.subtle.importKey("raw", new TextEncoder().encode(password + "\u0000" + historicalSecret), "PBKDF2", false, ["deriveBits"]);
  original.passwordHash = Buffer.from(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: Buffer.from(original.passwordSalt, "base64"), iterations: 100000 }, material, 256)).toString("base64");
  await env.TOKEN_STORE.put(userKey, JSON.stringify(original));
  env.AUTH_PEPPER = historicalSecret;
  env.AUTH_PEPPER_V2 = "new-version-two-test-pepper-at-least-32-characters";
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password: "WrongPassword123" })).response.status, 401);
  assert.equal((await env.TOKEN_STORE.get(userKey, "json")).passwordPepperVersion, 1);
  delete env.AUTH_PEPPER;
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password })).response.status, 503);
  env.AUTH_PEPPER = historicalSecret;
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password })).response.status, 200);
  const upgraded = await env.TOKEN_STORE.get(userKey, "json");
  assert.equal(upgraded.passwordPepperVersion, 2);
  assert.notEqual(upgraded.passwordHash, original.passwordHash);
  assert.equal(env.AUTH_PEPPER, historicalSecret);
  delete env.AUTH_PEPPER;
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password })).response.status, 200);
});

test("v2 password reset migrates a v1 account without requiring the old secret", async () => {
  const env = environment();
  const created = await signup(env);
  const token = "e".repeat(64);
  await env.TOKEN_STORE.put("account-reset:" + await hash(token), created.user.id);
  delete env.AUTH_PEPPER;
  env.AUTH_PEPPER_V2 = "new-version-two-test-pepper-at-least-32-characters";
  assert.equal((await call(env, "/api/account/password/reset", { token, password: "ResetOnVersionTwo123" })).response.status, 200);
  assert.equal((await env.TOKEN_STORE.get("account-user:" + created.user.id, "json")).passwordPepperVersion, 2);
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password: "ResetOnVersionTwo123" })).response.status, 200);
});

test("a used password-reset token is removed even before the KV listing contains it", async () => {
  const env = environment();
  const created = await signup(env);
  const token = "f".repeat(64);
  const resetKey = "account-reset:" + await hash(token);
  await env.TOKEN_STORE.put(resetKey, created.user.id);
  const actualList = env.TOKEN_STORE.list.bind(env.TOKEN_STORE);
  env.TOKEN_STORE.list = async options => options.prefix === "account-reset:"
    ? { keys: [], list_complete: true }
    : actualList(options);
  assert.equal((await call(env, "/api/account/password/reset", { token, password: "ReplacedPassword123" })).response.status, 200);
  assert.equal(await env.TOKEN_STORE.get(resetKey), null, "Consuming the provided token must not depend on a prefix listing");
  assert.equal((await call(env, "/api/account/password/reset", { token, password: "AnotherPassword123" })).response.status, 400);
});

test("a reset token expires after its configured 30-minute KV lifetime without changing the password", async () => {
  const env = { ...environment(), RESEND_API_KEY: "local-test-only-resend" };
  await signup(env);
  const originalFetch = globalThis.fetch;
  let token;
  globalThis.fetch = async (_, options) => {
    token = JSON.parse(options.body).text.match(/token=([a-f0-9]{64})/)[1];
    return new Response('{"id":"local-mail"}', { status: 200 });
  };
  try {
    assert.equal((await call(env, "/api/account/password/forgot", { email: "accountaudit@example.com" })).response.status, 200);
  } finally { globalThis.fetch = originalFetch; }
  const resetKey = "account-reset:" + await hash(token);
  assert.equal(env.TOKEN_STORE.expirations.get(resetKey), env.TOKEN_STORE.now + 30 * 60 * 1000);
  env.TOKEN_STORE.now += 30 * 60 * 1000 + 1;
  assert.equal((await call(env, "/api/account/password/reset", { token, password: "MustNotBeApplied123" })).response.status, 400);
  assert.equal((await call(env, "/api/account/login", { identifier: "account_audit", password })).response.status, 200);
});

test("English password-reset requests send localized email and preserve language through validation and use", async () => {
  const env = { ...environment(), RESEND_API_KEY: "local-test-only-resend" };
  await signup(env);
  let link;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_, options) => {
    const email = JSON.parse(options.body);
    assert.equal(email.subject, "Reset your Tempo password");
    assert.match(email.text, /30 minutes/);
    link = email.text.match(/https:\/\/apitempo.com\/reset-password\?[^\s]+/)[0];
    assert.equal(new URL(link).searchParams.get("lang"), "en");
    return new Response('{"id":"local-mail"}', { status: 200 });
  };
  try {
    const sent = await call(env, "/api/account/password/forgot", { email: "accountaudit@example.com" }, { headers: { "Accept-Language": "en-US,en;q=0.9,tr;q=0.5" } });
    assert.equal(sent.response.status, 200);
    assert.match(sent.data.message, /If an account matches/);
  } finally { globalThis.fetch = originalFetch; }
  const token = new URL(link).searchParams.get("token");
  const page = await handlePasswordResetPage(new Request(link), env, new URL(link));
  const html = await page.text();
  assert.match(html, /<html lang="en">/);
  assert.match(html, /Create a new password/);
  assert.match(html, /name="lang" value="en"/);
  for (const [newPassword, confirmation, expectedMessage] of [
    ["short", "short", "Password must contain 8–128 characters."],
    ["ValidPass123", "Different123", "Passwords do not match."],
    ["NewEnglishPassword123", "NewEnglishPassword123", "Your password has been updated."],
    ["AnotherPassword123", "AnotherPassword123", "This reset link has expired or has already been used."],
  ]) {
    const form = new Request("https://apitempo.com/reset-password", { method: "POST", headers: { "Accept-Language": "tr" }, body: new URLSearchParams({ token, lang: "en", password: newPassword, confirmation }) });
    const response = await handlePasswordResetPage(form, env, new URL(form.url));
    const resultHTML = await response.text();
    assert.match(resultHTML, /<html lang="en">/);
    assert.ok(resultHTML.includes(expectedMessage), "Reset form should show the localized outcome");
    if (newPassword === "short" || newPassword === "ValidPass123") assert.ok(resultHTML.includes('name="token" value="' + token + '"'));
  }
});
