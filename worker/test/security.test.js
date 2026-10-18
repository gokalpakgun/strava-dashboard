import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { webcrypto } from "node:crypto";
import worker from "../src/index.js";
import { handleAccountRequest, accountContext } from "../src/account.js";
import { deleteSocialAccount, handleModerationRequest, handleSocialRequest } from "../src/social.js";
import { readLimitedText, RequestBodyTooLargeError } from "../src/http.js";

globalThis.crypto ||= webcrypto;

class MemoryKV {
  values = new Map();
  writeCounts = new Map();

  async get(key, type) {
    const value = this.values.get(key);
    if (value === undefined) return null;
    return type === "json" ? JSON.parse(value) : value;
  }

  async put(key, value) {
    this.values.set(key, String(value));
    this.writeCounts.set(key, (this.writeCounts.get(key) || 0) + 1);
  }
  async delete(key) { this.values.delete(key); }

  async list({ prefix = "", limit = 1000 } = {}) {
    const keys = [...this.values.keys()]
      .filter(key => key.startsWith(prefix))
      .sort()
      .slice(0, limit)
      .map(name => ({ name }));
    return { keys, list_complete: true };
  }
}

function accountEnv() {
  return {
    TOKEN_STORE: new MemoryKV(),
    AUTH_PEPPER: "test-only-high-entropy-auth-pepper",
    AI: { run: async () => ({ response: "safe" }) },
  };
}

test("Strava OAuth state survives KV edge propagation and rejects tampering", async () => {
  const env = {
    TOKEN_STORE: new MemoryKV(),
    STRAVA_CLIENT_ID: "test-client",
    STRAVA_CLIENT_SECRET: "test-secret-for-oauth-state",
    ASSETS: { fetch: async () => new Response("not found", { status: 404 }) },
  };
  const originalFetch = globalThis.fetch;
  let tokenExchanges = 0;
  globalThis.fetch = async (input) => {
    assert.equal(String(input), "https://www.strava.com/oauth/token");
    tokenExchanges += 1;
    return new Response(JSON.stringify({
      access_token: "test-access-token",
      refresh_token: "test-refresh-token",
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      athlete: { id: tokenExchanges },
    }), { headers: { "Content-Type": "application/json" } });
  };

  try {
    const webStart = await worker.fetch(new Request("https://apitempo.com/auth/start"), env, {});
    const webState = new URL(webStart.headers.get("Location")).searchParams.get("state");
    const stateCookie = webStart.headers.get("Set-Cookie").split(";")[0];
    assert.equal(webStart.headers.get("Referrer-Policy"), "no-referrer");
    assert.equal(await env.TOKEN_STORE.get(`state:${webState}`), null);

    const webCallback = await worker.fetch(new Request(
      `https://apitempo.com/auth/callback?state=${encodeURIComponent(webState)}&code=web-code`,
      { headers: { Cookie: stateCookie } },
    ), env, {});
    assert.equal(webCallback.status, 302);
    assert.equal(new URL(webCallback.headers.get("Location")).searchParams.get("connected"), "1");
    assert.equal(webCallback.headers.get("Referrer-Policy"), "no-referrer");

    const mobileStart = await worker.fetch(new Request(
      `https://apitempo.com/mobile/auth/start?code_challenge=${"A".repeat(43)}`,
    ), env, {});
    const mobileState = new URL(mobileStart.headers.get("Location")).searchParams.get("state");
    assert.equal(await env.TOKEN_STORE.get(`mobile-oauth-state:${mobileState}`), null);

    const tamperedState = `${mobileState.startsWith("A") ? "B" : "A"}${mobileState.slice(1)}`;
    const rejected = await worker.fetch(new Request(
      `https://apitempo.com/mobile/auth/callback?state=${tamperedState}&code=attacker-code`,
    ), env, {});
    assert.equal(rejected.status, 400);
    assert.equal(tokenExchanges, 1);

    const mobileCallback = await worker.fetch(new Request(
      `https://apitempo.com/mobile/auth/callback?state=${encodeURIComponent(mobileState)}&code=mobile-code`,
    ), env, {});
    assert.equal(mobileCallback.status, 302);
    assert.match(mobileCallback.headers.get("Location"), /^tempohealth:\/\/auth\?ticket=/);
    assert.equal(tokenExchanges, 2);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("bounded request reader rejects oversized bodies without buffering them", async () => {
  const request = new Request("https://apitempo.com/api/account/signup", {
    method: "POST",
    headers: { "Content-Length": "9" },
    body: new ReadableStream({
      pull(controller) {
        controller.enqueue(new TextEncoder().encode("123456789"));
        controller.close();
      },
    }),
    duplex: "half",
  });

  await assert.rejects(readLimitedText(request, 8), RequestBodyTooLargeError);
  assert.equal(request.body.locked, false);
});

test("bounded request reader also enforces the stream limit if Content-Length lies", async () => {
  const request = new Request("https://apitempo.com/api/account/signup", {
    method: "POST",
    headers: { "Content-Length": "1" },
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("123456789"));
        controller.close();
      },
    }),
    duplex: "half",
  });

  await assert.rejects(readLimitedText(request, 8), RequestBodyTooLargeError);
});

