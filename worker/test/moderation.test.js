import assert from "node:assert/strict";
import test from "node:test";
import { webcrypto } from "node:crypto";
import { moderateCommunityText } from "../src/content-moderation.js";
import { handleAccountRequest } from "../src/account.js";

globalThis.crypto ||= webcrypto;

async function withoutLogs(run) {
  const saved = console.error;
  const logs = [];
  console.error = (...args) => logs.push(args);
  try { return await run(logs); } finally { console.error = saved; }
}

const classify = output => ({ AI: { run: async () => output } });

test("moderation accepts the Workers AI guard structured safe response and valid text variants", async () => {
  for (const response of [{ safe: true }, { safe: true, categories: [] }, "safe", " SAFE \n", '{"safe":true,"categories":[]}']) {
    assert.deepEqual(await moderateCommunityText(classify({ response }), "weekend_runner"), { allowed: true });
  }
});

test("moderation rejects structured unsafe and native unsafe category responses", async () => {
  for (const response of [{ safe: false }, { safe: false, categories: ["S10"] }, "unsafe", "unsafe S10", "unsafe\nS1,S10", '{"safe":false,"categories":["S7"]}']) {
    assert.deepEqual(await moderateCommunityText(classify({ response }), "public text"), { allowed: false, unavailable: false });
  }
});

test("moderation input follows the actual guard schema: no system role and bounded public text only", async () => {
  let called = false;
  const output = await moderateCommunityText({ AI: { run: async (model, input) => {
    called = true;
    assert.equal(model, "@cf/meta/llama-guard-3-8b");
    assert.deepEqual(input.messages.map(message => message.role), ["user"]);
    assert.equal(input.messages.every(message => ["user", "assistant"].includes(message.role)), true);
    assert.match(input.messages[0].content, /<BEGIN USER TEXT>/);
    assert.doesNotMatch(input.messages[0].content, /untransmitted-marker/);
    assert.equal(input.response_format.type, "json_object");
    assert.ok(input.max_tokens >= 64);
    return { response: { safe: true, categories: [] } };
  } } }, "a".repeat(100) + "untransmitted-marker");
  assert.equal(called, true);
  assert.equal(output.allowed, true);
});

test("moderation fails closed on malformed, contradictory or ambiguous provider output", async () => {
  const outputs = [null, {}, { response: [] }, { response: { safe: "true" } },
    { response: { safe: true, categories: ["S1"] } }, { response: { safe: true, categories: "none" } },
    { response: { safe: true, categories: ["unknown"] } }, { response: "safe\nunsafe" },
    { response: '{"safe":' }, { response: "safe, I think" }, { response: "x".repeat(4097) }];
  await withoutLogs(async logs => {
    for (const output of outputs) {
      assert.deepEqual(await moderateCommunityText(classify(output), "some-public-text"), {
        allowed: false, unavailable: true, diagnostic: "moderation-response-schema",
      });
    }
    assert.equal(logs.length, outputs.length);
    assert.equal(logs.every(entry => JSON.stringify(entry).includes("some-public-text")), false);
  });
});

test("provider billing/capacity diagnostics preserve only documented numeric codes and statuses", async () => {
  await withoutLogs(async logs => {
    for (const code of [3036, 3040, 5035]) {
      const env = { AI: { run: async () => { throw Object.assign(new Error("private-prompt-marker"), { code, status: code === 5035 ? 403 : 429 }); } } };
      assert.equal((await moderateCommunityText(env, "private-public-text-marker")).diagnostic, "moderation-ai-" + code);
    }
    const messageOnly = { AI: { run: async () => { throw new Error("InferenceUpstreamError: 3036: private-prompt-marker"); } } };
    assert.equal((await moderateCommunityText(messageOnly, "athlete_name")).diagnostic, "moderation-ai-3036");
    const serialized = JSON.stringify(logs);
    assert.doesNotMatch(serialized, /private-prompt-marker|private-public-text-marker/);
    assert.deepEqual(logs[0][1], { type: "provider", code: 3036, status: 429 });
  });
});

test("unknown provider errors and invalid binding/input have finite safe diagnostics", async () => {
  await withoutLogs(async logs => {
    const invalidCode = { AI: { run: async () => { throw Object.assign(new Error("private-marker"), { code: "private-marker", status: "private-marker" }); } } };
    assert.deepEqual(await moderateCommunityText(invalidCode, "athlete"), { allowed: false, unavailable: true, diagnostic: "moderation-provider" });
    assert.equal((await moderateCommunityText({}, "athlete")).diagnostic, "moderation-binding");
    assert.equal((await moderateCommunityText({ AI: {} }, "athlete")).diagnostic, "moderation-binding");
    assert.equal((await moderateCommunityText(classify({ response: "safe" }), " ")).diagnostic, "moderation-input");
    assert.doesNotMatch(JSON.stringify(logs), /private-marker/);
  });
});

test("signup succeeds when real guard schema returns a structured safe result", async () => {
  const values = new Map();
  const env = {
    AUTH_PEPPER: "moderation-regression-test-only-pepper-32-chars",
    TOKEN_STORE: {
      async get(key, type) {
        const value = values.get(key);
        return value === undefined ? null : type === "json" ? JSON.parse(value) : value;
      },
      async put(key, value) { values.set(key, String(value)); },
      async delete(key) { values.delete(key); },
    },
    AI: { run: async (_model, input) => {
      if (input.messages.some(message => message.role === "system")) throw Object.assign(new Error("Invalid data"), { code: 5004, status: 400 });
      return { response: { safe: true, categories: [] } };
    } },
  };
  const request = new Request("https://apitempo.com/api/account/signup", {
    method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.55" },
    body: JSON.stringify({ email: "guard-schema@example.com", username: "guard_schema", password: "RegressionPass123" }),
  });
  const result = await handleAccountRequest(request, env, new URL(request.url));
  assert.equal(result.status, 201);
  assert.equal((await result.json()).user.username, "guard_schema");
});
