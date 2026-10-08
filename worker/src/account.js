const ACCOUNT_SESSION_SECONDS = 60 * 60 * 24 * 30;
// Cloudflare Workers production rejects PBKDF2 counts above 100,000.
const PASSWORD_ITERATIONS = 100000;
const MAX_PROFILE_BODY = 800000;
const encoder = new TextEncoder();
const allowedSports = new Set([
  "run", "cycling", "walking", "hiking", "swimming", "fitness",
  "tennis", "basketball", "football", "volleyball", "padel", "badminton", "yoga",
]);

export async function handleAccountRequest(request, env, url) {
  if (!env.TOKEN_STORE) return responseJSON({ error: "Hesap depolama bağlantısı hazır değil." }, 503);

  if (url.pathname === "/api/account/signup" && request.method === "POST") {
    return signUp(request, env);
  }
  if (url.pathname === "/api/account/login" && request.method === "POST") {
    return signIn(request, env);
  }
  if (url.pathname === "/api/account/me" && request.method === "GET") {
    return getMe(request, env);
  }
  if (url.pathname === "/api/account/profile" && request.method === "PATCH") {
    return updateProfile(request, env);
  }
  if (url.pathname === "/api/account/logout" && request.method === "POST") {
    return signOut(request, env);
  }
  if (url.pathname === "/api/account" && request.method === "DELETE") {
    return deleteAccount(request, env);
  }
  return null;
}

async function signUp(request, env) {
  const limited = await rateLimit(request, env, "signup", 6);
  if (limited) return limited;
  const parsed = await readBody(request, 8192);
  if (parsed.response) return parsed.response;

  const email = normalizeEmail(parsed.value.email);
  const username = normalizeUsername(parsed.value.username);
  const password = typeof parsed.value.password === "string" ? parsed.value.password : "";
  const validation = validateCredentials(email, username, password);
  if (validation) return responseJSON({ error: validation }, 400);

  const emailKey = "account-email:" + await sha256Hex(email);
  const usernameKey = "account-username:" + username;
  const existing = await Promise.all([
    env.TOKEN_STORE.get(emailKey),
    env.TOKEN_STORE.get(usernameKey),
  ]);
  if (existing[0]) return responseJSON({ error: "Bu e-posta adresiyle zaten bir Tempo hesabı var." }, 409);
  if (existing[1]) return responseJSON({ error: "Bu kullanıcı adı alınmış." }, 409);

  const id = randomHex(20);
  const salt = randomBase64(16);
  const passwordHash = await derivePassword(password, salt, PASSWORD_ITERATIONS);
  const now = new Date().toISOString();
  const user = {
    id,
    email,
    username,
    displayName: username,
    avatarBase64: null,
    sports: [],
    onboardingComplete: false,
    createdAt: now,
    updatedAt: now,
    passwordSalt: salt,
    passwordHash,
    passwordIterations: PASSWORD_ITERATIONS,
  };

  await Promise.all([
    env.TOKEN_STORE.put("account-user:" + id, JSON.stringify(user)),
    env.TOKEN_STORE.put(emailKey, id),
    env.TOKEN_STORE.put(usernameKey, id),
  ]);
  const session = await createSession(env, id);
  return responseJSON({ token: session.token, user: publicUser(user) }, 201);
}

async function signIn(request, env) {
  const limited = await rateLimit(request, env, "login", 10);
  if (limited) return limited;
  const parsed = await readBody(request, 8192);
  if (parsed.response) return parsed.response;

  const email = normalizeEmail(parsed.value.email);
  const password = typeof parsed.value.password === "string" ? parsed.value.password : "";
  if (!isValidEmail(email) || password.length < 1 || password.length > 128) {
    return responseJSON({ error: "E-posta veya şifre hatalı." }, 401);
  }

  const userId = await env.TOKEN_STORE.get("account-email:" + await sha256Hex(email));
  const user = userId ? await env.TOKEN_STORE.get("account-user:" + userId, "json") : null;
  if (!user?.passwordHash || !user?.passwordSalt) {
    return responseJSON({ error: "E-posta veya şifre hatalı." }, 401);
  }

  const candidate = await derivePassword(password, user.passwordSalt, user.passwordIterations || PASSWORD_ITERATIONS);
  if (!constantTimeEqual(candidate, user.passwordHash)) {
    return responseJSON({ error: "E-posta veya şifre hatalı." }, 401);
  }

  const session = await createSession(env, user.id);
  return responseJSON({ token: session.token, user: publicUser(user) });
}