function jsonRequest(path, value, headers = {}) {
  return new Request("https://apitempo.com" + path, {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.20", ...headers },
    body: JSON.stringify(value),
  });
}

async function signUp(env, requestId = "") {
  const headers = requestId ? { "X-Tempo-Request-ID": requestId } : {};
  const response = await handleAccountRequest(
    jsonRequest("/api/account/signup", { email: "audit@example.com", username: "audit_user", password: "OriginalPass123" }, headers),
    env,
    new URL("https://apitempo.com/api/account/signup"),
  );
  return { response, body: await response.json() };
}

async function signUpAs(env, email, username) {
  const request = jsonRequest("/api/account/signup", { email, username, password: "OriginalPass123" });
  const response = await handleAccountRequest(request, env, new URL(request.url));
  return { response, body: await response.json() };
}

test("password hashes are peppered and legacy users are upgraded on successful login", async () => {
  const env = accountEnv();
  const created = await signUpAs(env, "legacy@example.com", "legacy_user");
  const user = await env.TOKEN_STORE.get("account-user:" + created.body.user.id, "json");
  const salt = Uint8Array.from(atob(user.passwordSalt), character => character.charCodeAt(0));
  const material = await crypto.subtle.importKey("raw", new TextEncoder().encode("OriginalPass123"), "PBKDF2", false, ["deriveBits"]);
  const legacyBits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations: 100000 }, material, 256);
  user.passwordHash = btoa(String.fromCharCode(...new Uint8Array(legacyBits)));
  delete user.passwordPepperVersion;
  await env.TOKEN_STORE.put("account-user:" + user.id, JSON.stringify(user));

  const loginRequest = jsonRequest("/api/account/login", { identifier: "legacy_user", password: "OriginalPass123" });
  const login = await handleAccountRequest(loginRequest, env, new URL(loginRequest.url));
  assert.equal(login.status, 200);
  const upgraded = await env.TOKEN_STORE.get("account-user:" + user.id, "json");
  assert.equal(upgraded.passwordPepperVersion, 1);
  assert.notEqual(upgraded.passwordHash, user.passwordHash);

  const unconfigured = { TOKEN_STORE: new MemoryKV() };
  const rejectedSignup = await signUpAs(unconfigured, "new@example.com", "new_user");
  assert.equal(rejectedSignup.response.status, 503);
  const weakPepper = { ...accountEnv(), AUTH_PEPPER: "too-short" };
  const weakSignup = await signUpAs(weakPepper, "weak@example.com", "weak_user");
  assert.equal(weakSignup.response.status, 503);
});

function socialRequest(path, token, value, method = "POST") {
  return new Request("https://apitempo.com" + path, {
    method,
    headers: { Authorization: "Bearer " + token, ...(value ? { "Content-Type": "application/json" } : {}) },
    ...(value ? { body: JSON.stringify(value) } : {}),
  });
}

