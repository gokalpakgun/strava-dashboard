import { accountContext, handleAccountRequest, handlePasswordResetPage } from "./account.js";
import { handleAccountHealth, handleSportsChat } from "./sports-chat.js";
import { handleModerationRequest, handleSocialRequest } from "./social.js";
import { readLimitedText, RequestBodyTooLargeError } from "./http.js";

const SESSION_COOKIE = "tempo_session";
const STATE_COOKIE = "tempo_oauth_state";
const SESSION_SECONDS = 60 * 60 * 24 * 30;
const MOBILE_TOKEN_SECONDS = 60 * 60 * 24 * 100;
const MOBILE_CALLBACK_SCHEME = "tempohealth";
const stravaRefreshInFlight = new Map();
const dashboardInFlight = new Map();

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/api/account" || url.pathname.startsWith("/api/account/")) {
        const accountResponse = await handleAccountRequest(request, env, url);
        if (accountResponse) return accountResponse;
      }
      if (url.pathname === "/api/account/health" && ["GET", "POST", "DELETE"].includes(request.method)) {
        return handleAccountHealth(request, env);
      }
      if (url.pathname === "/api/account/sports-chat" && request.method === "POST") {
        return handleSportsChat(request, env);
      }
      if (url.pathname === "/api/account/social" || url.pathname.startsWith("/api/account/social/")) {
        const socialResponse = await handleSocialRequest(request, env, url);
        if (socialResponse) return socialResponse;
      }
      if (url.pathname === "/api/moderation/reports" || url.pathname.startsWith("/api/moderation/reports/")) {
        const moderationResponse = await handleModerationRequest(request, env, url);
        if (moderationResponse) return moderationResponse;
      }
      if (url.pathname === "/reset-password" && (request.method === "GET" || request.method === "POST")) {
        return handlePasswordResetPage(request, env, url);
      }
      if (url.pathname === "/auth/start" && request.method === "GET") {
        return startAuthorization(url, env);
      }
      if (url.pathname === "/auth/callback" && request.method === "GET") {
        return completeAuthorization(request, url, env);
      }
      if (url.pathname === "/mobile/auth/start" && request.method === "GET") {
        return startMobileAuthorization(url, env);
      }
      if (url.pathname === "/mobile/auth/callback" && request.method === "GET") {
        return completeMobileAuthorization(url, env);
      }
      if (url.pathname === "/api/mobile/ping" && request.method === "GET") {
        return json({ ok: true, service: "tempo-mobile" });
      }
      if (url.pathname === "/privacy" && request.method === "GET") {
        const page = preferredLegalLanguage(request) === "en" ? "/privacy-en.html" : "/privacy.html";
        return withStaticSecurityHeaders(await env.ASSETS.fetch(new Request(new URL(page, url), request)));
      }
      if (url.pathname === "/terms" && request.method === "GET") {
        const page = preferredLegalLanguage(request) === "en" ? "/terms-en.html" : "/terms.html";
        return withStaticSecurityHeaders(await env.ASSETS.fetch(new Request(new URL(page, url), request)));
      }
      if (isStravaWebhookPath(url, env) && request.method === "GET") {
        return verifyStravaWebhook(url, env);
      }
      if (isStravaWebhookPath(url, env) && request.method === "POST") {
        return receiveStravaWebhook(request, env, ctx);
      }
      if (url.pathname === "/api/mobile/auth/exchange" && request.method === "POST") {
        return exchangeMobileTicket(request, env);
      }
      if (url.pathname === "/api/mobile/auth/restore" && request.method === "POST") {
        return restoreMobileConnection(request, env);
      }
      if (url.pathname === "/api/mobile/auth/logout" && request.method === "POST") {
        return logoutMobile(request, env);
      }
      if (url.pathname === "/api/mobile/dashboard" && request.method === "GET") {
        return getMobileDashboard(request, env);
      }
      if (url.pathname === "/api/mobile/coach" && request.method === "POST") {
        return json({ error: "Strava aktivite verileriyle yapay zekâ değerlendirmesi devre dışı. Tempo Koç’u Tempo hesabınla kullan." }, 410);
      }
      if (url.pathname === "/api/mobile/health/sync" && request.method === "POST") {
        return syncMobileHealth(request, env);
      }
      if (url.pathname === "/api/mobile/health" && request.method === "GET") {
        return getMobileHealth(request, env);
      }
      if (url.pathname === "/api/mobile/health" && request.method === "DELETE") {
        return unlinkMobileHealth(request, env);
      }
      if (url.pathname === "/api/mobile/water/sync" && request.method === "POST") {
        return syncMobileWater(request, env);
      }
      if (url.pathname === "/api/mobile/water/sync" && request.method === "DELETE") {
        return unlinkMobileWater(request, env);
      }
      if (url.pathname === "/api/mobile/water" && request.method === "GET") {
        return getMobileWater(request, env);
      }
      if (url.pathname === "/api/mobile/water/add" && request.method === "POST") {
        return addMobileWater(request, env);
      }
      if (url.pathname === "/auth/logout" && request.method === "POST") {
        return logout(request, env);
      }
      if (url.pathname === "/api/activities" && request.method === "GET") {
        return getActivities(request, env);
      }
      if (url.pathname === "/api/dashboard" && request.method === "GET") {
        return getDashboard(request, env);
      }
      if (url.pathname === "/api/health/water" && request.method === "GET") {
        return getWaterState(request, env);
      }
      if (url.pathname === "/api/health/water/pair" && request.method === "POST") {
        return createWaterPair(request, url, env);
      }
      if (url.pathname === "/api/health/water/pair" && request.method === "DELETE") {
        return unlinkWaterPair(request, url, env);
      }
      if (url.pathname === "/api/health/water/sync" && request.method === "POST") {
        return syncWaterTotal(request, env);
      }

      if (url.pathname === "/api/coach" && request.method === "POST") {
        return json({ error: "Strava aktivite verileriyle yapay zekâ değerlendirmesi devre dışı. Tempo Koç yalnızca açıkça seçilen Apple Sağlık özetini kullanır." }, 410);
      }
      if (url.pathname.startsWith("/api/") || url.pathname.startsWith("/auth/")) {
        return json({ error: "Not found" }, 404);
      }
      return withStaticSecurityHeaders(await env.ASSETS.fetch(request));
    } catch (error) {
      const rayId = request.headers.get("cf-ray") || "unavailable";
      const diagnostic = typeof error?.tempoDiagnostic === "string" && /^strava-[a-z-]+-\d{3}$/.test(error.tempoDiagnostic)
        ? error.tempoDiagnostic
        : "worker-error";
      console.error("Tempo Worker request failed:", { path: url.pathname, rayId, diagnostic, message: error?.message || "unknown error" });
      if (url.pathname.startsWith("/api/")) {
        return json({ error: "İstek tamamlanamadı. Biraz sonra tekrar deneyin." }, 502, { "X-Tempo-Diagnostic": diagnostic });
      }
      return new Response("Bağlantı sırasında bir sorun oluştu. Lütfen yeniden deneyin.", {
        status: 502,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
      });
    }
  },
};

