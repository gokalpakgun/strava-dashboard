const SESSION_COOKIE = "tempo_session";
const STATE_COOKIE = "tempo_oauth_state";
const SESSION_SECONDS = 60 * 60 * 24 * 30;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/auth/start" && request.method === "GET") {
        return startAuthorization(url, env);
      }
      if (url.pathname === "/auth/callback" && request.method === "GET") {
        return completeAuthorization(request, url, env);
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
      if (url.pathname.startsWith("/api/") || url.pathname.startsWith("/auth/")) {
        return json({ error: "Not found" }, 404);
      }
      return env.ASSETS.fetch(request);
    } catch (error) {
      console.error("Tempo Worker request failed:", error?.message || "unknown error");
      if (url.pathname.startsWith("/api/")) {
        return json({ error: "İstek tamamlanamadı. Biraz sonra tekrar deneyin." }, 502);
      }
      return new Response("Bağlantı sırasında bir sorun oluştu. Lütfen yeniden deneyin.", {
        status: 502,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
      });
    }
  },
};

async function startAuthorization(url, env) {
  requireBindings(env);
  const state = randomToken();
  const sessionId = randomToken();
  await env.TOKEN_STORE.put(`state:${state}`, sessionId, { expirationTtl: 600 });
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
      "Set-Cookie": cookie(STATE_COOKIE, state, 600, "/auth/callback"),
    },
  });
}

async function completeAuthorization(request, url, env) {
  requireBindings(env);
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  const stateCookie = readCookie(request, STATE_COOKIE);
  if (!state || !code || !stateCookie || state !== stateCookie) {
    return new Response("Strava bağlantısı doğrulanamadı. Lütfen yeniden deneyin.", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  const sessionId = await env.TOKEN_STORE.get(`state:${state}`);
  if (!sessionId) {
    return new Response("Bağlantı isteğinin süresi doldu. Lütfen yeniden deneyin.", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  await env.TOKEN_STORE.delete(`state:${state}`);

  const tokens = await stravaToken({
    client_id: env.STRAVA_CLIENT_ID,
    client_secret: env.STRAVA_CLIENT_SECRET,
    code,
    grant_type: "authorization_code",
  });
  await env.TOKEN_STORE.put(`session:${sessionId}`, JSON.stringify({
    refresh_token: tokens.refresh_token,
    athlete_id: tokens.athlete?.id ?? null,
  }), { expirationTtl: SESSION_SECONDS });

  const headers = new Headers({ Location: `${url.origin}/?connected=1`, "Cache-Control": "no-store" });
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

  const tokens = await stravaToken({
    client_id: env.STRAVA_CLIENT_ID,
    client_secret: env.STRAVA_CLIENT_SECRET,
    grant_type: "refresh_token",
    refresh_token: saved.refresh_token,
  });
  await env.TOKEN_STORE.put(`session:${sessionId}`, JSON.stringify({
    refresh_token: tokens.refresh_token,
    athlete_id: saved.athlete_id,
  }), { expirationTtl: SESSION_SECONDS });

  const response = await fetch("https://www.strava.com/api/v3/athlete/activities?per_page=100", {
    headers: { Authorization: `Bearer ${tokens.access_token}` },
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

  const cacheKey = `dashboard:${sessionId}`;
  const cached = await env.TOKEN_STORE.get(cacheKey, "json");
  if (cached) return json(cached);

  const saved = await env.TOKEN_STORE.get(`session:${sessionId}`, "json");
  if (!saved?.refresh_token) return json({ error: "Strava bağlantısı gerekli" }, 401);

  const tokens = await stravaToken({
    client_id: env.STRAVA_CLIENT_ID,
    client_secret: env.STRAVA_CLIENT_SECRET,
    grant_type: "refresh_token",
    refresh_token: saved.refresh_token,
  });
  await env.TOKEN_STORE.put(`session:${sessionId}`, JSON.stringify({
    refresh_token: tokens.refresh_token,
    athlete_id: tokens.athlete?.id ?? saved.athlete_id,
  }), { expirationTtl: SESSION_SECONDS });

  const headers = { Authorization: `Bearer ${tokens.access_token}` };
  const [athleteResponse, segmentsResponse] = await Promise.all([
    fetch("https://www.strava.com/api/v3/athlete", { headers }),
    fetch("https://www.strava.com/api/v3/segments/starred?per_page=100", { headers }),
  ]);
  if (!athleteResponse.ok) {
    console.error("Strava athlete request failed with status:", athleteResponse.status);
    return json({ error: "Strava profil veya aktiviteleri alınamadı." }, 502);
  }

  const athlete = await athleteResponse.json();
  const activities = [];
  const perPage = 100;
  const maxPages = 10;
  for (let page = 1; page <= maxPages; page += 1) {
    const response = await fetch(`https://www.strava.com/api/v3/athlete/activities?page=${page}&per_page=${perPage}`, { headers });
    if (!response.ok) {
      console.error("Strava activities request failed with status:", response.status);
      return json({ error: "Strava aktiviteleri alınamadı." }, response.status === 429 ? 429 : 502);
    }
    const pageActivities = await response.json();
    activities.push(...pageActivities);
    if (pageActivities.length < perPage) break;
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
    historyLimited: activities.length === perPage * maxPages,
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

async function logout(request, env) {
  requireBindings(env);
  const sessionId = readCookie(request, SESSION_COOKIE);
  if (sessionId) await env.TOKEN_STORE.delete(`session:${sessionId}`);
  return new Response(null, {
    status: 204,
    headers: { "Cache-Control": "no-store", "Set-Cookie": cookie(SESSION_COOKIE, "", 0, "/") },
  });
}

async function stravaToken(fields) {
  const response = await fetch("https://www.strava.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields),
  });
  if (!response.ok) {
    const details = (await response.text()).slice(0, 1000);
    console.error("Strava token request failed:", response.status, details);
    throw new Error(`Strava token request failed (${response.status})`);
  }
  return response.json();
}

function requireBindings(env) {
  if (!env.STRAVA_CLIENT_ID || !env.STRAVA_CLIENT_SECRET || !env.TOKEN_STORE || !env.ASSETS) {
    throw new Error("Required Worker secrets or bindings are missing");
  }
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
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
