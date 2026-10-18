export class RequestBodyTooLargeError extends Error {
  constructor() {
    super("Request body exceeds the configured limit");
    this.name = "RequestBodyTooLargeError";
  }
}

// Cloudflare KV requires expirationTtl to be at least 60 seconds. Keep short
// application cooldowns in the stored timestamp while using the minimum KV TTL.
export async function claimCooldown(kv, key, windowSeconds) {
  const durationSeconds = Number(windowSeconds);
  if (!kv || !Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    return { allowed: false, unavailable: true };
  }

  const now = Date.now();
  let previous;
  try {
    previous = await kv.get(key);
  } catch {
    return { allowed: false, unavailable: true };
  }

  if (previous !== null && previous !== undefined) {
    const previousAt = Number(previous);
    if (!Number.isFinite(previousAt) || now - previousAt < durationSeconds * 1000) {
      return { allowed: false, unavailable: false };
    }
  }

  try {
    await kv.put(key, String(now), { expirationTtl: Math.max(60, Math.ceil(durationSeconds)) });
  } catch {
    return { allowed: false, unavailable: true };
  }
  return { allowed: true, unavailable: false };
}

export async function readLimitedText(request, maximumBytes) {
  const declaredLength = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new RequestBodyTooLargeError();
  }

  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maximumBytes) {
        await reader.cancel();
        throw new RequestBodyTooLargeError();
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

