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
  if (url.pathname === "/api/account/password/forgot" && request.method === "POST") {
    return forgotPassword(request, env, url);
  }
  if (url.pathname === "/api/account/password/reset" && request.method === "POST") {
    return resetPasswordAPI(request, env);
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
  const parsed = await readBody(request, 8192);
  if (parsed.response) return parsed.response;

  const email = normalizeEmail(parsed.value.email);
  const username = normalizeUsername(parsed.value.username);
  const password = typeof parsed.value.password === "string" ? parsed.value.password : "";
  const validation = validateCredentials(email, username, password);
  if (validation) return responseJSON({ error: validation }, 400);

  const limited = await rateLimit(request, env, "signup", 6);
  if (limited) return limited;

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
  const parsed = await readBody(request, 8192);
  if (parsed.response) return parsed.response;

  const identifier = typeof parsed.value.identifier === "string"
    ? parsed.value.identifier.trim().toLowerCase()
    : normalizeEmail(parsed.value.email);
  const password = typeof parsed.value.password === "string" ? parsed.value.password : "";
  const identifierIsEmail = identifier.includes("@");
  const validIdentifier = identifierIsEmail ? isValidEmail(identifier) : isValidUsername(identifier);
  if (!validIdentifier || password.length < 1 || password.length > 128) {
    return responseJSON({ error: "E-posta, kullanıcı adı veya şifre hatalı." }, 401);
  }

  const limited = await rateLimit(request, env, "login", 10);
  if (limited) return limited;

  const userId = identifierIsEmail
    ? await env.TOKEN_STORE.get("account-email:" + await sha256Hex(identifier))
    : await env.TOKEN_STORE.get("account-username:" + normalizeUsername(identifier));
  const user = userId ? await env.TOKEN_STORE.get("account-user:" + userId, "json") : null;
  if (!user?.passwordHash || !user?.passwordSalt) {
    return responseJSON({ error: "E-posta, kullanıcı adı veya şifre hatalı." }, 401);
  }

  const candidate = await derivePassword(password, user.passwordSalt, user.passwordIterations || PASSWORD_ITERATIONS);
  if (!constantTimeEqual(candidate, user.passwordHash)) {
    return responseJSON({ error: "E-posta, kullanıcı adı veya şifre hatalı." }, 401);
  }

  const session = await createSession(env, user.id);
  return responseJSON({ token: session.token, user: publicUser(user) });
}

async function forgotPassword(request, env, url) {
  if (!env.RESEND_API_KEY) {
    return responseJSON({ error: "Şifre sıfırlama e-posta servisi henüz hazır değil." }, 503);
  }

  const parsed = await readBody(request, 4096);
  if (parsed.response) return parsed.response;
  const email = normalizeEmail(parsed.value.email);
  if (!isValidEmail(email)) return responseJSON({ error: "Geçerli bir e-posta adresi gir." }, 400);

  const limited = await rateLimit(request, env, "password-reset", 5);
  if (limited) return limited;

  const generic = { message: "Hesap eşleşirse şifre sıfırlama bağlantısı gönderildi." };
  const userId = await env.TOKEN_STORE.get("account-email:" + await sha256Hex(email));
  if (!userId) return responseJSON(generic);

  const token = randomHex(32);
  const tokenHash = await sha256Hex(token);
  await env.TOKEN_STORE.put("account-reset:" + tokenHash, userId, { expirationTtl: 1800 });

  const resetLink = url.origin + "/reset-password?token=" + token;
  const sent = await sendPasswordResetEmail(env, email, resetLink);
  if (!sent) {
    await env.TOKEN_STORE.delete("account-reset:" + tokenHash);
    return responseJSON({ error: "Sıfırlama e-postası şu anda gönderilemedi. Biraz sonra tekrar dene." }, 502);
  }
  return responseJSON(generic);
}

async function sendPasswordResetEmail(env, email, resetLink) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": "Bearer " + env.RESEND_API_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.EMAIL_FROM || "Tempo <noreply@apitempo.com>",
      to: [email],
      subject: "Tempo şifreni sıfırla",
      html: "<div style=\"font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;max-width:560px;margin:auto;padding:28px;color:#132019\"><h1 style=\"font-size:26px\">Şifreni sıfırla</h1><p>Tempo hesabın için yeni bir şifre oluşturmak üzere aşağıdaki düğmeye dokun.</p><p style=\"margin:28px 0\"><a href=\"" + resetLink + "\" style=\"background:#45d978;color:#07120b;text-decoration:none;padding:14px 20px;border-radius:14px;font-weight:700\">Yeni şifre oluştur</a></p><p style=\"color:#66736b;font-size:13px\">Bu bağlantı 30 dakika geçerlidir. Bu isteği sen yapmadıysan e-postayı yok sayabilirsin.</p></div>",
      text: "Tempo şifreni sıfırlamak için bu bağlantıyı aç: " + resetLink + " Bağlantı 30 dakika geçerlidir.",
    }),
  });
  if (!response.ok) console.error("Password reset email failed:", response.status);
  return response.ok;
}

async function resetPasswordAPI(request, env) {
  const parsed = await readBody(request, 8192);
  if (parsed.response) return parsed.response;
  const result = await resetPasswordValues(parsed.value.token, parsed.value.password, env);
  return result.ok
    ? responseJSON({ message: "Şifren güncellendi." })
    : responseJSON({ error: result.error }, result.status);
}