async function getMe(request, env) {
  const context = await accountContext(request, env);
  if (context.response) return context.response;
  return responseJSON({ user: publicUser(context.user) });
}

async function updateProfile(request, env) {
  const context = await accountContext(request, env);
  if (context.response) return context.response;
  const parsed = await readBody(request, MAX_PROFILE_BODY);
  if (parsed.response) return parsed.response;
  const input = parsed.value;
  const user = { ...context.user };
  const oldUsername = user.username;

  if (input.displayName !== undefined) {
    const displayName = typeof input.displayName === "string" ? input.displayName.trim() : "";
    if (displayName.length < 2 || displayName.length > 50) {
      return responseJSON({ error: "Görünen ad 2–50 karakter olmalı." }, 400);
    }
    user.displayName = displayName;
  }

  if (input.username !== undefined) {
    const username = normalizeUsername(input.username);
    if (!isValidUsername(username)) {
      return responseJSON({ error: "Kullanıcı adı 3–24 karakter olmalı ve yalnızca harf, rakam veya alt çizgi içermeli." }, 400);
    }
    if (username !== oldUsername) {
      const owner = await env.TOKEN_STORE.get("account-username:" + username);
      if (owner && owner !== user.id) return responseJSON({ error: "Bu kullanıcı adı alınmış." }, 409);
      user.username = username;
    }
  }

  if (input.avatarBase64 !== undefined) {
    if (input.avatarBase64 === null || input.avatarBase64 === "") {
      user.avatarBase64 = null;
    } else if (
      typeof input.avatarBase64 !== "string" ||
      input.avatarBase64.length > 750000 ||
      !/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(input.avatarBase64)
    ) {
      return responseJSON({ error: "Profil fotoğrafı geçersiz veya çok büyük." }, 400);
    } else {
      user.avatarBase64 = input.avatarBase64;
    }
  }

  if (input.sports !== undefined) {
    if (!Array.isArray(input.sports) || input.sports.length > allowedSports.size) {
      return responseJSON({ error: "Spor seçimleri geçersiz." }, 400);
    }
    const sports = [...new Set(input.sports.filter(value => typeof value === "string"))];
    if (sports.some(value => !allowedSports.has(value))) {
      return responseJSON({ error: "Desteklenmeyen spor seçimi var." }, 400);
    }
    user.sports = sports;
  }

  if (input.onboardingComplete !== undefined) {
    if (typeof input.onboardingComplete !== "boolean") {
      return responseJSON({ error: "Kayıt durumu geçersiz." }, 400);
    }
    if (input.onboardingComplete && (!user.displayName || !Array.isArray(user.sports) || !user.sports.length)) {
      return responseJSON({ error: "Kaydı tamamlamak için adını ve en az bir spor seçimini ekle." }, 400);
    }
    user.onboardingComplete = input.onboardingComplete;
  }

  user.updatedAt = new Date().toISOString();
  const writes = [
    env.TOKEN_STORE.put("account-user:" + user.id, JSON.stringify(user)),
    env.TOKEN_STORE.put("account-username:" + user.username, user.id),
  ];
  if (oldUsername && oldUsername !== user.username) {
    writes.push(env.TOKEN_STORE.delete("account-username:" + oldUsername));
  }
  await Promise.all(writes);
  return responseJSON({ user: publicUser(user) });
}

async function signOut(request, env) {
  const token = bearerToken(request);
  if (token) await env.TOKEN_STORE.delete("account-session:" + await sha256Hex(token));
  return new Response(null, { status: 204, headers: securityHeaders() });
}