function withStaticSecurityHeaders(response) {
  const headers = new Headers(response.headers);
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-Frame-Options", "DENY");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(self)");
  headers.set("Content-Security-Policy", "default-src 'self'; script-src 'self' https://unpkg.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://unpkg.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' https: data: blob:; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

function preferredLegalLanguage(request) {
  const supported = new Set(["en", "tr"]);
  const candidates = (request.headers.get("Accept-Language") || "")
    .split(",")
    .map((part, index) => {
      const [tag = "", quality = ""] = part.trim().split(";");
      const language = tag.trim().toLowerCase().split("-")[0];
      const match = quality.trim().match(/^q=(0(?:\.\d{0,3})?|1(?:\.0{0,3})?)$/i);
      return { language, quality: match ? Number(match[1]) : 1, index };
    })
    .filter(item => supported.has(item.language) && item.quality > 0)
    .sort((left, right) => right.quality - left.quality || left.index - right.index);
  return candidates[0]?.language || "tr";
}

async function startAuthorization(url, env) {
  requireBindings(env);
  const sessionId = randomToken();
  const state = await sealOAuthState(env, { flow: "web", sessionId });
  const redirectUri = `${url.origin}/auth/callback`;
  const authorize = new URL("https://www.strava.com/oauth/authorize");
  authorize.search = new URLSearchParams({
    client_id: env.STRAVA_CLIENT_ID,
    response_type: "code",
    redirect_uri: redirectUri,
    approval_prompt: "auto",
    scope: "activity:read_all,profile:read_all",
    state,
  }).toString();
  return new Response(null, {
    status: 302,
    headers: {
      Location: authorize.toString(),
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "Set-Cookie": cookie(STATE_COOKIE, state, 600, "/auth/callback"),
    },
  });
}

async function completeAuthorization(request, url, env) {
  requireBindings(env);
  const state = url.searchParams.get("state") || "";
  const code = url.searchParams.get("code");
  const stateCookie = readCookie(request, STATE_COOKIE);
  if (!state || !code || !stateCookie || state !== stateCookie) {
    return new Response("Strava bağlantısı doğrulanamadı. Lütfen yeniden deneyin.", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  const oauthState = await openOAuthState(env, state);
  const sessionId = oauthState?.flow === "web" ? oauthState.sessionId : "";
  if (!/^[a-f0-9]{64}$/i.test(sessionId)) {
    return new Response("Bağlantı isteğinin süresi doldu. Lütfen yeniden deneyin.", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }

  const tokens = await stravaToken({
    client_id: env.STRAVA_CLIENT_ID,
    client_secret: env.STRAVA_CLIENT_SECRET,
    code,
    grant_type: "authorization_code",
  });
  await env.TOKEN_STORE.put(`session:${sessionId}`, JSON.stringify({
    refresh_token: tokens.refresh_token,
    access_token: tokens.access_token,
    expires_at: Number(tokens.expires_at) || 0,
    athlete_id: tokens.athlete?.id ?? null,
  }), { expirationTtl: SESSION_SECONDS });
  if (tokens.athlete?.id) await rememberWebSession(env, tokens.athlete.id, sessionId);

  const headers = new Headers({ Location: `${url.origin}/?connected=1`, "Cache-Control": "no-store" });
  headers.set("Referrer-Policy", "no-referrer");
  headers.append("Set-Cookie", cookie(SESSION_COOKIE, sessionId, SESSION_SECONDS, "/"));
  headers.append("Set-Cookie", cookie(STATE_COOKIE, "", 0, "/auth/callback"));
  return new Response(null, {
    status: 302,
    headers,
  });
}

async function getActivities(request, env) {
  requireBindings(env);
  const sessionId = readCookie(request, SESSION_COOKIE);
  if (!sessionId) return json({ error: "Strava bağlantısı gerekli" }, 401);

  const saved = await env.TOKEN_STORE.get(`session:${sessionId}`, "json");
  if (!saved?.refresh_token) return json({ error: "Strava bağlantısı gerekli" }, 401);

  const accessToken = await stravaAccessToken(env, `session:${sessionId}`, saved, SESSION_SECONDS);

  const response = await fetch("https://www.strava.com/api/v3/athlete/activities?per_page=100", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) {
    console.error("Strava activities request failed with status:", response.status);
    return json({ error: "Strava aktiviteleri alınamadı." }, response.status === 401 ? 401 : 502);
  }
  const activities = await response.json();
  return json(activities.map((activity) => ({
    id: activity.id,
    name: activity.name,
    type: activity.sport_type || activity.type,
    start_date_local: activity.start_date_local,
    distance: activity.distance,
    moving_time: activity.moving_time,
    total_elevation_gain: activity.total_elevation_gain,
    average_speed: activity.average_speed,
  })));
}

async function getDashboard(request, env) {
  requireBindings(env);
  const sessionId = readCookie(request, SESSION_COOKIE);
  if (!sessionId) return json({ error: "Strava bağlantısı gerekli" }, 401);
  const sessionKey = `session:${sessionId}`;
  const saved = await env.TOKEN_STORE.get(sessionKey, "json");
  if (!saved?.refresh_token) return json({ error: "Strava bağlantısı gerekli" }, 401);
  return buildDashboard(env, { sessionKey, cacheKey: `dashboard:v2:${sessionId}`, saved, sessionTtl: SESSION_SECONDS });
}

async function getMobileDashboard(request, env) {
  requireBindings(env);
  const context = await getMobileContext(request, env);
  if (context.response) return context.response;
  return buildDashboard(env, {
    sessionKey: `mobile-strava:${context.athleteId}`,
    cacheKey: `mobile-dashboard:v3:${context.athleteId}`,
    saved: context.saved,
    sessionTtl: MOBILE_TOKEN_SECONDS,
  });
}

async function getMobileContext(request, env) {
  const token = readBearerToken(request);
  if (!token) return { response: json({ error: "Uygulama bağlantısı geçersiz." }, 401) };
  const tokenHash = await hashToken(token);
  const athleteId = await env.TOKEN_STORE.get(`mobile-session:${tokenHash}`);
  if (!athleteId) return { response: json({ error: "Uygulama bağlantısının süresi doldu. Strava ile yeniden giriş yap." }, 401) };
  const saved = await env.TOKEN_STORE.get(`mobile-strava:${athleteId}`, "json");
  if (!saved?.refresh_token) return { response: json({ error: "Strava bağlantısını uygulamadan bir kez yenile." }, 401) };
  // Mobile sessions have a fixed 100-day lifetime. Do not refresh their KV
  // keys on each API request: dashboard, Health and water loads can run in
  // parallel and KV rejects repeated writes to the same key within a second.
  return { athleteId, tokenHash, saved };
}

async function buildDashboard(env, { sessionKey, cacheKey, saved, sessionTtl }) {
  const cached = await env.TOKEN_STORE.get(cacheKey, "json");
  if (cached) return json(cached);

  const inFlight = dashboardInFlight.get(cacheKey);
  if (inFlight) return (await inFlight).clone();

  const pending = buildDashboardUncached(env, { sessionKey, cacheKey, saved, sessionTtl });
  dashboardInFlight.set(cacheKey, pending);
  try {
    return (await pending).clone();
  } finally {
    if (dashboardInFlight.get(cacheKey) === pending) dashboardInFlight.delete(cacheKey);
  }
}

async function buildDashboardUncached(env, { sessionKey, cacheKey, saved, sessionTtl }) {
  const accessToken = await stravaAccessToken(env, sessionKey, saved, sessionTtl);
  const headers = { Authorization: `Bearer ${accessToken}` };
  const [athleteResponse, segmentsResponse] = await Promise.all([
    fetch("https://www.strava.com/api/v3/athlete", { headers }),
    fetch("https://www.strava.com/api/v3/segments/starred?per_page=100", { headers }),
  ]);
  if (!athleteResponse.ok) {
    console.error("Strava athlete request failed with status:", athleteResponse.status);
    const status = [401, 403, 429].includes(athleteResponse.status) ? athleteResponse.status : 502;
    return json({ error: "Strava profil veya aktiviteleri alınamadı." }, status, {
      "X-Tempo-Diagnostic": `strava-athlete-${athleteResponse.status}`,
    });
  }

  const athlete = await athleteResponse.json();
  const activities = [];
  const perPage = 100;
  const maxPages = 10;
  let historyLimited = false;
  for (let page = 1; page <= maxPages; page += 1) {
    const response = await fetch(`https://www.strava.com/api/v3/athlete/activities?page=${page}&per_page=${perPage}`, { headers });
    if (!response.ok) {
      console.error("Strava activities request failed with status:", response.status);
      if (activities.length === 0) {
        const status = [401, 403, 429].includes(response.status) ? response.status : 502;
        return json({ error: "Strava aktiviteleri alınamadı." }, status, {
          "X-Tempo-Diagnostic": `strava-activities-${response.status}`,
        });
      }
      // Preserve available data when Strava throttles a later history page.
      historyLimited = true;
      break;
    }
    const pageActivities = await response.json();
    activities.push(...pageActivities);
    if (pageActivities.length < perPage) break;
    if (page === maxPages) historyLimited = true;
  }

  let segments = [];
  if (segmentsResponse.ok) {
    const value = await segmentsResponse.json();
    segments = value.map((segment) => ({
      id: segment.id,
      name: segment.name,
      distance: segment.distance,
      average_grade: segment.average_grade,
      climb_category: segment.climb_category,
      star_count: segment.star_count,
      athlete_segment_stats: segment.athlete_segment_stats,
    }));
  } else {
    console.warn("Strava starred segments unavailable with status:", segmentsResponse.status);
  }

  const photoActivities = activities.filter((activity) => activity.total_photo_count > 0).slice(0, 8);
  // Activity summaries normally include a simplified route; fetch details for
  // a few recent activities when it is absent, where Strava may expose the
  // full polyline instead. Reuse those detail requests for activity photos.
  const routeActivities = activities.filter((activity) => !activity.map?.summary_polyline).slice(0, 4);
  const detailActivities = [...new Map([...photoActivities, ...routeActivities].map((activity) => [activity.id, activity])).values()];
  const details = await Promise.all(detailActivities.map(async (activity) => {
    const response = await fetch(`https://www.strava.com/api/v3/activities/${activity.id}`, { headers });
    if (!response.ok) return [activity.id, null];
    return [activity.id, await response.json()];
  }));
  const detailsById = new Map(details);
  const photos = photoActivities.flatMap((activity) => {
    const detail = detailsById.get(activity.id);
    const primary = detail?.photos?.primary;
    const urls = primary?.urls || {};
    const image = urls["600"] || urls["500"] || urls["100"] || Object.values(urls)[0];
    return image ? [{ activity_id: activity.id, activity_name: activity.name, image }] : [];
  });

  const result = {
    athlete: {
      id: athlete.id,
      firstname: athlete.firstname,
      lastname: athlete.lastname,
      profile: athlete.profile,
      city: athlete.city,
      state: athlete.state,
      country: athlete.country,
      sex: athlete.sex,
      weight: athlete.weight,
      follower_count: athlete.follower_count,
      friend_count: athlete.friend_count,
      bikes: (athlete.bikes || []).map((gear) => ({ id: gear.id, name: gear.name, distance: gear.distance, primary: gear.primary, type: "Bisiklet" })),
      shoes: (athlete.shoes || []).map((gear) => ({ id: gear.id, name: gear.name, distance: gear.distance, primary: gear.primary, type: "Ayakkabı" })),
    },
    segments,
    photos,
    achievement: buildAchievement(activities),
    historyLimited,
    activities: activities.map((activity) => ({
      id: activity.id,
      name: activity.name,
      type: activity.sport_type || activity.type,
      start_date_local: activity.start_date_local,
      distance: activity.distance,
      moving_time: activity.moving_time,
      total_elevation_gain: activity.total_elevation_gain,
      average_speed: activity.average_speed,
      gear_id: activity.gear_id,
      total_photo_count: activity.total_photo_count,
      polyline: activity.map?.summary_polyline || detailsById.get(activity.id)?.map?.polyline || detailsById.get(activity.id)?.map?.summary_polyline || "",
    })),
  };
  await env.TOKEN_STORE.put(cacheKey, JSON.stringify(result), { expirationTtl: 600 });
  return json(result);
}


function finiteNonNegative(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : 0;
}

function buildAchievement(activities) {
  const source = Array.isArray(activities) ? activities : [];
  const totals = {
    activityCount: 0,
    movingHours: 0,
    elevationM: 0,
    longestActivityKm: 0,
  };
  const sportStats = Object.fromEntries(
    ["run", "ride", "walk", "hike", "swim", "fitness", "tennis", "basketball", "football", "volleyball", "padel", "badminton", "yoga"]
      .map((sport) => [sport, { count: 0, km: 0, hours: 0, longestKm: 0, maxMinutes: 0, days: new Set() }]),
  );
  const activeDays = new Set();
  const sports = new Set();
  let totalXP = 0;
  let earlyBirdCount = 0;

  for (const activity of source) {
    const movingMinutes = finiteNonNegative(activity.moving_time) / 60;
    const distanceKm = finiteNonNegative(activity.distance) / 1000;
    const elevationM = finiteNonNegative(activity.total_elevation_gain);
    if (movingMinutes <= 0 && distanceKm <= 0) continue;

    totals.activityCount += 1;
    totals.movingHours += movingMinutes / 60;
    totals.elevationM += elevationM;
    totals.longestActivityKm = Math.max(totals.longestActivityKm, distanceKm);

    const sport = achievementSport(activity.sport_type || activity.type);
    if (sportStats[sport]) {
      sports.add(sport);
      sportStats[sport].count += 1;
      sportStats[sport].km += distanceKm;
      sportStats[sport].hours += movingMinutes / 60;
      sportStats[sport].longestKm = Math.max(sportStats[sport].longestKm, distanceKm);
      sportStats[sport].maxMinutes = Math.max(sportStats[sport].maxMinutes, movingMinutes);
    }

    const localDate = String(activity.start_date_local || "");
    const day = localDate.slice(0, 10);
    if (/^\d{4}-\d{2}-\d{2}$/.test(day)) {
      activeDays.add(day);
      if (sportStats[sport]) sportStats[sport].days.add(day);
    }
    const hour = Number(localDate.slice(11, 13));
    if (Number.isFinite(hour) && hour >= 4 && hour < 8) earlyBirdCount += 1;

    const minuteXP = Math.min(Math.floor(movingMinutes) * 2, 360);
    let distanceXP = Math.floor(distanceKm);
    if (["run", "walk", "hike"].includes(sport)) distanceXP = Math.floor(distanceKm * 8);
    else if (sport === "ride") distanceXP = Math.floor(distanceKm * 2);
    else if (sport === "swim") distanceXP = Math.floor(distanceKm * 25);
    distanceXP = Math.min(distanceXP, 300);
    const elevationXP = Math.min(Math.floor(elevationM / 20), 100);
    totalXP += 25 + minuteXP + distanceXP + elevationXP;
  }

  totalXP = Math.max(0, Math.round(totalXP));
  const streak = longestAchievementStreak(activeDays);
  let level = 1;
  while (level < 50 && totalXP >= achievementLevelThreshold(level + 1)) level += 1;
  const levelStartXP = achievementLevelThreshold(level);
  const nextLevelTotalXP = level < 50 ? achievementLevelThreshold(level + 1) : levelStartXP;
  const nextLevelXP = level < 50 ? nextLevelTotalXP - levelStartXP : 0;
  const currentLevelXP = level < 50 ? totalXP - levelStartXP : 0;
  const progress = level < 50 && nextLevelXP > 0 ? Math.min(currentLevelXP / nextLevelXP, 1) : 1;

  const badge = (id, title, description, symbol, tint, current, target, unit) => ({
    id,
    title,
    description,
    symbol,
    tint,
    unlocked: current >= target,
    progress: Math.min(Math.max(current / target, 0), 1),
    current: Math.round(current * 10) / 10,
    target,
    unit,
  });
  const milestoneLabel = (value) => Number.isInteger(value) ? String(value) : String(value).replace(".", ",");
  const sportMilestoneBadges = ({ id, title, symbol, tint, stats, distanceTargets, longestTargets, sessionMinutes = 90 }) => {
    const lowerTitle = title.toLocaleLowerCase("tr-TR");
    const sportStreak = longestAchievementStreak(stats.days);
    const countTargets = distanceTargets?.length ? [1, 5, 10, 25, 50] : [1, 5, 10, 20, 35, 50, 100];
    const hourTargets = distanceTargets?.length ? [5, 15, 30, 75] : [5, 10, 25, 50, 100];
    const streakTargets = distanceTargets?.length ? [3, 7] : [3, 7, 14];
    const values = [
      ...countTargets.map((target, index) => badge(
        `${id}_count_${target}`,
        index === 0 ? `İlk ${title}` : `${title} · ${target} Aktivite`,
        `${target} ${lowerTitle} aktivitesi tamamla.`,
        symbol,
        tint,
        stats.count,
        target,
        "aktivite",
      )),
      ...hourTargets.map((target) => badge(
        `${id}_hours_${target}`,
        `${title} · ${target} Saat`,
        `Toplam ${target} saat ${lowerTitle} yap.`,
        "clock.fill",
        tint,
        stats.hours,
        target,
        "saat",
      )),
      ...streakTargets.map((target) => badge(
        `${id}_streak_${target}`,
        `${title} · ${target} Gün Seri`,
        `${target} gün aralıksız ${lowerTitle} aktivitesi kaydet.`,
        "flame.fill",
        tint,
        sportStreak,
        target,
        "gün",
      )),
    ];

    if (distanceTargets?.length) {
      values.push(
        ...distanceTargets.map((target) => badge(
          `${id}_distance_${String(target).replace(".", "_")}`,
          `${title} · ${milestoneLabel(target)} km`,
          `Toplam ${milestoneLabel(target)} km ${lowerTitle} yap.`,
          symbol,
          tint,
          stats.km,
          target,
          "km",
        )),
        ...longestTargets.map((target) => badge(
          `${id}_longest_${String(target).replace(".", "_")}`,
          `${title} · Tek Seferde ${milestoneLabel(target)} km`,
          `Tek bir aktivitede ${milestoneLabel(target)} km tamamla.`,
          "medal.fill",
          tint,
          stats.longestKm,
          target,
          "km",
        )),
      );
    } else {
      values.push(badge(
        `${id}_single_${sessionMinutes}`,
        `${title} · Uzun Seans`,
        `Tek bir aktivitede ${sessionMinutes} dakika tamamla.`,
        "stopwatch.fill",
        tint,
        stats.maxMinutes,
        sessionMinutes,
        "dk",
      ));
    }
    return values;
  };

  const badges = [
    badge("first_activity", "İlk Adım", "İlk Strava aktiviteni tamamla.", "flag.checkered", "green", totals.activityCount, 1, "aktivite"),
    badge("activity_10", "Ritim Yakala", "10 aktivite tamamla.", "10.circle.fill", "blue", totals.activityCount, 10, "aktivite"),
    badge("activity_25", "İstikrar", "25 aktivite tamamla.", "25.circle.fill", "green", totals.activityCount, 25, "aktivite"),
    badge("activity_50", "Aktif 50", "50 aktivite tamamla.", "50.circle.fill", "purple", totals.activityCount, 50, "aktivite"),
    badge("activity_100", "Yüzler Kulübü", "100 aktivite tamamla.", "trophy.fill", "orange", totals.activityCount, 100, "aktivite"),
    badge("activity_250", "Tempo Ustası", "250 aktivite tamamla.", "crown.fill", "pink", totals.activityCount, 250, "aktivite"),
    badge("active_10_hours", "10 Saat Aktif", "Toplam 10 saat hareket et.", "clock.fill", "purple", totals.movingHours, 10, "saat"),
    badge("active_50_hours", "50 Saat Aktif", "Toplam 50 saat hareket et.", "clock.badge.checkmark.fill", "blue", totals.movingHours, 50, "saat"),
    badge("active_100_hours", "Yüz Saat", "Toplam 100 saat hareket et.", "hourglass.tophalf.filled", "green", totals.movingHours, 100, "saat"),
    badge("active_250_hours", "Dayanıklılık", "Toplam 250 saat hareket et.", "bolt.heart.fill", "orange", totals.movingHours, 250, "saat"),
    badge("elevation_1000", "İlk Zirve", "Toplam 1.000 metre yüksel.", "mountain.2", "green", totals.elevationM, 1000, "m"),
    badge("elevation_5000", "Dağcı", "Toplam 5.000 metre yüksel.", "mountain.2.fill", "purple", totals.elevationM, 5000, "m"),
    badge("elevation_10000", "Yüksek İrtifa", "Toplam 10.000 metre yüksel.", "mountain.2.fill", "blue", totals.elevationM, 10000, "m"),
    badge("elevation_25000", "Zirvelerin Ustası", "Toplam 25.000 metre yüksel.", "mountain.2.fill", "orange", totals.elevationM, 25000, "m"),
    badge("streak_3", "Üç Gün Seri", "3 gün aralıksız aktivite kaydet.", "flame.fill", "orange", streak, 3, "gün"),
    badge("streak_7", "Yedi Gün Seri", "7 gün aralıksız aktivite kaydet.", "calendar.badge.checkmark", "green", streak, 7, "gün"),
    badge("streak_14", "İki Haftalık Seri", "14 gün aralıksız aktivite kaydet.", "calendar.badge.checkmark", "blue", streak, 14, "gün"),
    badge("streak_30", "Aylık Seri", "30 gün aralıksız aktivite kaydet.", "calendar.badge.checkmark", "purple", streak, 30, "gün"),
    badge("multi_sport_3", "Çok Yönlü", "En az 3 farklı spor türü yap.", "square.grid.2x2.fill", "pink", sports.size, 3, "spor"),
    badge("multi_sport_5", "Spor Kaşifi", "En az 5 farklı spor türü yap.", "safari.fill", "blue", sports.size, 5, "spor"),
    badge("multi_sport_8", "Her Sahada", "En az 8 farklı spor türü yap.", "star.square.on.square.fill", "orange", sports.size, 8, "spor"),
    badge("century", "Asırlık Sürüş", "Tek aktivitede 100 km tamamla.", "medal.fill", "green", totals.longestActivityKm, 100, "km"),
    badge("early_bird", "Erken Kuş", "Saat 08.00’den önce 5 aktiviteye başla.", "sunrise.fill", "orange", earlyBirdCount, 5, "aktivite"),
    badge("early_bird_20", "Güneşle Yarış", "Saat 08.00’den önce 20 aktiviteye başla.", "sunrise.circle.fill", "purple", earlyBirdCount, 20, "aktivite"),

    ...sportMilestoneBadges({ id: "run", title: "Koşu", symbol: "figure.run", tint: "orange", stats: sportStats.run, distanceTargets: [25, 50, 100, 250], longestTargets: [5, 10, 21.1] }),
    ...sportMilestoneBadges({ id: "ride", title: "Bisiklet", symbol: "bicycle", tint: "blue", stats: sportStats.ride, distanceTargets: [100, 250, 500, 1000], longestTargets: [25, 50, 100] }),
    ...sportMilestoneBadges({ id: "walk", title: "Yürüyüş", symbol: "figure.walk", tint: "green", stats: sportStats.walk, distanceTargets: [25, 100, 250, 500], longestTargets: [5, 10, 20] }),
    ...sportMilestoneBadges({ id: "hike", title: "Doğa Yürüyüşü", symbol: "figure.hiking", tint: "purple", stats: sportStats.hike, distanceTargets: [25, 50, 100, 250], longestTargets: [5, 10, 20] }),
    ...sportMilestoneBadges({ id: "swim", title: "Yüzme", symbol: "figure.pool.swim", tint: "blue", stats: sportStats.swim, distanceTargets: [5, 10, 25, 50], longestTargets: [1, 2, 5] }),
    ...sportMilestoneBadges({ id: "fitness", title: "Fitness", symbol: "dumbbell.fill", tint: "orange", stats: sportStats.fitness, sessionMinutes: 90 }),
    ...sportMilestoneBadges({ id: "tennis", title: "Tenis", symbol: "tennis.racket", tint: "green", stats: sportStats.tennis, sessionMinutes: 90 }),
    ...sportMilestoneBadges({ id: "basketball", title: "Basketbol", symbol: "basketball.fill", tint: "orange", stats: sportStats.basketball, sessionMinutes: 90 }),
    ...sportMilestoneBadges({ id: "football", title: "Futbol", symbol: "soccerball", tint: "green", stats: sportStats.football, sessionMinutes: 90 }),
    ...sportMilestoneBadges({ id: "volleyball", title: "Voleybol", symbol: "volleyball.fill", tint: "blue", stats: sportStats.volleyball, sessionMinutes: 90 }),
    ...sportMilestoneBadges({ id: "padel", title: "Padel", symbol: "figure.racquetball", tint: "purple", stats: sportStats.padel, sessionMinutes: 90 }),
    ...sportMilestoneBadges({ id: "badminton", title: "Badminton", symbol: "figure.badminton", tint: "blue", stats: sportStats.badminton, sessionMinutes: 75 }),
    ...sportMilestoneBadges({ id: "yoga", title: "Yoga", symbol: "figure.yoga", tint: "pink", stats: sportStats.yoga, sessionMinutes: 60 }),
  ];

  return {
    level,
    title: achievementLevelTitle(level),
    total_xp: totalXP,
    current_level_xp: Math.max(0, currentLevelXP),
    next_level_xp: nextLevelXP,
    progress: Math.round(progress * 1000) / 1000,
    unlocked_badge_count: badges.filter((item) => item.unlocked).length,
    total_badge_count: badges.length,
    badges,
  };
}

function achievementSport(value) {
  const type = String(value || "").toLowerCase();
  if (type.includes("run")) return "run";
  if (type.includes("ride") || type.includes("cycle") || type.includes("bike")) return "ride";
  if (type.includes("walk")) return "walk";
  if (type.includes("hike")) return "hike";
  if (type.includes("swim")) return "swim";
  if (type.includes("tennis")) return "tennis";
  if (type.includes("basketball")) return "basketball";
  if (type.includes("soccer") || type.includes("football")) return "football";
  if (type.includes("volleyball")) return "volleyball";
  if (type.includes("padel")) return "padel";
  if (type.includes("badminton")) return "badminton";
  if (type.includes("yoga")) return "yoga";
  if (type.includes("workout") || type.includes("weight") || type.includes("crossfit")) return "fitness";
  return "other";
}

function longestAchievementStreak(activeDays) {
  const values = [...activeDays]
    .map((day) => Math.floor(Date.parse(day + "T00:00:00Z") / 86400000))
    .filter(Number.isFinite)
    .sort((a, b) => a - b);
  let longest = 0;
  let current = 0;
  let previous = null;
  for (const value of values) {
    if (previous === null || value === previous + 1) current += 1;
    else if (value !== previous) current = 1;
    longest = Math.max(longest, current);
    previous = value;
  }
  return longest;
}

function achievementLevelThreshold(level) {
  return 100 * level * (level - 1);
}

function achievementLevelTitle(level) {
  if (level >= 40) return "Efsane";
  if (level >= 25) return "Zirve";
  if (level >= 15) return "Dayanıklılık";
  if (level >= 8) return "Atılım";
  if (level >= 3) return "Ritim";
  return "Başlangıç";
}

async function startMobileAuthorization(url, env) {
  requireBindings(env);
  const codeChallenge = url.searchParams.get("code_challenge") || "";
  if (!/^[A-Za-z0-9_-]{43}$/.test(codeChallenge)) {
    return new Response("Uygulama doğrulaması başlatılamadı. Tempo uygulamasından yeniden dene.", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  const state = await sealOAuthState(env, { flow: "mobile", codeChallenge });
  const authorize = new URL("https://www.strava.com/oauth/authorize");
  authorize.search = new URLSearchParams({
    client_id: env.STRAVA_CLIENT_ID,
    response_type: "code",
    redirect_uri: `${url.origin}/mobile/auth/callback`,
    approval_prompt: "auto",
    scope: "activity:read_all,profile:read_all",
    state,
  }).toString();
  return new Response(null, {
    status: 302,
    headers: { Location: authorize.toString(), "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" },
  });
}

async function completeMobileAuthorization(url, env) {
  requireBindings(env);
  const state = url.searchParams.get("state") || "";
  const code = url.searchParams.get("code") || "";
  if (!/^[A-Za-z0-9_-]{40,512}$/.test(state) || !code) {
    return new Response("Bağlantı isteği geçersiz veya süresi dolmuş. Tempo uygulamasından yeniden dene.", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  const oauthState = await openOAuthState(env, state);
  if (oauthState?.flow !== "mobile" || !/^[A-Za-z0-9_-]{43}$/.test(oauthState.codeChallenge || "")) {
    return new Response("Bağlantı isteği geçersiz veya süresi dolmuş. Tempo uygulamasından yeniden dene.", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  const tokens = await stravaToken({
    client_id: env.STRAVA_CLIENT_ID,
    client_secret: env.STRAVA_CLIENT_SECRET,
    code,
    grant_type: "authorization_code",
  });
  const athleteId = tokens.athlete?.id;
  if (!athleteId || !tokens.refresh_token) return new Response("Strava hesabı doğrulanamadı. Yeniden dene.", { status: 502 });
  const ticket = randomToken();
  await env.TOKEN_STORE.put(`mobile-ticket:${ticket}`, JSON.stringify({
    athleteId: String(athleteId),
    codeChallenge: oauthState.codeChallenge,
    refreshToken: tokens.refresh_token,
    accessToken: tokens.access_token,
    expiresAt: Number(tokens.expires_at) || 0,
  }), { expirationTtl: 300 });
  return new Response(null, {
    status: 302,
    headers: {
      Location: `${MOBILE_CALLBACK_SCHEME}://auth?ticket=${encodeURIComponent(ticket)}`,
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
}

async function restoreMobileConnection(request, env) {
  requireBindings(env);
  const account = await accountContext(request, env);
  if (account.response) return account.response;

  const suppliedToken = (request.headers.get("X-Tempo-Mobile-Token") || "").trim();
  if (/^[a-f0-9]{64}$/i.test(suppliedToken)) {
    const suppliedHash = await hashToken(suppliedToken);
    const suppliedAthleteId = await env.TOKEN_STORE.get(`mobile-session:${suppliedHash}`);
    const suppliedStrava = suppliedAthleteId
      ? await env.TOKEN_STORE.get(`mobile-strava:${suppliedAthleteId}`, "json")
      : null;
    if (suppliedAthleteId && suppliedStrava?.refresh_token) {
      const existingOwner = await env.TOKEN_STORE.get(`strava-account:${suppliedAthleteId}`);
      if (existingOwner && existingOwner !== account.user.id) {
        return json({ error: "Bu Strava hesabı başka bir Tempo hesabına bağlı. Önce o hesaptaki bağlantıyı kaldır." }, 409);
      }
      await Promise.all([
        env.TOKEN_STORE.put(`account-strava:${account.user.id}`, suppliedAthleteId),
        env.TOKEN_STORE.put(`strava-account:${suppliedAthleteId}`, account.user.id),
        env.TOKEN_STORE.put(`mobile-session:${suppliedHash}`, suppliedAthleteId, { expirationTtl: MOBILE_TOKEN_SECONDS }),
        env.TOKEN_STORE.put(`mobile-link-for:${suppliedAthleteId}`, suppliedHash, { expirationTtl: MOBILE_TOKEN_SECONDS }),
      ]);
      return json({ token: suppliedToken, athleteId: String(suppliedAthleteId), expiresIn: MOBILE_TOKEN_SECONDS });
    }
  }

  const athleteId = await env.TOKEN_STORE.get(`account-strava:${account.user.id}`);
  if (!athleteId) return json({ error: "Bu Tempo hesabına bağlı Strava hesabı bulunamadı." }, 404);

  const saved = await env.TOKEN_STORE.get(`mobile-strava:${athleteId}`, "json");
  if (!saved?.refresh_token) {
    await Promise.all([
      env.TOKEN_STORE.delete(`account-strava:${account.user.id}`),
      env.TOKEN_STORE.delete(`strava-account:${athleteId}`),
    ]);
    return json({ error: "Kayıtlı Strava bağlantısının yenilenmesi gerekiyor." }, 404);
  }

  const token = randomToken();
  const tokenHash = await hashToken(token);
  const oldHash = await env.TOKEN_STORE.get(`mobile-link-for:${athleteId}`);
  const writes = [
    env.TOKEN_STORE.put(`mobile-session:${tokenHash}`, athleteId, { expirationTtl: MOBILE_TOKEN_SECONDS }),
    env.TOKEN_STORE.put(`mobile-link-for:${athleteId}`, tokenHash, { expirationTtl: MOBILE_TOKEN_SECONDS }),
    env.TOKEN_STORE.put(`strava-account:${athleteId}`, account.user.id),
  ];
  if (oldHash && oldHash !== tokenHash) writes.push(env.TOKEN_STORE.delete(`mobile-session:${oldHash}`));
  await Promise.all(writes);
  return json({ token, athleteId: String(athleteId), expiresIn: MOBILE_TOKEN_SECONDS });
}

async function exchangeMobileTicket(request, env) {
  requireBindings(env);
  let input;
  try {
    const body = await readLimitedText(request, 1024);
    input = JSON.parse(body);
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) return json({ error: "İstek çok büyük." }, 413);
    return json({ error: "Bağlantı kodu okunamadı." }, 400);
  }
  const ticket = typeof input?.ticket === "string" ? input.ticket : "";
  const verifier = typeof input?.verifier === "string" ? input.verifier : "";
  if (!/^[a-f0-9]{64}$/i.test(ticket)) return json({ error: "Bağlantı kodu geçersiz." }, 400);
  if (!/^[A-Za-z0-9_-]{43}$/.test(verifier)) return json({ error: "Uygulama doğrulaması geçersiz." }, 400);
  const ticketKey = `mobile-ticket:${ticket}`;
  let ticketData = null;
  for (const delayMs of [0, 80, 160, 320, 640, 1000]) {
    if (delayMs) await new Promise((resolve) => setTimeout(resolve, delayMs));
    ticketData = await env.TOKEN_STORE.get(ticketKey, "json");
    if (ticketData?.athleteId && ticketData?.codeChallenge && ticketData?.refreshToken) break;
  }
  if (!ticketData?.athleteId || !ticketData?.codeChallenge || !ticketData?.refreshToken) {
    return json({ error: "Bağlantı kodu hazırlanamadı. Strava bağlantısını yeniden başlat." }, 408);
  }
  if (await sha256Base64Url(verifier) !== ticketData.codeChallenge) {
    return json({ error: "Uygulama doğrulaması eşleşmedi." }, 401);
  }
  const account = await accountContext(request, env);
  const existingOwner = await env.TOKEN_STORE.get(`strava-account:${ticketData.athleteId}`);
  if (existingOwner && (account.response || existingOwner !== account.user.id)) {
    return json({ error: "Bu Strava hesabı başka bir Tempo hesabına bağlı. Önce o hesaptaki bağlantıyı kaldır." }, 409);
  }
  if (ticketData.token) {
    return json({
      token: ticketData.token,
      athleteId: String(ticketData.athleteId),
      expiresIn: MOBILE_TOKEN_SECONDS,
    });
  }

  const token = randomToken();
  const tokenHash = await hashToken(token);
  const athleteKey = String(ticketData.athleteId);
  const oldHash = await env.TOKEN_STORE.get(`mobile-link-for:${athleteKey}`);
  const writes = [
    env.TOKEN_STORE.put(`mobile-session:${tokenHash}`, athleteKey, { expirationTtl: MOBILE_TOKEN_SECONDS }),
    env.TOKEN_STORE.put(`mobile-link-for:${athleteKey}`, tokenHash, { expirationTtl: MOBILE_TOKEN_SECONDS }),
    env.TOKEN_STORE.put(`mobile-strava:${athleteKey}`, JSON.stringify({
      refresh_token: ticketData.refreshToken,
      access_token: ticketData.accessToken,
      expires_at: ticketData.expiresAt,
      athlete_id: athleteKey,
    }), { expirationTtl: MOBILE_TOKEN_SECONDS }),
    env.TOKEN_STORE.put(ticketKey, JSON.stringify({ ...ticketData, token }), { expirationTtl: 300 }),
    env.TOKEN_STORE.delete(`mobile-dashboard:v3:${athleteKey}`),
  ];
  if (!account.response) {
    writes.push(
      env.TOKEN_STORE.put(`account-strava:${account.user.id}`, athleteKey),
      env.TOKEN_STORE.put(`strava-account:${athleteKey}`, account.user.id),
    );
  }
  if (oldHash) writes.push(env.TOKEN_STORE.delete(`mobile-session:${oldHash}`));
  await Promise.all(writes);
  return json({
    token,
    athleteId: athleteKey,
    expiresIn: MOBILE_TOKEN_SECONDS,
  });
}

async function logoutMobile(request, env) {
  requireBindings(env);
  const token = readBearerToken(request);
  if (!token) return json({ error: "Uygulama oturumu geçersiz." }, 401);
  const tokenHash = await hashToken(token);
  const athleteId = await env.TOKEN_STORE.get(`mobile-session:${tokenHash}`);
  if (!athleteId) return json({ ok: true });
  const linkedHash = await env.TOKEN_STORE.get(`mobile-link-for:${athleteId}`);
  const saved = await env.TOKEN_STORE.get(`mobile-strava:${athleteId}`, "json");
  let stravaRevoked = true;
  if (linkedHash === tokenHash) {
    if (saved?.refresh_token) stravaRevoked = await revokeStravaRefreshToken(env, saved.refresh_token);
    await clearStravaAthleteData(env, athleteId);
  } else {
    await env.TOKEN_STORE.delete(`mobile-session:${tokenHash}`);
  }
  return json({ ok: true, stravaRevoked });
}

async function revokeStravaRefreshToken(env, refreshToken) {
  if (!env.STRAVA_CLIENT_ID || !env.STRAVA_CLIENT_SECRET || !refreshToken) return false;
  try {
    const response = await fetch("https://www.strava.com/oauth/revoke", {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(env.STRAVA_CLIENT_ID + ":" + env.STRAVA_CLIENT_SECRET),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ token: refreshToken, token_type_hint: "refresh_token" }),
    });
    if (!response.ok) console.error("Strava token revocation failed with status:", response.status);
    return response.ok;
  } catch (error) {
    console.error("Strava token revocation request failed:", error?.message || "unknown error");
    return false;
  }
}

async function getMobileWater(request, env) {
  requireBindings(env);
  const token = readBearerToken(request);
  if (!token) return json({ error: "Uygulama bağlantısı geçersiz." }, 401);
  const tokenHash = await hashToken(token);
  const athleteId = await env.TOKEN_STORE.get(`mobile-session:${tokenHash}`);
  if (!athleteId) return json({ error: "Uygulama bağlantısının süresi doldu. Strava ile yeniden giriş yap." }, 401);
  const totals = await env.TOKEN_STORE.get(`health-water-athlete:${athleteId}`, "json") || {};
  return json({ totals });
}

async function getMobileHealth(request, env) {
  requireBindings(env);
  const context = await getMobileContext(request, env);
  if (context.response) return context.response;
  const stored = await env.TOKEN_STORE.get(`mobile-health:${context.athleteId}`, "json");
  return json(stored || { updatedAt: null, days: {} });
}

async function syncMobileHealth(request, env) {
  requireBindings(env);
  const context = await getMobileContext(request, env);
  if (context.response) return context.response;

  let input;
  try {
    const body = await readLimitedText(request, 65_536);
    input = JSON.parse(body);
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) return json({ error: "Sağlık verisi isteği çok büyük." }, 413);
    return json({ error: "Sağlık verileri okunamadı." }, 400);
  }
  if (!input?.days || typeof input.days !== "object" || Array.isArray(input.days) || Object.keys(input.days).length > 92) {
    return json({ error: "Günlük sağlık verileri geçersiz." }, 400);
  }

  const latestAllowed = new Date();
  latestAllowed.setUTCDate(latestAllowed.getUTCDate() + 1);
  const earliestAllowed = new Date();
  earliestAllowed.setUTCDate(earliestAllowed.getUTCDate() - 90);
  const minDay = earliestAllowed.toISOString().slice(0, 10);
  const maxDay = latestAllowed.toISOString().slice(0, 10);
  const limits = {
    waterMl: [0, 20000, 0],
    sleepMinutes: [0, 1440, 0],
    sleepCoreMinutes: [0, 1440, 0],
    sleepDeepMinutes: [0, 1440, 0],
    sleepREMMinutes: [0, 1440, 0],
    sleepAwakeMinutes: [0, 1440, 0],
    steps: [0, 200000, 0],
    activeEnergyKcal: [0, 20000, 1],
    exerciseMinutes: [0, 1440, 0],
    restingHeartRateBpm: [20, 250, 1],
    hrvMs: [0, 1000, 1],
    respiratoryRate: [3, 80, 1],
    oxygenSaturationPct: [50, 100, 1],
    vo2Max: [5, 100, 1],
    walkingHeartRateBpm: [20, 250, 1],
    heartRateRecoveryBpm: [0, 150, 1],
    wristTemperatureC: [25, 45, 2],
    bodyMassKg: [5, 500, 1],
  };
  const clean = {};
  for (const [day, values] of Object.entries(input.days)) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(Date.parse(`${day}T00:00:00Z`)) || new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) !== day || day < minDay || day > maxDay || !values || typeof values !== "object" || Array.isArray(values)) {
      return json({ error: "Sağlık verilerinde geçersiz tarih bulundu." }, 400);
    }
    const row = {};
    for (const [key, [minimum, maximum, digits]] of Object.entries(limits)) {
      if (values[key] === undefined || values[key] === null) continue;
      const number = Number(values[key]);
      if (!Number.isFinite(number) || number < minimum || number > maximum) {
        return json({ error: `${day} tarihindeki ${key} değeri geçersiz.` }, 400);
      }
      const factor = 10 ** digits;
      row[key] = Math.round(number * factor) / factor;
    }
    if (Object.keys(row).length) clean[day] = row;
  }

  const updatedAt = new Date().toISOString();
  const healthKey = `mobile-health:${context.athleteId}`;
  const waterKey = `health-water-athlete:${context.athleteId}`;
  const waterTotals = Object.fromEntries(Object.entries(clean)
    .filter(([, values]) => Number.isFinite(values.waterMl))
    .map(([day, values]) => [day, Math.round(values.waterMl)]));
  const writes = [
    env.TOKEN_STORE.put(healthKey, JSON.stringify({ updatedAt, days: clean }), { expirationTtl: 60 * 60 * 24 * 100 }),
  ];
  writes.push(Object.keys(waterTotals).length
    ? env.TOKEN_STORE.put(waterKey, JSON.stringify(waterTotals), { expirationTtl: 60 * 60 * 24 * 100 })
    : env.TOKEN_STORE.delete(waterKey));
  await Promise.all(writes);
  return json({ ok: true, syncedDays: Object.keys(clean).length, updatedAt });
}

async function unlinkMobileHealth(request, env) {
  requireBindings(env);
  const context = await getMobileContext(request, env);
  if (context.response) return context.response;
  await Promise.all([
    env.TOKEN_STORE.delete(`mobile-health:${context.athleteId}`),
    env.TOKEN_STORE.delete(`health-water-athlete:${context.athleteId}`),
  ]);
  return json({ ok: true });
}

async function addMobileWater(request, env) {
  requireBindings(env);
  const token = readBearerToken(request);
  if (!token) return json({ error: "Uygulama bağlantısı geçersiz." }, 401);
  const tokenHash = await hashToken(token);
  const athleteId = await env.TOKEN_STORE.get(`mobile-session:${tokenHash}`);
  if (!athleteId) return json({ error: "Uygulama bağlantısının süresi doldu. Strava ile yeniden giriş yap." }, 401);

  let input;
  try {
    const body = await readLimitedText(request, 1024);
    input = JSON.parse(body);
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) return json({ error: "İstek çok büyük." }, 413);
    return json({ error: "Su miktarı okunamadı." }, 400);
  }

  const day = typeof input?.date === "string" ? input.date : "";
  const amountMl = Number(input?.amountMl);
  const now = new Date();
  const latestAllowed = new Date(now);
  latestAllowed.setUTCDate(latestAllowed.getUTCDate() + 1);
  const earliestAllowed = new Date(now);
  earliestAllowed.setUTCDate(earliestAllowed.getUTCDate() - 1);
  const minDay = earliestAllowed.toISOString().slice(0, 10);
  const maxDay = latestAllowed.toISOString().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(Date.parse(`${day}T00:00:00Z`)) || new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) !== day || day < minDay || day > maxDay || !Number.isInteger(amountMl) || amountMl < 1 || amountMl > 2000) {
    return json({ error: "Tarih veya su miktarı geçersiz." }, 400);
  }

  const totalsKey = `health-water-athlete:${athleteId}`;
  const totals = await env.TOKEN_STORE.get(totalsKey, "json") || {};
  const current = Number(totals[day]) || 0;
  const totalMl = current + amountMl;
  if (totalMl > 20000) return json({ error: "Günlük su toplamı 20.000 ml sınırını aşamaz." }, 400);
  totals[day] = totalMl;
  await Promise.all([
    env.TOKEN_STORE.put(totalsKey, JSON.stringify(totals), { expirationTtl: 60 * 60 * 24 * 100 }),
  ]);
  return json({ ok: true, totalMl });
}

async function syncMobileWater(request, env) {
  requireBindings(env);
  const token = readBearerToken(request);
  if (!token) return json({ error: "Uygulama bağlantısı geçersiz." }, 401);
  const tokenHash = await hashToken(token);
  const athleteId = await env.TOKEN_STORE.get(`mobile-session:${tokenHash}`);
  if (!athleteId) return json({ error: "Uygulama bağlantısının süresi doldu. Strava ile yeniden giriş yap." }, 401);

  let input;
  try {
    const body = await readLimitedText(request, 16_384);
    input = JSON.parse(body);
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) return json({ error: "İstek çok büyük." }, 413);
    return json({ error: "Su toplamları okunamadı." }, 400);
  }
  const incoming = input?.totals;
  if (!incoming || typeof incoming !== "object" || Array.isArray(incoming) || Object.keys(incoming).length > 100) {
    return json({ error: "Günlük su toplamları geçersiz." }, 400);
  }

  const now = new Date();
  const latestAllowed = new Date(now);
  latestAllowed.setUTCDate(latestAllowed.getUTCDate() + 1);
  const earliestAllowed = new Date(now);
  earliestAllowed.setUTCDate(earliestAllowed.getUTCDate() - 90);
  const minDay = earliestAllowed.toISOString().slice(0, 10);
  const maxDay = latestAllowed.toISOString().slice(0, 10);
  const clean = {};
  for (const [day, value] of Object.entries(incoming)) {
    const amount = Number(value);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(Date.parse(`${day}T00:00:00Z`)) || new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) !== day || day < minDay || day > maxDay || !Number.isFinite(amount) || amount < 0 || amount > 20000) {
      return json({ error: "Tarih veya su miktarı geçersiz." }, 400);
    }
    clean[day] = Math.round(amount);
  }

  const totalsKey = `health-water-athlete:${athleteId}`;
  const totals = Object.keys(clean).length ? await env.TOKEN_STORE.get(totalsKey, "json") || {} : {};
  Object.assign(totals, clean);
  for (const savedDay of Object.keys(totals)) if (savedDay < minDay) delete totals[savedDay];
  const writes = [Object.keys(clean).length
    ? env.TOKEN_STORE.put(totalsKey, JSON.stringify(totals), { expirationTtl: 60 * 60 * 24 * 100 })
    : env.TOKEN_STORE.delete(totalsKey)];
  await Promise.all(writes);
  return json({ ok: true, syncedDays: Object.keys(clean).length });
}