async function resetPasswordValues(tokenValue, passwordValue, env) {
  const token = typeof tokenValue === "string" ? tokenValue.trim() : "";
  const password = typeof passwordValue === "string" ? passwordValue : "";
  if (!/^[a-f0-9]{64}$/i.test(token)) {
    return { ok: false, status: 400, error: "Sıfırlama bağlantısı geçersiz." };
  }
  if (password.length < 8 || password.length > 128) {
    return { ok: false, status: 400, error: "Şifre 8–128 karakter olmalı." };
  }

  const resetKey = "account-reset:" + await sha256Hex(token);
  const userId = await env.TOKEN_STORE.get(resetKey);
  if (!userId) {
    return { ok: false, status: 400, error: "Sıfırlama bağlantısının süresi dolmuş veya bağlantı daha önce kullanılmış." };
  }

  const user = await env.TOKEN_STORE.get("account-user:" + userId, "json");
  if (!user) {
    await env.TOKEN_STORE.delete(resetKey);
    return { ok: false, status: 400, error: "Tempo hesabı bulunamadı." };
  }

  const salt = randomBase64(16);
  user.passwordSalt = salt;
  user.passwordHash = await derivePassword(password, salt, PASSWORD_ITERATIONS);
  user.passwordIterations = PASSWORD_ITERATIONS;
  user.updatedAt = new Date().toISOString();
  await Promise.all([
    env.TOKEN_STORE.put("account-user:" + user.id, JSON.stringify(user)),
    env.TOKEN_STORE.delete(resetKey),
  ]);
  return { ok: true, status: 200 };
}

export async function handlePasswordResetPage(request, env, url) {
  if (!env.TOKEN_STORE) return passwordResetDocument("", "Hesap depolama bağlantısı hazır değil.", false);
  if (request.method === "GET") {
    const token = url.searchParams.get("token") || "";
    if (!/^[a-f0-9]{64}$/i.test(token)) {
      return passwordResetDocument("", "Sıfırlama bağlantısı geçersiz.", false);
    }
    return passwordResetDocument(token, "", false);
  }
  if (request.method === "POST") {
    const form = await request.formData();
    const password = String(form.get("password") || "");
    const confirmation = String(form.get("confirmation") || "");
    if (password !== confirmation) {
      return passwordResetDocument(String(form.get("token") || ""), "Şifreler eşleşmiyor.", false);
    }
    const result = await resetPasswordValues(form.get("token"), password, env);
    return passwordResetDocument("", result.ok ? "Şifren güncellendi. Artık Tempo uygulamasından giriş yapabilirsin." : result.error, result.ok);
  }
  return new Response("Method not allowed", { status: 405, headers: { "Allow": "GET, POST" } });
}

function passwordResetDocument(token, message, success) {
  const safeToken = /^[a-f0-9]{64}$/i.test(token) ? token : "";
  const safeMessage = escapeHTML(message || "");
  const content = success
    ? "<div class=\"result ok\"><div class=\"icon\">✓</div><h1>Şifren hazır</h1><p>" + safeMessage + "</p></div>"
    : "<h1>Yeni şifre oluştur</h1><p class=\"lead\">Tempo hesabın için güçlü bir şifre belirle.</p>" +
      (safeMessage ? "<div class=\"message\">" + safeMessage + "</div>" : "") +
      (safeToken ? "<form method=\"post\" action=\"/reset-password\"><input type=\"hidden\" name=\"token\" value=\"" + safeToken + "\"><label>Yeni şifre</label><input name=\"password\" type=\"password\" minlength=\"8\" maxlength=\"128\" required autocomplete=\"new-password\"><label>Yeni şifre tekrar</label><input name=\"confirmation\" type=\"password\" minlength=\"8\" maxlength=\"128\" required autocomplete=\"new-password\"><button type=\"submit\">Şifreyi güncelle</button></form>" : "");
  const html = "<!doctype html><html lang=\"tr\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Tempo şifre sıfırlama</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:linear-gradient(145deg,#08171c,#07100c);font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;color:#f5fff7;padding:20px}.card{width:min(100%,440px);background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.09);border-radius:28px;padding:28px;box-shadow:0 22px 70px rgba(0,0,0,.35)}.brand{color:#64ef8e;font-weight:800;margin-bottom:28px}.brand span{color:#91a49a;font-weight:500;margin-left:8px}h1{font-size:30px;margin:0 0 8px}.lead,p{color:#a8b5ad;line-height:1.5}.message{color:#ff9b78;background:rgba(255,105,65,.1);padding:12px;border-radius:13px;margin:18px 0}label{display:block;font-size:13px;font-weight:650;margin:16px 0 7px}input{width:100%;height:54px;border:1px solid rgba(255,255,255,.09);border-radius:15px;background:rgba(255,255,255,.06);color:white;padding:0 15px;font-size:16px}button{width:100%;height:56px;border:0;border-radius:16px;background:#64ef8e;color:#061109;font-size:16px;font-weight:750;margin-top:22px}.result{text-align:center}.icon{width:66px;height:66px;border-radius:50%;background:#64ef8e;color:#061109;display:grid;place-items:center;font-size:32px;font-weight:800;margin:0 auto 18px}</style></head><body><main class=\"card\"><div class=\"brand\">TEMPO <span>Sağlık ve spor</span></div>" + content + "</main></body></html>";
  return new Response(html, {
    status: 200,
    headers: {
      ...securityHeaders(),
      "Content-Type": "text/html; charset=utf-8",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
    },
  });
}

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, character => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[character]));
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
  const key = "account-rate:v2:" + action + ":" + await sha256Hex(ip);
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