test("social report queue is private; blocking removes friendship, requests and challenge access", async () => {
  const env = { ...accountEnv(), MODERATION_TOKEN: "test-only-moderation-secret-at-least-32-chars" };
  const [alice, bob] = await Promise.all([
    signUpAs(env, "alice@example.com", "alice_audit"),
    signUpAs(env, "bob@example.com", "bob_audit"),
  ]);
  assert.equal(alice.response.status, 201);
  assert.equal(bob.response.status, 201);

  const sendRequest = await worker.fetch(socialRequest("/api/account/social/friends", alice.body.token, { username: "bob_audit" }), env);
  assert.equal(sendRequest.status, 201);
  const pending = await worker.fetch(socialRequest("/api/account/social", bob.body.token, null, "GET"), env);
  const pendingData = await pending.json();
  const accept = await worker.fetch(socialRequest("/api/account/social/requests", bob.body.token, { requestId: pendingData.incoming[0].id, action: "accept" }), env);
  assert.equal(accept.status, 200);

  const createdChallenge = await worker.fetch(socialRequest("/api/account/social/challenges", alice.body.token, {
    title: "Audit challenge", metric: "steps", friendIds: [bob.body.user.id],
  }), env);
  assert.equal(createdChallenge.status, 201);
  const challengeData = await createdChallenge.json();
  const reported = await worker.fetch(socialRequest("/api/account/social/reports", bob.body.token, {
    challengeId: challengeData.challenge.id, category: "inappropriate",
  }), env);
  assert.equal(reported.status, 201);

  const unauthorized = await worker.fetch(new Request("https://apitempo.com/api/moderation/reports"), env);
  assert.equal(unauthorized.status, 401);
  const queue = await worker.fetch(new Request("https://apitempo.com/api/moderation/reports", {
    headers: { Authorization: "Bearer " + env.MODERATION_TOKEN },
  }), env);
  assert.equal(queue.status, 200);
  const reports = await queue.json();
  assert.equal(reports.reports.length, 1);
  assert.equal(reports.reports[0].targetUserId, alice.body.user.id);
  assert.equal(reports.reports[0].status, "open");

  const resolve = await worker.fetch(new Request("https://apitempo.com/api/moderation/reports/" + reports.reports[0].id, {
    method: "POST",
    headers: { Authorization: "Bearer " + env.MODERATION_TOKEN, "Content-Type": "application/json" },
    body: JSON.stringify({ action: "resolve" }),
  }), env);
  assert.equal(resolve.status, 200);
  const closedQueue = await (await worker.fetch(new Request("https://apitempo.com/api/moderation/reports", {
    headers: { Authorization: "Bearer " + env.MODERATION_TOKEN },
  }), env)).json();
  assert.equal(closedQueue.reports[0].status, "resolved");

  const blocked = await worker.fetch(socialRequest("/api/account/social/blocks", alice.body.token, { userId: bob.body.user.id, action: "block" }), env);
  assert.equal(blocked.status, 200);
  const aliceSnapshot = await (await worker.fetch(socialRequest("/api/account/social", alice.body.token, null, "GET"), env)).json();
  assert.deepEqual(aliceSnapshot.friends, []);
  assert.equal(aliceSnapshot.blocked[0].id, bob.body.user.id);
  assert.equal(aliceSnapshot.challenges[0].participants.some(participant => participant.userId === bob.body.user.id), false);
  const rejectedReconnect = await worker.fetch(socialRequest("/api/account/social/friends", bob.body.token, { username: "alice_audit" }), env);
  assert.equal(rejectedReconnect.status, 403);
});

test("social creation stays disabled when the moderation secret is missing or weak", async () => {
  const env = { ...accountEnv(), MODERATION_TOKEN: "short" };
  const user = await signUpAs(env, "social@example.com", "social_audit");
  const response = await worker.fetch(socialRequest("/api/account/social/challenges", user.body.token, {
    title: "Weekly", metric: "steps", friendIds: ["a".repeat(40)],
  }), env);
  assert.equal(response.status, 503);
  const reportQueue = await worker.fetch(new Request("https://apitempo.com/api/moderation/reports", {
    headers: { Authorization: "Bearer short" },
  }), env);
  assert.equal(reportQueue.status, 503);
});