async function unlinkMobileWater(request, env) {
  requireBindings(env);
  const token = readBearerToken(request);
  if (!token) return json({ error: "Uygulama bağlantısı geçersiz." }, 401);
  const tokenHash = await hashToken(token);
  const athleteId = await env.TOKEN_STORE.get(`mobile-session:${tokenHash}`);
  if (!athleteId) return json({ error: "Uygulama bağlantısının süresi doldu." }, 401);
  const currentHash = await env.TOKEN_STORE.get(`mobile-link-for:${athleteId}`);
  if (currentHash === tokenHash) {
    await Promise.all([
      env.TOKEN_STORE.delete(`mobile-link-for:${athleteId}`),
      env.TOKEN_STORE.delete(`health-water-athlete:${athleteId}`),
    ]);
  }
  return json({ ok: true });
}

async function getWaterState(request, env) {
  requireBindings(env);
  const sessionId = readCookie(request, SESSION_COOKIE);
  const session = sessionId ? await env.TOKEN_STORE.get(`session:${sessionId}`, "json") : null;
  if (!session?.refresh_token) {
    return json({ error: "Önce Strava hesabını bağla." }, 401);
  }
  const athleteId = session.athlete_id ? String(session.athlete_id) : "";
  const [legacyTotals, linkHash, mobileHash, athleteTotals] = await Promise.all([
    env.TOKEN_STORE.get(`health-water:${sessionId}`, "json"),
    env.TOKEN_STORE.get(`health-water-link-for:${sessionId}`),
    athleteId ? env.TOKEN_STORE.get(`mobile-link-for:${athleteId}`) : null,
    athleteId ? env.TOKEN_STORE.get(`health-water-athlete:${athleteId}`, "json") : null,
  ]);
  if (linkHash) await env.TOKEN_STORE.put(`health-water-link:${linkHash}`, sessionId, { expirationTtl: SESSION_SECONDS });
  return json({
    linked: Boolean(linkHash || mobileHash),
    source: mobileHash ? "iphone" : linkHash ? "shortcut" : null,
    totals: { ...(legacyTotals || {}), ...(athleteTotals || {}) },
  });
}