async function deleteAccount(request, env) {
  const context = await accountContext(request, env);
  if (context.response) return context.response;
  await Promise.all([
    env.TOKEN_STORE.delete("account-user:" + context.user.id),
    env.TOKEN_STORE.delete("account-email:" + await sha256Hex(context.user.email)),
    env.TOKEN_STORE.delete("account-username:" + context.user.username),
    env.TOKEN_STORE.delete("account-session:" + context.sessionHash),
  ]);
  return new Response(null, { status: 204, headers: securityHeaders() });
}

async function accountContext(request, env) {
  const token = bearerToken(request);
  if (!/^[a-f0-9]{64}$/i.test(token)) {
    return { response: responseJSON({ error: "Tempo oturumunun süresi doldu." }, 401) };
  }
  const sessionHash = await sha256Hex(token);
  const userId = await env.TOKEN_STORE.get("account-session:" + sessionHash);
  if (!userId) return { response: responseJSON({ error: "Tempo oturumunun süresi doldu." }, 401) };
  const user = await env.TOKEN_STORE.get("account-user:" + userId, "json");
  if (!user) {
    await env.TOKEN_STORE.delete("account-session:" + sessionHash);
    return { response: responseJSON({ error: "Tempo hesabı bulunamadı." }, 401) };
  }
  await env.TOKEN_STORE.put("account-session:" + sessionHash, userId, { expirationTtl: ACCOUNT_SESSION_SECONDS });
  return { user, sessionHash };
}

async function createSession(env, userId) {
  const token = randomHex(32);
  const hash = await sha256Hex(token);
  await env.TOKEN_STORE.put("account-session:" + hash, userId, { expirationTtl: ACCOUNT_SESSION_SECONDS });
  return { token, hash };
}

async function rateLimit(request, env, action, limit) {
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const key = "account-rate:" + action + ":" + await sha256Hex(ip);
  const count = Number(await env.TOKEN_STORE.get(key) || 0);
  if (count >= limit) {
    return responseJSON({ error: "Çok fazla deneme yapıldı. 15 dakika sonra yeniden dene." }, 429);
  }
  await env.TOKEN_STORE.put(key, String(count + 1), { expirationTtl: 900 });
  return null;
}

async function readBody(request, maximum) {
  try {
    const text = await request.text();
    if (text.length > maximum) return { response: responseJSON({ error: "İstek çok büyük." }, 413) };
    const value = JSON.parse(text);
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid");
    return { value };
  } catch {
    return { response: responseJSON({ error: "İstek bilgileri okunamadı." }, 400) };
  }
}

function validateCredentials(email, username, password) {
  if (!isValidEmail(email)) return "Geçerli bir e-posta adresi gir.";
  if (!isValidUsername(username)) return "Kullanıcı adı 3–24 karakter olmalı ve yalnızca harf, rakam veya alt çizgi içermeli.";
  if (password.length < 8 || password.length > 128) return "Şifre 8–128 karakter olmalı.";
  return null;
}

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}
function normalizeUsername(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}
function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value) && value.length <= 254;
}
function isValidUsername(value) {
  return /^[a-z0-9_]{3,24}$/.test(value);
}
function bearerToken(request) {
  const header = request.headers.get("Authorization") || "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() : "";
}
function publicUser(user) {
  return {
    id: user.id,
    email: user.email,
    username: user.username,
    displayName: user.displayName || user.username,
    avatarBase64: user.avatarBase64 || null,
    sports: Array.isArray(user.sports) ? user.sports : [],
    onboardingComplete: Boolean(user.onboardingComplete),
    createdAt: user.createdAt || null,
  };
}

async function derivePassword(password, saltBase64, iterations) {
  const material = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({
    name: "PBKDF2",
    hash: "SHA-256",
    salt: base64Bytes(saltBase64),
    iterations,
  }, material, 256);
  return bytesBase64(new Uint8Array(bits));
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}
function constantTimeEqual(left, right) {
  if (typeof left !== "string" || typeof right !== "string" || left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}
function randomHex(length) {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
}
function randomBase64(length) {
  return bytesBase64(crypto.getRandomValues(new Uint8Array(length)));
}
function bytesBase64(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
function base64Bytes(value) {
  const binary = atob(value);
  return Uint8Array.from(binary, character => character.charCodeAt(0));
}
function securityHeaders() {
  return {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  };
}
function responseJSON(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...securityHeaders(),
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}