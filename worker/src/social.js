import { accountContext } from "./account.js";
import { readLimitedText, RequestBodyTooLargeError } from "./http.js";

const MAX_FRIENDS = 100;
const MAX_PENDING = 50;
const MAX_CHALLENGE_MEMBERS = 21;
const CHALLENGE_SECONDS = 60 * 60 * 24 * 7;

export async function handleSocialRequest(request, env, url) {
  if (!env.TOKEN_STORE) return json({ error: "Hesap depolama bağlantısı hazır değil." }, 503);
  const account = await accountContext(request, env);
  if (account.response) return account.response;
  const userId = account.user.id;
  const root = "/api/account/social";

  if (url.pathname === root && request.method === "GET") return loadSnapshot(env, account.user);
  if (url.pathname === root + "/friends" && request.method === "POST") return sendFriendRequest(request, env, account.user);
  if (url.pathname === root + "/requests" && request.method === "POST") return respondToFriendRequest(request, env, account.user);
  if (url.pathname === root + "/challenges" && request.method === "POST") return createChallenge(request, env, account.user);
  const match = url.pathname.match(/^\/api\/account\/social\/challenges\/([a-f0-9-]{20,64})$/i);
  if (match && request.method === "POST") return updateChallenge(request, env, account.user, match[1]);
  if (url.pathname === root && request.method !== "GET") return json({ error: "Bu sosyal işlem desteklenmiyor." }, 405);
  return null;
}

export async function deleteSocialAccount(env, userId) {
  const state = await readState(env, userId);
  const related = new Set([...state.incoming, ...state.outgoing]);
  const requests = await Promise.all([...related].map(id => loadRequest(env, id)));
  const affectedUsers = new Set([
    ...state.friends,
    ...requests.flatMap(record => record ? [record.from, record.to] : []),
  ]);
  await Promise.all([...affectedUsers].filter(id => id && id !== userId).map(async otherId => {
    const otherState = await readState(env, otherId);
    otherState.friends = otherState.friends.filter(id => id !== userId);
    otherState.incoming = otherState.incoming.filter(id => !related.has(id));
    otherState.outgoing = otherState.outgoing.filter(id => !related.has(id));
    await saveState(env, otherId, otherState);
  }));
  await Promise.all([...related].map(id => env.TOKEN_STORE.delete("social-request:" + id)));
  await Promise.all(state.challenges.map(async id => {
    const key = "social-challenge:" + id;
    const challenge = await loadChallenge(env, id);
    if (!challenge) return;
    const otherIds = challenge.participants.map(item => item.userId).filter(id => id !== userId);
    if (challenge.creatorId === userId) {
      await env.TOKEN_STORE.delete(key);
      await Promise.all(otherIds.map(async otherId => {
        const otherState = await readState(env, otherId);
        otherState.challenges = otherState.challenges.filter(value => value !== id);
        await saveState(env, otherId, otherState);
      }));
    } else {
      challenge.participants = challenge.participants.filter(item => item.userId !== userId);
      await env.TOKEN_STORE.put(key, JSON.stringify(challenge), { expirationTtl: Math.max(60, Math.ceil((Date.parse(challenge.endsAt) - Date.now()) / 1000) + 60 * 60 * 24 * 14) });
    }
  }));
  await env.TOKEN_STORE.delete("social-state:" + userId);
}