async function createWaterPair(request, url, env) {
  requireBindings(env);
  if (request.headers.get("Origin") !== url.origin) return json({ error: "İstek doğrulanamadı." }, 403);
  const sessionId = readCookie(request, SESSION_COOKIE);
  if (!sessionId || !await env.TOKEN_STORE.get(`session:${sessionId}`, "json")) {
    return json({ error: "Önce Strava hesabını bağla." }, 401);
  }

  const oldHash = await env.TOKEN_STORE.get(`health-water-link-for:${sessionId}`);
  if (oldHash) await env.TOKEN_STORE.delete(`health-water-link:${oldHash}`);
  const token = randomToken();
  const tokenHash = await hashToken(token);
  await env.TOKEN_STORE.put(`health-water-link:${tokenHash}`, sessionId, { expirationTtl: SESSION_SECONDS });
  await env.TOKEN_STORE.put(`health-water-link-for:${sessionId}`, tokenHash, { expirationTtl: SESSION_SECONDS });
  return json({ token });
}

async function unlinkWaterPair(request, url, env) {
  requireBindings(env);
  if (request.headers.get("Origin") !== url.origin) return json({ error: "İstek doğrulanamadı." }, 403);
  const sessionId = readCookie(request, SESSION_COOKIE);
  if (!sessionId || !await env.TOKEN_STORE.get(`session:${sessionId}`, "json")) {
    return json({ error: "Önce Strava hesabını bağla." }, 401);
  }
  const tokenHash = await env.TOKEN_STORE.get(`health-water-link-for:${sessionId}`);
  if (tokenHash) await env.TOKEN_STORE.delete(`health-water-link:${tokenHash}`);
  const session = await env.TOKEN_STORE.get(`session:${sessionId}`, "json");
  const athleteId = session?.athlete_id ? String(session.athlete_id) : "";
  const mobileHash = athleteId ? await env.TOKEN_STORE.get(`mobile-link-for:${athleteId}`) : null;
  const deletes = [
    env.TOKEN_STORE.delete(`health-water-link-for:${sessionId}`),
    env.TOKEN_STORE.delete(`health-water:${sessionId}`),
  ];
  if (athleteId) {
    deletes.push(env.TOKEN_STORE.delete(`health-water-athlete:${athleteId}`));
    if (mobileHash) deletes.push(env.TOKEN_STORE.delete(`mobile-session:${mobileHash}`), env.TOKEN_STORE.delete(`mobile-link-for:${athleteId}`));
  }
  await Promise.all(deletes);
  return json({ ok: true });
}