test("public usernames are moderated on signup and username changes", async () => {
  const env = accountEnv();
  env.AI = { run: async () => ({ response: "unsafe S10" }) };
  const rejectedSignup = await signUpAs(env, "bad-name@example.com", "unsafe_user");
  assert.equal(rejectedSignup.response.status, 400);

  env.AI = { run: async () => ({ response: "safe" }) };
  const user = await signUpAs(env, "good-name@example.com", "safe_user");
  env.AI = { run: async () => ({ response: "unsafe S10" }) };
  const usernameChange = await worker.fetch(new Request("https://apitempo.com/api/account/profile", {
    method: "PATCH",
    headers: { Authorization: "Bearer " + user.body.token, "Content-Type": "application/json" },
    body: JSON.stringify({ username: "unsafe_user_2" }),
  }), env);
  assert.equal(usernameChange.status, 400);
});

test("community text is rejected when classified unsafe and fails closed when moderation is unavailable", async () => {
  const env = { ...accountEnv(), MODERATION_TOKEN: "test-only-moderation-secret-at-least-32-chars" };
  const user = await signUpAs(env, "filtered@example.com", "filtered_user");
  env.AI = { run: async () => ({ response: "unsafe S10" }) };
  const profileRequest = new Request("https://apitempo.com/api/account/profile", {
    method: "PATCH",
    headers: { Authorization: "Bearer " + user.body.token, "Content-Type": "application/json" },
    body: JSON.stringify({ displayName: "blocked text" }),
  });
  const profile = await worker.fetch(profileRequest, env);
  assert.equal(profile.status, 400);

  const challengeRequest = socialRequest("/api/account/social/challenges", user.body.token, {
    title: "blocked title", metric: "steps", friendIds: ["a".repeat(40)],
  });
  const challenge = await worker.fetch(challengeRequest, env);
  assert.equal(challenge.status, 400);

  env.AI = { run: async () => { throw new Error("moderation unavailable"); } };
  const unavailable = await worker.fetch(new Request("https://apitempo.com/api/account/profile", {
    method: "PATCH",
    headers: { Authorization: "Bearer " + user.body.token, "Content-Type": "application/json" },
    body: JSON.stringify({ displayName: "not reviewed" }),
  }), env);
  assert.equal(unavailable.status, 503);
});

test("signup idempotency never exposes an existing session to a request-ID-only caller", async () => {
  const env = accountEnv();
  const requestId = "d707bc40-a42c-49c9-8598-5a8109f3b4ee";
  const first = await signUp(env, requestId);
  assert.equal(first.response.status, 201);
  assert.equal(typeof first.body.token, "string");

  const wrongPasswordRequest = jsonRequest("/api/account/signup", {
    email: "audit@example.com", username: "audit_user", password: "WrongPassword123",
  }, { "X-Tempo-Request-ID": requestId });
  const replay = await handleAccountRequest(wrongPasswordRequest, env, new URL(wrongPasswordRequest.url));
  assert.equal(replay.status, 409);
  assert.equal((await replay.json()).token, undefined);

  const stored = [...env.TOKEN_STORE.values.entries()].find(([key]) => key.startsWith("account-signup-request:"));
  assert.deepEqual(JSON.parse(stored[1]), { userId: first.body.user.id });

  const validRetry = await signUp(env, requestId);
  assert.equal(validRetry.response.status, 201);
  assert.notEqual(validRetry.body.token, first.body.token);
});

test("password reset invalidates sessions created before the reset", async () => {
  const env = accountEnv();
  const created = await signUp(env);
  const resetToken = "a".repeat(64);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(resetToken));
  const resetHash = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
  await env.TOKEN_STORE.put("account-reset:" + resetHash, created.body.user.id, { expirationTtl: 1800 });
  const otherResetToken = "b".repeat(64);
  const otherDigest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(otherResetToken));
  const otherHash = [...new Uint8Array(otherDigest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
  await env.TOKEN_STORE.put("account-reset:" + otherHash, created.body.user.id, { expirationTtl: 1800 });

  const resetRequest = jsonRequest("/api/account/password/reset", { token: resetToken, password: "ReplacementPass123" });
  const reset = await handleAccountRequest(resetRequest, env, new URL(resetRequest.url));
  assert.equal(reset.status, 200);
  assert.equal(await env.TOKEN_STORE.get("account-reset:" + resetHash), null);
  assert.equal(await env.TOKEN_STORE.get("account-reset:" + otherHash), null);

  const oldSession = await accountContext(new Request("https://apitempo.com/api/account/me", {
    headers: { Authorization: "Bearer " + created.body.token },
  }), env);
  assert.equal(oldSession.response.status, 401);

  const loginRequest = jsonRequest("/api/account/login", { identifier: "audit_user", password: "ReplacementPass123" });
  const login = await handleAccountRequest(loginRequest, env, new URL(loginRequest.url));
  assert.equal(login.status, 200);
  assert.equal(typeof (await login.json()).token, "string");
});