async function loadSnapshot(env, user) {
  const state = await readState(env, user.id);
  const [friends, incoming, outgoing, challengeRecords] = await Promise.all([
    Promise.all(state.friends.slice(0, MAX_FRIENDS).map(id => loadPublicUser(env, id))),
    Promise.all(state.incoming.slice(0, MAX_PENDING).map(id => loadRequest(env, id))),
    Promise.all(state.outgoing.slice(0, MAX_PENDING).map(id => loadRequest(env, id))),
    Promise.all(state.challenges.slice(0, 40).map(id => loadChallenge(env, id))),
  ]);
  const activeIds = challengeRecords.filter(challenge => challenge && Date.parse(challenge.endsAt) > Date.now()).map(challenge => challenge.id);
  if (activeIds.length !== state.challenges.length) {
    state.challenges = activeIds;
    await saveState(env, user.id, state);
  }
  const activeChallenges = (await Promise.all(challengeRecords.map(async challenge => {
    if (!challenge || Date.parse(challenge.endsAt) <= Date.now() || !challenge.participants.some(item => item.userId === user.id)) return null;
    return presentChallenge(env, challenge, user.id);
  }))).filter(Boolean);
  return json({
    profile: publicProfile(user),
    friends: friends.filter(Boolean),
    incoming: (await Promise.all(incoming.filter(item => item?.status === "pending" && item.to === user.id).map(async item => ({
      id: item.id, createdAt: item.createdAt, user: await loadPublicUser(env, item.from),
    })))).filter(item => item.user),
    outgoing: (await Promise.all(outgoing.filter(item => item?.status === "pending" && item.from === user.id).map(async item => ({
      id: item.id, createdAt: item.createdAt, user: await loadPublicUser(env, item.to),
    })))).filter(item => item.user),
    challenges: activeChallenges,
  });
}

async function sendFriendRequest(request, env, user) {
  const body = await readBody(request, 512);
  if (body.error) return body.error;
  const username = normalizeUsername(body.value.username);
  if (!/^[a-z0-9_]{3,24}$/.test(username)) return json({ error: "Geçerli bir kullanıcı adı yaz." }, 400);
  if (username === user.username) return json({ error: "Kendine arkadaşlık isteği gönderemezsin." }, 400);
  const throttleKey = "social-request-cooldown:" + user.id;
  if (await env.TOKEN_STORE.get(throttleKey)) return json({ error: "Yeni istek göndermeden önce biraz bekle." }, 429);
  await env.TOKEN_STORE.put(throttleKey, "1", { expirationTtl: 2 });
  const friendId = await env.TOKEN_STORE.get("account-username:" + username);
  const friend = friendId ? await env.TOKEN_STORE.get("account-user:" + friendId, "json") : null;
  if (!friend) return json({ error: "Bu kullanıcı adına sahip Tempo hesabı bulunamadı." }, 404);
  const [mine, theirs] = await Promise.all([readState(env, user.id), readState(env, friend.id)]);
  if (mine.friends.includes(friend.id)) return json({ error: "Bu kişi zaten arkadaş listende." }, 409);
  if (mine.outgoing.length >= MAX_PENDING || theirs.incoming.length >= MAX_PENDING) {
    return json({ error: "Bekleyen arkadaşlık isteği sınırına ulaşıldı." }, 429);
  }
  const existingRequest = await findRequestBetween(env, mine, theirs, user.id, friend.id);
  if (existingRequest) return json({ error: "Bu kişiye zaten bekleyen bir istek var." }, 409);
  const id = crypto.randomUUID();
  const record = { id, from: user.id, to: friend.id, status: "pending", createdAt: new Date().toISOString() };
  mine.outgoing.unshift(id);
  theirs.incoming.unshift(id);
  await Promise.all([
    env.TOKEN_STORE.put("social-request:" + id, JSON.stringify(record), { expirationTtl: 60 * 60 * 24 * 90 }),
    saveState(env, user.id, mine), saveState(env, friend.id, theirs),
  ]);
  return json({ ok: true, requestId: id, user: publicProfile(friend) }, 201);
}

async function respondToFriendRequest(request, env, user) {
  const body = await readBody(request, 1024);
  if (body.error) return body.error;
  const id = typeof body.value.requestId === "string" ? body.value.requestId : "";
  const action = body.value.action;
  if (!/^[a-f0-9-]{20,64}$/i.test(id) || !["accept", "decline"].includes(action)) {
    return json({ error: "Arkadaşlık isteği geçersiz." }, 400);
  }
  const key = "social-request:" + id;
  const record = await env.TOKEN_STORE.get(key, "json");
  if (!record || record.to !== user.id || record.status !== "pending") return json({ error: "Bekleyen arkadaşlık isteği bulunamadı." }, 404);
  const [mine, theirs] = await Promise.all([readState(env, user.id), readState(env, record.from)]);
  mine.incoming = mine.incoming.filter(value => value !== id);
  theirs.outgoing = theirs.outgoing.filter(value => value !== id);
  if (action === "accept") {
    if (mine.friends.length >= MAX_FRIENDS || theirs.friends.length >= MAX_FRIENDS) return json({ error: "Arkadaş listesi sınırına ulaşıldı." }, 409);
    if (!mine.friends.includes(record.from)) mine.friends.unshift(record.from);
    if (!theirs.friends.includes(user.id)) theirs.friends.unshift(user.id);
  }
  // Once both indexes have been updated, the request record is no longer needed.
  await Promise.all([env.TOKEN_STORE.delete(key), saveState(env, user.id, mine), saveState(env, record.from, theirs)]);
  return json({ ok: true });
}