async function syncWaterTotal(request, env) {
  requireBindings(env);
  const match = (request.headers.get("Authorization") || "").match(/^Bearer ([a-f0-9]{64})$/i);
  if (!match) return json({ error: "Kestirme anahtarı eksik veya geçersiz." }, 401);

  let input;
  try {
    const body = await readLimitedText(request, 2048);
    input = JSON.parse(body);
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) return json({ error: "İstek çok büyük." }, 413);
    return json({ error: "Günlük su toplamı okunamadı." }, 400);
  }

  const day = typeof input?.date === "string" ? input.date : "";
  const totalMl = input?.totalMl;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(Date.parse(`${day}T00:00:00Z`)) || new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) !== day || typeof totalMl !== "number" || !Number.isFinite(totalMl) || totalMl < 0 || totalMl > 20000) {
    return json({ error: "Tarih veya su toplamı geçersiz." }, 400);
  }
  const now = new Date();
  const latestAllowed = new Date(now);
  latestAllowed.setUTCDate(latestAllowed.getUTCDate() + 1);
  const earliestAllowed = new Date(now);
  earliestAllowed.setUTCDate(earliestAllowed.getUTCDate() - 90);
  if (day > latestAllowed.toISOString().slice(0, 10) || day < earliestAllowed.toISOString().slice(0, 10)) {
    return json({ error: "Yalnızca son 90 günün su toplamı eşitlenebilir." }, 400);
  }

  const tokenHash = await hashToken(match[1]);
  const sessionId = await env.TOKEN_STORE.get(`health-water-link:${tokenHash}`);
  if (!sessionId) return json({ error: "Kestirme bağlantısı süresi dolmuş. Siteden yeni anahtar oluştur." }, 401);
  const session = await env.TOKEN_STORE.get(`session:${sessionId}`, "json");
  if (!session?.refresh_token) {
    await env.TOKEN_STORE.delete(`health-water-link:${tokenHash}`);
    return json({ error: "Strava bağlantısı süresi dolmuş. Siteden yeniden bağlan." }, 401);
  }

  const totals = await env.TOKEN_STORE.get(`health-water:${sessionId}`, "json") || {};
  totals[day] = Math.round(totalMl);
  for (const savedDay of Object.keys(totals)) {
    if (savedDay < earliestAllowed.toISOString().slice(0, 10)) delete totals[savedDay];
  }
  await Promise.all([
    env.TOKEN_STORE.put(`health-water:${sessionId}`, JSON.stringify(totals), { expirationTtl: 60 * 60 * 24 * 100 }),
    env.TOKEN_STORE.put(`health-water-link:${tokenHash}`, sessionId, { expirationTtl: SESSION_SECONDS }),
    env.TOKEN_STORE.put(`health-water-link-for:${sessionId}`, tokenHash, { expirationTtl: SESSION_SECONDS }),
    env.TOKEN_STORE.put(`session:${sessionId}`, JSON.stringify(session), { expirationTtl: SESSION_SECONDS }),
  ]);
  return json({ ok: true, date: day, totalMl: Math.round(totalMl) });
}