test("authenticated Tempo API checks do not rewrite the session key on every request", async () => {
  const env = accountEnv();
  const created = await signUp(env);
  const sessionHash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(created.body.token)))]
    .map(byte => byte.toString(16).padStart(2, "0")).join("");
  const key = "account-session:" + sessionHash;
  const writesBefore = env.TOKEN_STORE.writeCounts.get(key);

  for (let i = 0; i < 3; i += 1) {
    const context = await accountContext(new Request("https://apitempo.com/api/account/me", {
      headers: { Authorization: "Bearer " + created.body.token },
    }), env);
    assert.equal(context.response, undefined);
  }

  assert.equal(env.TOKEN_STORE.writeCounts.get(key), writesBefore);
});

test("parallel mobile health reads do not rewrite the same mobile session key", async () => {
  const env = accountEnv();
  env.STRAVA_CLIENT_ID = "client-id";
  env.STRAVA_CLIENT_SECRET = "client-secret";
  env.ASSETS = { fetch: async () => new Response("ok") };
  const token = "e".repeat(64);
  const tokenHash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)))]
    .map(byte => byte.toString(16).padStart(2, "0")).join("");
  const sessionKey = "mobile-session:" + tokenHash;
  await Promise.all([
    env.TOKEN_STORE.put(sessionKey, "123456"),
    env.TOKEN_STORE.put("mobile-strava:123456", JSON.stringify({ refresh_token: "refresh-token" })),
    env.TOKEN_STORE.put("mobile-health:123456", JSON.stringify({ days: {} })),
  ]);
  const writesBefore = env.TOKEN_STORE.writeCounts.get(sessionKey);

  const responses = await Promise.all(Array.from({ length: 3 }, () => worker.fetch(new Request("https://apitempo.com/api/mobile/health", {
    headers: { Authorization: "Bearer " + token },
  }), env)));

  assert.deepEqual(responses.map(response => response.status), [200, 200, 200]);
  assert.equal(env.TOKEN_STORE.writeCounts.get(sessionKey), writesBefore);
});

test("rate-limit KV write contention returns 429 instead of a Worker error", async () => {
  class ContendedKV extends MemoryKV {
    async put(key, value, options) {
      if (key.startsWith("account-rate:") && this.writeCounts.has(key)) throw new Error("KV same-key write limit");
      return super.put(key, value, options);
    }
  }
  const env = { TOKEN_STORE: new ContendedKV(), AUTH_PEPPER: "test-only-high-entropy-auth-pepper", AI: { run: async () => ({ response: "safe" }) } };
  const first = await signUp(env);
  assert.equal(first.response.status, 201);
  const secondRequest = jsonRequest("/api/account/signup", {
    email: "second@example.com", username: "second_user", password: "OriginalPass123",
  });
  const response = await handleAccountRequest(secondRequest, env, new URL(secondRequest.url));
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "1");
});