async function createChallenge(request, env, user) {
  const body = await readBody(request, 4096);
  if (body.error) return body.error;
  const title = typeof body.value.title === "string" ? body.value.title.trim().slice(0, 60) : "";
  const metric = body.value.metric;
  const friendIds = Array.isArray(body.value.friendIds) ? [...new Set(body.value.friendIds.filter(value => typeof value === "string"))] : [];
  if (!title) return json({ error: "Yarışmaya kısa bir ad ver." }, 400);
  if (!["steps", "exerciseMinutes"].includes(metric)) return json({ error: "Yarışma yalnızca adım veya egzersiz dakikası üzerinden olabilir." }, 400);
  if (friendIds.length < 1 || friendIds.length > MAX_CHALLENGE_MEMBERS - 1) return json({ error: "En az bir arkadaş seç; yarışmaya en fazla 20 arkadaş eklenebilir." }, 400);
  const state = await readState(env, user.id);
  await pruneExpiredChallenges(env, user.id, state);
  if (friendIds.some(id => !state.friends.includes(id))) return json({ error: "Yarışmaya yalnızca arkadaş listendeki kişileri ekleyebilirsin." }, 403);
  if (state.challenges.length >= 40) return json({ error: "Aktif yarışma sınırına ulaştın." }, 429);
  const now = new Date();
  const startsAt = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
  const endsAt = new Date(startsAt.getTime() + CHALLENGE_SECONDS * 1000);
  const id = crypto.randomUUID();
  const participants = [{ userId: user.id, status: "accepted", shareHealth: false, joinedAt: now.toISOString() }]
    .concat(friendIds.map(userId => ({ userId, status: "invited", shareHealth: false, invitedAt: now.toISOString() })));
  const challenge = { id, creatorId: user.id, title, metric, startsAt: startsAt.toISOString(), endsAt: endsAt.toISOString(), participants };
  state.challenges.unshift(id);
  await Promise.all([
    env.TOKEN_STORE.put("social-challenge:" + id, JSON.stringify(challenge), { expirationTtl: CHALLENGE_SECONDS + 60 * 60 * 24 * 14 }),
    saveState(env, user.id, state),
    ...friendIds.map(async friendId => {
      const friendState = await readState(env, friendId);
      friendState.challenges.unshift(id);
      await saveState(env, friendId, friendState);
    }),
  ]);
  return json({ ok: true, challenge: await presentChallenge(env, challenge, user.id) }, 201);
}

async function updateChallenge(request, env, user, id) {
  const key = "social-challenge:" + id;
  const challenge = await loadChallenge(env, id);
  if (!challenge) return json({ error: "Yarışma bulunamadı veya süresi doldu." }, 404);
  const participant = challenge.participants.find(item => item.userId === user.id);
  if (!participant) return json({ error: "Bu yarışmaya davetin yok." }, 403);
  const body = await readBody(request, 1024);
  if (body.error) return body.error;
  if (body.value.action === "accept" || body.value.action === "decline") {
    if (participant.status !== "invited") return json({ error: "Bu davet daha önce yanıtlanmış." }, 409);
    participant.status = body.value.action === "accept" ? "accepted" : "declined";
    participant.respondedAt = new Date().toISOString();
    participant.shareHealth = false;
  } else if (body.value.action === "share") {
    if (participant.status !== "accepted" || typeof body.value.share !== "boolean") return json({ error: "Önce yarışma davetini kabul et." }, 400);
    participant.shareHealth = body.value.share;
  } else {
    return json({ error: "Yarışma işlemi geçersiz." }, 400);
  }
  await env.TOKEN_STORE.put(key, JSON.stringify(challenge), { expirationTtl: Math.max(60, Math.ceil((Date.parse(challenge.endsAt) - Date.now()) / 1000) + 60 * 60 * 24 * 14) });
  return json({ ok: true, challenge: await presentChallenge(env, challenge, user.id) });
}