async function hashToken(token) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256Base64Url(value) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  let binary = "";
  for (const byte of digest) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function readBearerToken(request) {
  const match = (request.headers.get("Authorization") || "").match(/^Bearer ([a-f0-9]{64})$/i);
  return match ? match[1] : "";
}

async function logout(request, env) {
  requireBindings(env);
  const sessionId = readCookie(request, SESSION_COOKIE);
  let stravaRevoked = true;
  if (sessionId) {
    const saved = await env.TOKEN_STORE.get(`session:${sessionId}`, "json");
    if (saved?.athlete_id) {
      if (saved.refresh_token) stravaRevoked = await revokeStravaRefreshToken(env, saved.refresh_token);
      await clearStravaAthleteData(env, saved.athlete_id);
    } else {
      const waterHash = await env.TOKEN_STORE.get(`health-water-link-for:${sessionId}`);
      await Promise.all([
        env.TOKEN_STORE.delete(`session:${sessionId}`),
        env.TOKEN_STORE.delete(`dashboard:v2:${sessionId}`),
        env.TOKEN_STORE.delete(`health-water-link:${waterHash || ""}`),
        env.TOKEN_STORE.delete(`health-water-link-for:${sessionId}`),
        env.TOKEN_STORE.delete(`health-water:${sessionId}`),
      ]);
    }
  }
  const response = json({ ok: true, stravaRevoked });
  response.headers.append("Set-Cookie", cookie(SESSION_COOKIE, "", 0, "/"));
  return response;
}