test("parallel dashboard cache misses make one Strava fetch batch and one KV cache write", async () => {
  const env = accountEnv();
  env.STRAVA_CLIENT_ID = "client-id";
  env.STRAVA_CLIENT_SECRET = "client-secret";
  env.ASSETS = { fetch: async () => new Response("ok") };
  const sessionId = "dashboard-session";
  await env.TOKEN_STORE.put("session:" + sessionId, JSON.stringify({
    access_token: "access-token", refresh_token: "refresh-token", expires_at: Math.floor(Date.now() / 1000) + 3600,
  }));

  const originalFetch = globalThis.fetch;
  let stravaCalls = 0;
  globalThis.fetch = async input => {
    stravaCalls += 1;
    const url = new URL(String(input));
    if (url.pathname === "/api/v3/athlete") return new Response(JSON.stringify({ id: 123, firstname: "Tempo" }));
    if (url.pathname === "/api/v3/segments/starred") return new Response("[]");
    if (url.pathname === "/api/v3/athlete/activities") return new Response("[]");
    throw new Error("Unexpected mocked request: " + url.pathname);
  };
  try {
    const request = () => worker.fetch(new Request("https://apitempo.com/api/dashboard", {
      headers: { Cookie: "tempo_session=" + sessionId },
    }), env);
    const responses = await Promise.all([request(), request(), request()]);
    assert.deepEqual(responses.map(response => response.status), [200, 200, 200]);
    assert.deepEqual(await Promise.all(responses.map(response => response.json())).then(items => items.map(item => item.activities.length)), [0, 0, 0]);
    assert.equal(stravaCalls, 3);
    assert.equal(env.TOKEN_STORE.writeCounts.get("dashboard:v2:" + sessionId), 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("mobile dashboard keeps the first activity page when Strava rate limits older history", async () => {
  const env = accountEnv();
  env.STRAVA_CLIENT_ID = "client-id";
  env.STRAVA_CLIENT_SECRET = "client-secret";
  env.ASSETS = { fetch: async () => new Response("ok") };
  const token = "b".repeat(64);
  const tokenHash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)))]
    .map(byte => byte.toString(16).padStart(2, "0")).join("");
  await Promise.all([
    env.TOKEN_STORE.put("mobile-session:" + tokenHash, "123456"),
    env.TOKEN_STORE.put("mobile-strava:123456", JSON.stringify({
      access_token: "access-token", refresh_token: "refresh-token", expires_at: Math.floor(Date.now() / 1000) + 3600,
    })),
  ]);

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async input => {
    const url = new URL(String(input));
    if (url.pathname === "/api/v3/athlete") return new Response(JSON.stringify({ id: 123, firstname: "Tempo" }));
    if (url.pathname === "/api/v3/segments/starred") return new Response("[]");
    if (url.pathname === "/api/v3/athlete/activities" && url.searchParams.get("page") === "1") {
      const activities = Array.from({ length: 100 }, (_, index) => ({
        id: index + 1, name: `Run ${index + 1}`, sport_type: "Run", start_date_local: "2026-10-01T08:00:00Z",
        distance: 1000, moving_time: 300, total_elevation_gain: 10, average_speed: 3.3,
        total_photo_count: 0, map: { summary_polyline: "encoded-route" },
      }));
      return new Response(JSON.stringify(activities));
    }
    if (url.pathname === "/api/v3/athlete/activities") return new Response("rate limited", { status: 429 });
    throw new Error("Unexpected mocked request: " + url.pathname);
  };

  try {
    const response = await worker.fetch(new Request("https://apitempo.com/api/mobile/dashboard", {
      headers: { Authorization: "Bearer " + token },
    }), env);
    assert.equal(response.status, 200);
    const dashboard = await response.json();
    assert.equal(dashboard.activities.length, 100);
    assert.equal(dashboard.historyLimited, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("mobile dashboard exposes safe Strava status diagnostics for a denied activity request", async () => {
  const env = accountEnv();
  env.STRAVA_CLIENT_ID = "client-id";
  env.STRAVA_CLIENT_SECRET = "client-secret";
  env.ASSETS = { fetch: async () => new Response("ok") };
  const token = "c".repeat(64);
  const tokenHash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)))]
    .map(byte => byte.toString(16).padStart(2, "0")).join("");
  await Promise.all([
    env.TOKEN_STORE.put("mobile-session:" + tokenHash, "654321"),
    env.TOKEN_STORE.put("mobile-strava:654321", JSON.stringify({
      access_token: "access-token", refresh_token: "refresh-token", expires_at: Math.floor(Date.now() / 1000) + 3600,
    })),
  ]);

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async input => {
    const url = new URL(String(input));
    if (url.pathname === "/api/v3/athlete") return new Response(JSON.stringify({ id: 654321, firstname: "Tempo" }));
    if (url.pathname === "/api/v3/segments/starred") return new Response("[]");
    if (url.pathname === "/api/v3/athlete/activities") return new Response("forbidden", { status: 403 });
    throw new Error("Unexpected mocked request: " + url.pathname);
  };

  try {
    const response = await worker.fetch(new Request("https://apitempo.com/api/mobile/dashboard", {
      headers: { Authorization: "Bearer " + token },
    }), env);
    assert.equal(response.status, 403);
    assert.equal(response.headers.get("X-Tempo-Diagnostic"), "strava-activities-403");
    assert.deepEqual(await response.json(), { error: "Strava aktiviteleri alınamadı." });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("password reset email ignores an untrusted incoming Host", async () => {
  const env = accountEnv();
  env.RESEND_API_KEY = "test-key";
  await signUp(env);
  const originalFetch = globalThis.fetch;
  let emailPayload;
  globalThis.fetch = async (_url, options) => {
    emailPayload = JSON.parse(options.body);
    return new Response("{}", { status: 200 });
  };
  try {
    const hostileRequest = new Request("https://attacker.example/api/account/password/forgot", {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.20" },
      body: JSON.stringify({ email: "audit@example.com" }),
    });
    const response = await handleAccountRequest(hostileRequest, env, new URL(hostileRequest.url));
    assert.equal(response.status, 200);
    assert.match(emailPayload.text, /https:\/\/apitempo\.com\/reset-password\?token=/);
    assert.doesNotMatch(emailPayload.text, /attacker\.example/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("account deletion completes locally even when Strava revocation fails", async () => {
  const env = accountEnv();
  env.STRAVA_CLIENT_ID = "client-id";
  env.STRAVA_CLIENT_SECRET = "client-secret";
  const created = await signUp(env, "d707bc40-a42c-49c9-8598-5a8109f3b4ee");
  const userId = created.body.user.id;
  const athleteId = "987654321";
  const sessionHash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(created.body.token)))]
    .map(byte => byte.toString(16).padStart(2, "0")).join("");
  await Promise.all([
    env.TOKEN_STORE.put("account-strava:" + userId, athleteId),
    env.TOKEN_STORE.put("mobile-strava:" + athleteId, JSON.stringify({ refresh_token: "refresh-token" })),
    env.TOKEN_STORE.put("strava-account:" + athleteId, userId),
    env.TOKEN_STORE.put("mobile-link-for:" + athleteId, "mobile-hash"),
    env.TOKEN_STORE.put("mobile-session:mobile-hash", athleteId),
    env.TOKEN_STORE.put("mobile-dashboard:v3:" + athleteId, "{}"),
    env.TOKEN_STORE.put("account-health:" + userId, "{}"),
    env.TOKEN_STORE.put("account-water:" + userId, "{}"),
    env.TOKEN_STORE.put("account-reset:" + "c".repeat(64), userId),
    env.TOKEN_STORE.put("session:web-session", JSON.stringify({ athlete_id: athleteId, refresh_token: "refresh-token" })),
    env.TOKEN_STORE.put("strava-web-sessions:" + athleteId, JSON.stringify(["web-session"])),
    env.TOKEN_STORE.put("dashboard:v2:web-session", "{}"),
    env.TOKEN_STORE.put("account-session:" + sessionHash, JSON.stringify({ userId, version: 1 })),
  ]);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response("unavailable", { status: 503 });
  try {
    const request = new Request("https://apitempo.com/api/account", {
      method: "DELETE",
      headers: { Authorization: "Bearer " + created.body.token },
    });
    const response = await handleAccountRequest(request, env, new URL(request.url));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, stravaRevoked: false });
    for (const key of [
      "account-user:" + userId, "account-session:" + sessionHash, "account-reset:" + "c".repeat(64),
      "account-strava:" + userId, "mobile-strava:" + athleteId, "strava-account:" + athleteId,
      "mobile-link-for:" + athleteId, "mobile-session:mobile-hash", "mobile-dashboard:v3:" + athleteId,
      "account-health:" + userId, "account-water:" + userId, "session:web-session", "dashboard:v2:web-session",
      "strava-web-sessions:" + athleteId,
    ]) assert.equal(await env.TOKEN_STORE.get(key), null, key);
    const signupRequest = [...env.TOKEN_STORE.values.keys()].find(key => key.startsWith("account-signup-request:"));
    assert.equal(signupRequest, undefined);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("mobile Strava disconnect deletes Tempo copies even when OAuth revocation fails", async () => {
  const env = accountEnv();
  env.STRAVA_CLIENT_ID = "client-id";
  env.STRAVA_CLIENT_SECRET = "client-secret";
  env.ASSETS = { fetch: async () => new Response("ok") };
  const token = "d".repeat(64);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  const tokenHash = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
  await Promise.all([
    env.TOKEN_STORE.put("mobile-session:" + tokenHash, "123456"),
    env.TOKEN_STORE.put("mobile-link-for:123456", tokenHash),
    env.TOKEN_STORE.put("mobile-strava:123456", JSON.stringify({ refresh_token: "refresh-token" })),
    env.TOKEN_STORE.put("mobile-dashboard:v3:123456", "{}"),
    env.TOKEN_STORE.put("mobile-health:123456", "{}"),
    env.TOKEN_STORE.put("health-water-athlete:123456", "{}"),
    env.TOKEN_STORE.put("strava-account:123456", "tempo-account"),
    env.TOKEN_STORE.put("account-strava:tempo-account", "123456"),
  ]);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response("unavailable", { status: 503 });
  try {
    const response = await worker.fetch(new Request("https://apitempo.com/api/mobile/auth/logout", {
      method: "POST",
      headers: { Authorization: "Bearer " + token },
    }), env);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, stravaRevoked: false });
    for (const key of [
      "mobile-session:" + tokenHash, "mobile-link-for:123456", "mobile-strava:123456",
      "mobile-dashboard:v3:123456", "mobile-health:123456", "health-water-athlete:123456",
      "strava-account:123456", "account-strava:tempo-account",
    ]) assert.equal(await env.TOKEN_STORE.get(key), null, key);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("deleting a user removes their pending friend-request references from the other account", async () => {
  const env = accountEnv();
  await env.TOKEN_STORE.put("social-state:deleted", JSON.stringify({ friends: [], incoming: ["req-1"], outgoing: [], challenges: [] }));
  await env.TOKEN_STORE.put("social-state:remaining", JSON.stringify({ friends: [], incoming: [], outgoing: ["req-1"], challenges: [] }));
  await env.TOKEN_STORE.put("social-request:req-1", JSON.stringify({ id: "req-1", from: "remaining", to: "deleted", status: "pending" }));

  await deleteSocialAccount(env, "deleted");
  assert.deepEqual(await env.TOKEN_STORE.get("social-state:remaining", "json"), { friends: [], incoming: [], outgoing: [], challenges: [], blocked: [] });
  assert.equal(await env.TOKEN_STORE.get("social-request:req-1"), null);
  assert.equal(await env.TOKEN_STORE.get("social-state:deleted"), null);
});

test("privacy and terms routes select a supported language and are routed through the Worker", async () => {
  const config = JSON.parse(await readFile(new URL("../wrangler.jsonc", import.meta.url), "utf8"));
  assert.ok(config.assets.run_worker_first.includes("/terms"));
  assert.ok(config.assets.run_worker_first.includes("/privacy"));

  for (const [path, acceptLanguage, expected] of [
    ["/terms", "fr-CA, en-US;q=0.9, tr;q=0.8", "/terms-en.html"],
    ["/privacy", "tr-TR, en;q=0.8", "/privacy.html"],
  ]) {
    let requestedPath = "";
    const response = await worker.fetch(new Request("https://apitempo.com" + path, {
      headers: { "Accept-Language": acceptLanguage },
    }), { ASSETS: { fetch: async request => { requestedPath = new URL(request.url).pathname; return new Response("ok"); } } });
    assert.equal(response.status, 200);
    assert.equal(requestedPath, expected);
    assert.equal(response.headers.get("X-Frame-Options"), "DENY");
    assert.equal(response.headers.get("X-Content-Type-Options"), "nosniff");
    assert.equal(response.headers.get("Referrer-Policy"), "strict-origin-when-cross-origin");
    assert.match(response.headers.get("Content-Security-Policy"), /frame-ancestors 'none'/);
  }
});
