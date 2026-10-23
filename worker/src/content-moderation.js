const MODEL = "@cf/meta/llama-guard-3-8b";
// Documented Workers AI codes only; arbitrary error messages are never logged.
const PROVIDER_CODES = new Set([5007, 5004, 3039, 3003, 5018, 5016, 3023, 3041, 5035, 5019, 5005, 3042, 3006, 3007, 3008, 3036, 3040]);

// Only short public-facing user content is sent here. Health, Strava and
// private account fields must never be passed to this classifier.
export async function moderateCommunityText(env, text) {
  if (!env.AI || typeof env.AI.run !== "function") return unavailable("binding");
  if (typeof text !== "string" || !text.trim()) return unavailable("input");
  try {
    const result = await env.AI.run(MODEL, {
      messages: [
        {
          role: "user",
          // This guard's schema only accepts user/assistant roles. It applies
          // its own safety taxonomy to the public text; no system role.
          content: "Public sports profile or challenge text:\n<BEGIN USER TEXT>\n" + text.trim().slice(0, 100) + "\n<END USER TEXT>",
        },
      ],
      max_tokens: 128,
      temperature: 0,
      response_format: { type: "json_object" },
    });
    const verdict = parseVerdict(result?.response);
    if (verdict === true) return { allowed: true };
    if (verdict === false) return { allowed: false, unavailable: false };
    return unavailable("response-schema");
  } catch (error) {
    const explicitCode = Number(error?.code ?? error?.error_code);
    const messageCode = typeof error?.message === "string"
      ? Number(error.message.match(/^\s*(?:[A-Za-z][A-Za-z0-9_.]*:\s*)?(\d{4})(?=[:\s])/)?.[1]) : NaN;
    const code = PROVIDER_CODES.has(explicitCode) ? explicitCode : PROVIDER_CODES.has(messageCode) ? messageCode : null;
    const rawStatus = Number(error?.status ?? error?.statusCode);
    const status = Number.isInteger(rawStatus) && rawStatus >= 400 && rawStatus <= 599 ? rawStatus : null;
    return unavailable("provider", code, status);
  }
}

function parseVerdict(response) {
  if (typeof response === "string") {
    const text = response.trim();
    if (text.length > 4096) return null;
    if (text.startsWith("{")) {
      try { return parseVerdict(JSON.parse(text)); } catch { return null; }
    }
    if (/^safe$/i.test(text)) return true;
    if (/^unsafe(?:\s+S(?:[1-9]|1[0-4])(?:\s*,\s*S(?:[1-9]|1[0-4]))*)?$/i.test(text)) return false;
    return null;
  }
  if (!response || typeof response !== "object" || Array.isArray(response) || typeof response.safe !== "boolean") return null;
  if (response.categories !== undefined && (!Array.isArray(response.categories)
    || response.categories.some(category => typeof category !== "string" || !/^S(?:[1-9]|1[0-4])$/.test(category)))) return null;
  if (response.safe && response.categories?.length) return null;
  return response.safe;
}

function unavailable(type, code = null, status = null) {
  const diagnostic = code === null ? "moderation-" + type : "moderation-ai-" + code;
  console.error("Community text moderation unavailable.", { type, code, status });
  return { allowed: false, unavailable: true, diagnostic };
}