function isStravaWebhookPath(url, env) {
  return Boolean(env.STRAVA_WEBHOOK_PATH_SECRET)
    && url.pathname === `/webhooks/strava/${env.STRAVA_WEBHOOK_PATH_SECRET}`;
}

function verifyStravaWebhook(url, env) {
  const mode = url.searchParams.get("hub.mode");
  const token = url.searchParams.get("hub.verify_token");
  const challenge = url.searchParams.get("hub.challenge");
  if (!env.STRAVA_WEBHOOK_VERIFY_TOKEN || !env.TOKEN_STORE) return json({ error: "Strava webhook doğrulaması yapılandırılmadı." }, 503);
  if (mode !== "subscribe" || token !== env.STRAVA_WEBHOOK_VERIFY_TOKEN || !challenge) {
    return json({ error: "Strava webhook doğrulaması reddedildi." }, 403);
  }
  return json({ "hub.challenge": challenge });
}

async function receiveStravaWebhook(request, env, ctx) {
  if (!env.STRAVA_WEBHOOK_VERIFY_TOKEN || !env.TOKEN_STORE) {
    return json({ error: "Strava webhook doğrulaması yapılandırılmadı." }, 503);
  }
  let event;
  try {
    const body = await readLimitedText(request, 8192);
    event = JSON.parse(body);
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) return json({ error: "Webhook isteği çok büyük." }, 413);
    return json({ error: "Webhook isteği geçersiz." }, 400);
  }
  const ownerId = String(event?.owner_id ?? "");
  const objectId = String(event?.object_id ?? "");
  if (!/^\d{1,20}$/.test(ownerId) || !["activity", "athlete"].includes(event?.object_type)
      || !["create", "update", "delete"].includes(event?.aspect_type)) {
    return json({ error: "Webhook olayı geçersiz." }, 400);
  }

  let work;
  if (event.object_type === "athlete" && event.aspect_type === "update"
      && String(event?.updates?.authorized).toLowerCase() === "false") {
    work = clearStravaAthleteData(env, objectId || ownerId);
  } else if (event.object_type === "activity" && /^\d{1,20}$/.test(objectId)) {
    work = invalidateStravaDashboards(env, ownerId);
  }
  if (work) {
    if (ctx?.waitUntil) {
      ctx.waitUntil(work.catch(error => console.error("Strava webhook cleanup failed:", error?.message || "unknown error")));
    } else {
      await work;
    }
  }
  return json({ ok: true });
}