async function presentChallenge(env, challenge, viewerId) {
  const participants = await Promise.all(challenge.participants.map(async participant => {
    const profile = await loadPublicUser(env, participant.userId);
    const result = {
      userId: participant.userId,
      status: participant.status,
      shareHealth: participant.shareHealth === true,
      user: profile,
      score: null,
    };
    if (profile && participant.status === "accepted" && participant.shareHealth === true) {
      result.score = await challengeScore(env, participant.userId, challenge);
    }
    return result;
  }));
  return {
    id: challenge.id,
    myUserId: viewerId,
    title: challenge.title,
    metric: challenge.metric,
    startsAt: challenge.startsAt,
    endsAt: challenge.endsAt,
    myStatus: challenge.participants.find(item => item.userId === viewerId)?.status ?? "none",
    myShareHealth: challenge.participants.find(item => item.userId === viewerId)?.shareHealth === true,
    participants: participants.filter(item => item.user),
  };
}

async function challengeScore(env, userId, challenge) {
  const health = await env.TOKEN_STORE.get("account-health:" + userId, "json");
  const startDay = challenge.startsAt.slice(0, 10);
  const endDayExclusive = challenge.endsAt.slice(0, 10);
  let total = 0;
  let hasMeasurement = false;
  for (const [day, values] of Object.entries(health?.days || {})) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < startDay || day >= endDayExclusive || Date.now() < Date.parse(challenge.startsAt)) continue;
    const value = Number(values?.[challenge.metric]);
    if (Number.isFinite(value) && value >= 0) { total += value; hasMeasurement = true; }
  }
  return hasMeasurement ? Math.round(total) : null;
}

async function findRequestBetween(env, mine, theirs, from, to) {
  const ids = [...new Set([...mine.outgoing, ...mine.incoming, ...theirs.outgoing, ...theirs.incoming])];
  const records = await Promise.all(ids.map(id => loadRequest(env, id)));
  return records.find(item => item?.status === "pending" && ((item.from === from && item.to === to) || (item.from === to && item.to === from)));
}

async function readState(env, userId) {
  const state = await env.TOKEN_STORE.get("social-state:" + userId, "json");
  return {
    friends: Array.isArray(state?.friends) ? state.friends : [],
    incoming: Array.isArray(state?.incoming) ? state.incoming : [],
    outgoing: Array.isArray(state?.outgoing) ? state.outgoing : [],
    challenges: Array.isArray(state?.challenges) ? state.challenges : [],
  };
}

async function pruneExpiredChallenges(env, userId, state) {
  const records = await Promise.all(state.challenges.map(id => loadChallenge(env, id)));
  const activeIds = records.filter(challenge => challenge && Date.parse(challenge.endsAt) > Date.now()).map(challenge => challenge.id);
  if (activeIds.length !== state.challenges.length) {
    state.challenges = activeIds;
    await saveState(env, userId, state);
  }
}

function saveState(env, userId, state) {
  return env.TOKEN_STORE.put("social-state:" + userId, JSON.stringify(state), { expirationTtl: 60 * 60 * 24 * 365 * 5 });
}

async function loadPublicUser(env, id) {
  const user = await env.TOKEN_STORE.get("account-user:" + id, "json");
  return user ? publicProfile(user) : null;
}

async function loadRequest(env, id) { return env.TOKEN_STORE.get("social-request:" + id, "json"); }
async function loadChallenge(env, id) { return env.TOKEN_STORE.get("social-challenge:" + id, "json"); }

function publicProfile(user) {
  return { id: user.id, username: user.username, displayName: user.displayName || user.username, avatarBase64: null };
}

function normalizeUsername(value) {
  return typeof value === "string" ? value.trim().replace(/^@/, "").toLowerCase() : "";
}

async function readBody(request, maximum) {
  try {
    const text = await readLimitedText(request, maximum);
    const value = JSON.parse(text);
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid");
    return { value };
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) return { error: json({ error: "İstek çok büyük." }, 413) };
    return { error: json({ error: "İstek bilgileri okunamadı." }, 400) };
  }
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" },
  });
}