async function rememberWebSession(env, athleteId, sessionId) {
  const key = `strava-web-sessions:${athleteId}`;
  const current = await env.TOKEN_STORE.get(key, "json");
  const sessions = Array.isArray(current) ? current.filter(value => typeof value === "string") : [];
  if (!sessions.includes(sessionId)) sessions.push(sessionId);
  await env.TOKEN_STORE.put(key, JSON.stringify(sessions), { expirationTtl: SESSION_SECONDS });
}

async function forgetWebSession(env, athleteId, sessionId) {
  const key = `strava-web-sessions:${athleteId}`;
  const current = await env.TOKEN_STORE.get(key, "json");
  const sessions = Array.isArray(current) ? current.filter(value => value !== sessionId) : [];
  if (sessions.length) await env.TOKEN_STORE.put(key, JSON.stringify(sessions), { expirationTtl: SESSION_SECONDS });
  else await env.TOKEN_STORE.delete(key);
}

async function invalidateStravaDashboards(env, athleteId) {
  const sessionIds = await env.TOKEN_STORE.get(`strava-web-sessions:${athleteId}`, "json");
  const deletes = [env.TOKEN_STORE.delete(`mobile-dashboard:v3:${athleteId}`)];
  if (Array.isArray(sessionIds)) {
    deletes.push(...sessionIds.filter(value => typeof value === "string").map(sessionId =>
      env.TOKEN_STORE.delete(`dashboard:v2:${sessionId}`)));
  }
  await Promise.all(deletes);
}

async function clearStravaAthleteData(env, athleteId) {
  await invalidateStravaDashboards(env, athleteId);
  const accountId = await env.TOKEN_STORE.get(`strava-account:${athleteId}`);
  const mobileHash = await env.TOKEN_STORE.get(`mobile-link-for:${athleteId}`);
  const indexedSessions = await env.TOKEN_STORE.get(`strava-web-sessions:${athleteId}`, "json");
  const legacySessions = await findLegacyWebSessions(env, athleteId);
  const sessionIds = [...new Set([
    ...(Array.isArray(indexedSessions) ? indexedSessions.filter(value => typeof value === "string") : []),
    ...legacySessions,
  ])];
  const keys = [
    `strava-account:${athleteId}`,
    `account-strava:${accountId || ""}`,
    `mobile-strava:${athleteId}`,
    `mobile-link-for:${athleteId}`,
    `mobile-session:${mobileHash || ""}`,
    `mobile-health:${athleteId}`,
    `health-water-athlete:${athleteId}`,
    `strava-web-sessions:${athleteId}`,
  ];
  if (Array.isArray(sessionIds)) {
    for (const sessionId of sessionIds) {
      if (typeof sessionId !== "string") continue;
      keys.push(`session:${sessionId}`, `dashboard:v2:${sessionId}`);
      const waterHash = await env.TOKEN_STORE.get(`health-water-link-for:${sessionId}`);
      keys.push(`health-water-link-for:${sessionId}`, `health-water-link:${waterHash || ""}`, `health-water:${sessionId}`);
    }
  }
  await Promise.all([...new Set(keys)].map(key => env.TOKEN_STORE.delete(key)));
}

async function findLegacyWebSessions(env, athleteId) {
  const matches = [];
  let cursor;
  do {
    const page = await env.TOKEN_STORE.list({ prefix: "session:", limit: 1000, ...(cursor ? { cursor } : {}) });
    const sessions = await Promise.all(page.keys.map(async entry => {
      const sessionId = entry.name.slice("session:".length);
      const record = await env.TOKEN_STORE.get(entry.name, "json");
      return String(record?.athlete_id ?? "") === String(athleteId) ? sessionId : null;
    }));
    matches.push(...sessions.filter(Boolean));
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return matches;
}

async function stravaToken(fields) {
  const response = await fetch("https://www.strava.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields),
  });
  if (!response.ok) {
    console.error("Strava token request failed with status:", response.status);
    const error = new Error("Strava token request failed");
    error.tempoDiagnostic = `strava-token-${response.status}`;
    throw error;
  }
  return response.json();
}

async function stravaAccessToken(env, sessionKey, saved, sessionTtl) {
  const now = Math.floor(Date.now() / 1000);
  if (saved?.access_token && Number(saved.expires_at) > now + 60) return saved.access_token;

  const pending = stravaRefreshInFlight.get(sessionKey);
  if (pending) return pending;

  const refresh = (async () => {
    let current = await env.TOKEN_STORE.get(sessionKey, "json") || saved;
    const currentExpiry = Number(current?.expires_at) || 0;
    if (current?.access_token && currentExpiry > Math.floor(Date.now() / 1000) + 60) {
      return current.access_token;
    }
    if (!current?.refresh_token) throw new Error("Strava refresh token is missing");

    let tokens;
    try {
      tokens = await stravaToken({
        client_id: env.STRAVA_CLIENT_ID,
        client_secret: env.STRAVA_CLIENT_SECRET,
        grant_type: "refresh_token",
        refresh_token: current.refresh_token,
      });
    } catch (error) {
      // Another Worker instance may have rotated the token at the same time.
      await new Promise(resolve => setTimeout(resolve, 120));
      current = await env.TOKEN_STORE.get(sessionKey, "json") || current;
      const racedExpiry = Number(current?.expires_at) || 0;
      if (current?.access_token && racedExpiry > Math.floor(Date.now() / 1000) + 60) {
        return current.access_token;
      }
      if (!current?.refresh_token || current.refresh_token === saved?.refresh_token) throw error;
      tokens = await stravaToken({
        client_id: env.STRAVA_CLIENT_ID,
        client_secret: env.STRAVA_CLIENT_SECRET,
        grant_type: "refresh_token",
        refresh_token: current.refresh_token,
      });
    }

    const updated = {
      ...current,
      refresh_token: tokens.refresh_token || current.refresh_token,
      access_token: tokens.access_token,
      expires_at: Number(tokens.expires_at) || 0,
    };
    await env.TOKEN_STORE.put(sessionKey, JSON.stringify(updated), { expirationTtl: sessionTtl });
    return updated.access_token;
  })();
  stravaRefreshInFlight.set(sessionKey, refresh);
  try {
    return await refresh;
  } finally {
    if (stravaRefreshInFlight.get(sessionKey) === refresh) stravaRefreshInFlight.delete(sessionKey);
  }
}

function requireBindings(env) {
  if (!env.STRAVA_CLIENT_ID || !env.STRAVA_CLIENT_SECRET || !env.TOKEN_STORE || !env.ASSETS) {
    throw new Error("Required Worker secrets or bindings are missing");
  }
}

function json(value, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...extraHeaders,
    },
  });
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sealOAuthState(env, value) {
  const label = "Tempo Strava OAuth state v1";
  const keyDigest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${label}:${env.STRAVA_CLIENT_SECRET}`));
  const key = await crypto.subtle.importKey("raw", keyDigest, "AES-GCM", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const payload = new TextEncoder().encode(JSON.stringify({ ...value, expiresAt: Math.floor(Date.now() / 1000) + 600 }));
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: new TextEncoder().encode(label) }, key, payload));
  const envelope = new Uint8Array(iv.length + ciphertext.length);
  envelope.set(iv);
  envelope.set(ciphertext, iv.length);
  let binary = "";
  for (const byte of envelope) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function openOAuthState(env, value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{40,512}$/.test(value)) return null;
  try {
    const label = "Tempo Strava OAuth state v1";
    const keyDigest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${label}:${env.STRAVA_CLIENT_SECRET}`));
    const key = await crypto.subtle.importKey("raw", keyDigest, "AES-GCM", false, ["decrypt"]);
    const base64 = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - value.length % 4) % 4);
    const binary = atob(base64);
    if (binary.length < 28) return null;
    const envelope = Uint8Array.from(binary, character => character.charCodeAt(0));
    const plaintext = await crypto.subtle.decrypt({
      name: "AES-GCM",
      iv: envelope.slice(0, 12),
      additionalData: new TextEncoder().encode(label),
    }, key, envelope.slice(12));
    const payload = JSON.parse(new TextDecoder().decode(plaintext));
    const now = Math.floor(Date.now() / 1000);
    if (!Number.isInteger(payload?.expiresAt) || payload.expiresAt <= now || payload.expiresAt > now + 600) return null;
    return payload;
  } catch {
    return null;
  }
}

function readCookie(request, name) {
  const header = request.headers.get("Cookie") || "";
  for (const part of header.split(";")) {
    const [key, ...value] = part.trim().split("=");
    if (key === name) return decodeURIComponent(value.join("="));
  }
  return "";
}

function cookie(name, value, maxAge, path) {
  return `${name}=${encodeURIComponent(value)}; Max-Age=${maxAge}; Path=${path}; Secure; HttpOnly; SameSite=Lax`;
}
