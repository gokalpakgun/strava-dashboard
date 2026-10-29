import { queueSocialNotification } from "./push.js";
import { accountContext } from "./account.js";
import { claimCooldown, readLimitedText, RequestBodyTooLargeError } from "./http.js";
import { moderateCommunityText } from "./content-moderation.js";

const MAX_FRIENDS = 100;
const MAX_PENDING = 50;
const MAX_CHALLENGE_MEMBERS = 21;
const CHALLENGE_SECONDS = 60 * 60 * 24 * 7;

export async function handleSocialRequest(request, env, url, ctx) {
  if (!env.TOKEN_STORE) return json({ error: "Hesap depolama bağlantısı hazır değil." }, 503);
  const account = await accountContext(request, env);
  if (account.response) return account.response;
  const userId = account.user.id;
  const root = "/api/account/social";

  if (!hasModerationToken(env) && request.method !== "DELETE" && url.pathname.startsWith(root + "/challenges")) {
    return json({ error: "Sosyal güvenlik ayarı tamamlanana kadar bu özellik kullanılamıyor." }, 503);
  }

  if (url.pathname === root && request.method === "GET") return loadSnapshot(env, account.user);
  if (url.pathname === root + "/friends" && request.method === "POST") return sendFriendRequest(request, env, account.user, ctx);
  if (url.pathname === root + "/friends/remove" && request.method === "POST") return removeFriend(request, env, account.user);
  if (url.pathname === root + "/requests" && request.method === "POST") return respondToFriendRequest(request, env, account.user, ctx);
  if (url.pathname === root + "/blocks" && request.method === "POST") return updateBlock(request, env, account.user);
  if (url.pathname === root + "/reports" && request.method === "POST") return createReport(request, env, account.user);
  if (url.pathname === root + "/challenges" && request.method === "POST") return createChallenge(request, env, account.user, ctx);
  const match = url.pathname.match(/^\/api\/account\/social\/challenges\/([a-f0-9-]{20,64})$/i);
  if (match && request.method === "POST") return updateChallenge(request, env, account.user, match[1]);
  if (match && request.method === "DELETE") return cancelChallenge(env, account.user, match[1]);
  if (url.pathname === root && request.method !== "GET") return json({ error: "Bu sosyal işlem desteklenmiyor." }, 405);
  return null;
}

export async function handleModerationRequest(request, env, url) {
  if (url.pathname !== "/api/moderation/reports" && !/^\/api\/moderation\/reports\/[a-f0-9-]{20,64}$/i.test(url.pathname)) return null;
  const secret = hasModerationToken(env) ? env.MODERATION_TOKEN : "";
  if (!secret) return json({ error: "Bildirim sistemi henüz etkinleştirilmedi." }, 503);
  const supplied = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!secret || !constantTimeEqual(supplied, secret)) return json({ error: "Yetkisiz." }, 401);
  if (!env.TOKEN_STORE) return json({ error: "Hesap depolama bağlantısı hazır değil." }, 503);
  if (url.pathname === "/api/moderation/reports" && request.method === "GET") {
    const cursor = url.searchParams.get("cursor") || undefined;
    const listed = await env.TOKEN_STORE.list({ prefix: "moderation-report:", limit: 100, ...(cursor ? { cursor } : {}) });
    const reports = await Promise.all(listed.keys.map(item => env.TOKEN_STORE.get(item.name, "json")));
    return json({
      reports: reports.filter(Boolean).sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
      complete: listed.list_complete,
      cursor: listed.list_complete ? null : listed.cursor || null,
    });
  }
  const match = url.pathname.match(/^\/api\/moderation\/reports\/([a-f0-9-]{20,64})$/i);
  if (request.method === "POST" && match) {
    const body = await readBody(request, 512);
    if (body.error) return body.error;
    if (body.value.action !== "resolve") return json({ error: "Desteklenmeyen işlem." }, 400);
    const key = "moderation-report:" + match[1];
    const report = await env.TOKEN_STORE.get(key, "json");
    if (!report) return json({ error: "Bildirim bulunamadı." }, 404);
    report.status = "resolved";
    report.resolvedAt = new Date().toISOString();
    await env.TOKEN_STORE.put(key, JSON.stringify(report), { expirationTtl: 60 * 60 * 24 * 180 });
    return json({ ok: true });
  }
  return json({ error: "Method not allowed." }, 405);
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
    Promise.all(state.friends.filter(id => !state.blocked.includes(id)).slice(0, MAX_FRIENDS).map(id => loadPublicUser(env, id))),
    Promise.all(state.incoming.slice(0, MAX_PENDING).map(id => loadRequest(env, id))),
    Promise.all(state.outgoing.slice(0, MAX_PENDING).map(id => loadRequest(env, id))),
    Promise.all(state.challenges.slice(0, 40).map(id => loadChallenge(env, id))),
  ]);
  const activeIds = challengeRecords.filter(challenge => challenge && Date.parse(challenge.endsAt) > Date.now()
    && challenge.participants.some(item => item.userId === user.id && item.status !== "declined")).map(challenge => challenge.id);
  const pendingChanged = retainPendingRequests(state, user.id, [...incoming, ...outgoing]);
  if (activeIds.length !== state.challenges.length || pendingChanged) {
    state.challenges = activeIds;
    await saveState(env, user.id, state);
  }
  const activeChallenges = (await Promise.all(challengeRecords.map(async challenge => {
    if (!challenge || Date.parse(challenge.endsAt) <= Date.now()
      || !challenge.participants.some(item => item.userId === user.id && item.status !== "declined")) return null;
    return presentChallenge(env, challenge, user.id);
  }))).filter(Boolean);
  return json({
    profile: publicProfile(user),
    friends: friends.filter(Boolean),
    blocked: (await Promise.all(state.blocked.slice(0, MAX_FRIENDS).map(id => loadPublicUser(env, id)))).filter(Boolean),
    incoming: (await Promise.all(incoming.filter(item => item?.status === "pending" && item.to === user.id).map(async item => ({
      id: item.id, createdAt: item.createdAt, user: await loadPublicUser(env, item.from),
    })))).filter(item => item.user),
    outgoing: (await Promise.all(outgoing.filter(item => item?.status === "pending" && item.from === user.id).map(async item => ({
      id: item.id, createdAt: item.createdAt, user: await loadPublicUser(env, item.to),
    })))).filter(item => item.user),
    challenges: activeChallenges,
  });
}

async function sendFriendRequest(request, env, user, ctx) {
  const body = await readBody(request, 512);
  if (body.error) return body.error;
  const username = normalizeUsername(body.value.username);
  if (!/^[a-z0-9_]{3,24}$/.test(username)) return json({ error: "Geçerli bir kullanıcı adı yaz." }, 400);
  if (username === user.username) return json({ error: "Kendine arkadaşlık isteği gönderemezsin." }, 400);
  const throttleKey = "social-request-cooldown:" + user.id;
  const throttle = await claimCooldown(env.TOKEN_STORE, throttleKey, 2);
  if (!throttle.allowed) {
    return json({ error: throttle.unavailable ? "İstek şu anda işlenemiyor. Biraz sonra tekrar dene." : "Yeni istek göndermeden önce biraz bekle." }, throttle.unavailable ? 503 : 429);
  }
  const friendId = await env.TOKEN_STORE.get("account-username:" + username);
  const friend = friendId ? await env.TOKEN_STORE.get("account-user:" + friendId, "json") : null;
  if (!friend) return json({ error: "Bu kullanıcı adına sahip Tempo hesabı bulunamadı." }, 404);
  const [mine, theirs] = await Promise.all([readState(env, user.id), readState(env, friend.id)]);
  await Promise.all([prunePendingRequests(env, user.id, mine), prunePendingRequests(env, friend.id, theirs)]);
  if (mine.blocked.includes(friend.id) || theirs.blocked.includes(user.id)) return json({ error: "Bu kullanıcıyla bağlantı kurulamıyor." }, 403);
  if (mine.friends.includes(friend.id)) return json({ error: "Bu kişi zaten arkadaş listende." }, 409);
  const existingRequests = await findRequestsBetween(env, mine, theirs, user.id, friend.id);
  const incomingRequest = existingRequests.find(item => item.from === friend.id && item.to === user.id);
  if (incomingRequest) {

    // If both people send an invite before either sees the notification,
    // treat the second invite as acceptance instead of trapping them in a 409.
    if (mine.friends.length >= MAX_FRIENDS || theirs.friends.length >= MAX_FRIENDS) {
      return json({ error: "Arkadaş listesi sınırına ulaşıldı." }, 409);
    }
    const requestIds = new Set(existingRequests.map(item => item.id));
    mine.incoming = mine.incoming.filter(id => !requestIds.has(id));
    mine.outgoing = mine.outgoing.filter(id => !requestIds.has(id));
    theirs.incoming = theirs.incoming.filter(id => !requestIds.has(id));
    theirs.outgoing = theirs.outgoing.filter(id => !requestIds.has(id));
    mine.friends.unshift(friend.id);
    theirs.friends.unshift(user.id);
    await Promise.all([
      ...existingRequests.map(item => env.TOKEN_STORE.delete("social-request:" + item.id)),
      saveState(env, user.id, mine),
      saveState(env, friend.id, theirs),
    ]);
    await queueSocialNotification(env, ctx, friend.id, "friend_accepted", incomingRequest.id);
    return json({ ok: true, accepted: true, user: publicProfile(friend) });
  }
  if (existingRequests.length) return json({ error: "Bu kişiye zaten bekleyen bir istek var." }, 409);
  if (mine.outgoing.length >= MAX_PENDING || theirs.incoming.length >= MAX_PENDING) {
    return json({ error: "Bekleyen arkadaşlık isteği sınırına ulaşıldı." }, 429);
  }
  const id = crypto.randomUUID();
  const record = { id, from: user.id, to: friend.id, status: "pending", createdAt: new Date().toISOString() };
  mine.outgoing.unshift(id);
  theirs.incoming.unshift(id);
  await Promise.all([
    env.TOKEN_STORE.put("social-request:" + id, JSON.stringify(record), { expirationTtl: 60 * 60 * 24 * 90 }),
    saveState(env, user.id, mine), saveState(env, friend.id, theirs),
  ]);
  await queueSocialNotification(env, ctx, friend.id, "friend_request", id);
  return json({ ok: true, requestId: id, user: publicProfile(friend) }, 201);
}

async function respondToFriendRequest(request, env, user, ctx) {
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
  if (mine.blocked.includes(record.from) || theirs.blocked.includes(user.id)) return json({ error: "Bu kullanıcıyla bağlantı kurulamıyor." }, 403);
  mine.incoming = mine.incoming.filter(value => value !== id);
  theirs.outgoing = theirs.outgoing.filter(value => value !== id);
  if (action === "accept") {
    if (mine.friends.length >= MAX_FRIENDS || theirs.friends.length >= MAX_FRIENDS) return json({ error: "Arkadaş listesi sınırına ulaşıldı." }, 409);
    if (!mine.friends.includes(record.from)) mine.friends.unshift(record.from);
    if (!theirs.friends.includes(user.id)) theirs.friends.unshift(user.id);
  }
  // Once both indexes have been updated, the request record is no longer needed.
  await Promise.all([env.TOKEN_STORE.delete(key), saveState(env, user.id, mine), saveState(env, record.from, theirs)]);
  if (action === "accept") {
    await queueSocialNotification(env, ctx, record.from, "friend_accepted", id);
  }
  return json({ ok: true });
}

async function updateBlock(request, env, user) {
  const body = await readBody(request, 1024);
  if (body.error) return body.error;
  const userId = typeof body.value.userId === "string" ? body.value.userId : "";
  const action = body.value.action;
  if (!/^[a-f0-9]{40}$/i.test(userId) || userId === user.id || !["block", "unblock"].includes(action)) {
    return json({ error: "Engelleme işlemi geçersiz." }, 400);
  }
  const target = await env.TOKEN_STORE.get("account-user:" + userId, "json");
  if (!target) return json({ error: "Tempo hesabı bulunamadı." }, 404);
  const [mine, theirs] = await Promise.all([readState(env, user.id), readState(env, userId)]);
  if (action === "unblock") {
    mine.blocked = mine.blocked.filter(id => id !== userId);
    await saveState(env, user.id, mine);
    return json({ ok: true });
  }

  if (!mine.blocked.includes(userId) && mine.blocked.length >= MAX_FRIENDS) return json({ error: "Engellenen hesap sınırına ulaşıldı." }, 429);
  if (!mine.blocked.includes(userId)) mine.blocked.unshift(userId);
  mine.friends = mine.friends.filter(id => id !== userId);
  theirs.friends = theirs.friends.filter(id => id !== user.id);

  const requestIds = new Set([...mine.incoming, ...mine.outgoing, ...theirs.incoming, ...theirs.outgoing]);
  for (const id of requestIds) {
    const record = await loadRequest(env, id);
    if (record && ((record.from === user.id && record.to === userId) || (record.from === userId && record.to === user.id))) {
      mine.incoming = mine.incoming.filter(value => value !== id);
      mine.outgoing = mine.outgoing.filter(value => value !== id);
      theirs.incoming = theirs.incoming.filter(value => value !== id);
      theirs.outgoing = theirs.outgoing.filter(value => value !== id);
      await env.TOKEN_STORE.delete("social-request:" + id);
    }
  }

  const sharedChallenges = [...new Set([...mine.challenges, ...theirs.challenges])];
  await Promise.all(sharedChallenges.map(async id => {
    const challenge = await loadChallenge(env, id);
    if (!challenge || !challenge.participants.some(item => item.userId === user.id) || !challenge.participants.some(item => item.userId === userId)) return;
    // A member may leave a shared challenge by blocking someone, but cannot
    // evict its creator or another member from a third person's challenge.
    const removedId = challenge.creatorId === user.id ? userId : user.id;
    challenge.participants = challenge.participants.filter(item => item.userId !== removedId);
    if (removedId === user.id) mine.challenges = mine.challenges.filter(value => value !== id);
    else theirs.challenges = theirs.challenges.filter(value => value !== id);
    await env.TOKEN_STORE.put("social-challenge:" + id, JSON.stringify(challenge), { expirationTtl: Math.max(60, Math.ceil((Date.parse(challenge.endsAt) - Date.now()) / 1000) + 60 * 60 * 24 * 14) });
  }));
  await Promise.all([saveState(env, user.id, mine), saveState(env, userId, theirs)]);
  return json({ ok: true });
}

async function createReport(request, env, user) {
  if (!hasModerationToken(env)) return json({ error: "Bildirim sistemi henüz etkinleştirilmedi." }, 503);
  const body = await readBody(request, 1024);
  if (body.error) return body.error;
  const category = body.value.category;
  if (!["harassment", "spam", "impersonation", "inappropriate"].includes(category)) return json({ error: "Bildirim nedeni geçersiz." }, 400);
  const state = await readState(env, user.id);
  const targetId = typeof body.value.userId === "string" ? body.value.userId : "";
  const challengeId = typeof body.value.challengeId === "string" ? body.value.challengeId : "";
  let target;
  if (challengeId) {
    const challenge = await loadChallenge(env, challengeId);
    if (!challenge || !challenge.participants.some(item => item.userId === user.id)) return json({ error: "Yarışma bulunamadı." }, 404);
    target = await loadPublicUser(env, challenge.creatorId);
    if (!target) return json({ error: "Kullanıcı bulunamadı." }, 404);
  } else {
    if (!/^[a-f0-9]{40}$/i.test(targetId) || targetId === user.id || !state.friends.includes(targetId)) return json({ error: "Yalnızca arkadaş listesindeki bir hesabı bildirebilirsin." }, 400);
    target = await loadPublicUser(env, targetId);
    if (!target) return json({ error: "Kullanıcı bulunamadı." }, 404);
  }
  const cooldownKey = "social-report-cooldown:" + user.id;
  const id = crypto.randomUUID();
  const report = {
    id,
    reporterId: user.id,
    targetUserId: target.id,
    targetUsername: target.username,
    challengeId: challengeId || null,
    category,
    status: "open",
    createdAt: new Date().toISOString(),
  };
  try {
    const cooldown = await claimCooldown(env.TOKEN_STORE, cooldownKey, 30);
    if (!cooldown.allowed) {
      return json({ error: cooldown.unavailable ? "Bildirim şu anda kaydedilemedi. Biraz sonra tekrar dene." : "Yeni bildirim göndermeden önce biraz bekle." }, cooldown.unavailable ? 503 : 429);
    }
    await env.TOKEN_STORE.put("moderation-report:" + id, JSON.stringify(report), { expirationTtl: 60 * 60 * 24 * 180 });
  } catch {
    return json({ error: "Bildirim şu anda kaydedilemedi. Biraz sonra tekrar dene." }, 503);
  }
  return json({ ok: true, message: "Bildirim alındı." }, 201);
}

async function removeFriend(request, env, user) {
  const body = await readBody(request, 512);
  if (body.error) return body.error;
  const friendId = body.value.userId;
  if (typeof friendId !== "string" || !/^[a-f0-9]{40}$/i.test(friendId) || friendId === user.id) return json({ error: "Invalid friend." }, 400);
  const mine = await readState(env, user.id);
  const theirs = await readState(env, friendId);
  if (!mine.friends.includes(friendId) && !theirs.friends.includes(user.id)) return json({ ok: true });
  mine.friends = mine.friends.filter(id => id !== friendId);
  theirs.friends = theirs.friends.filter(id => id !== user.id);
  // Removing a friend does not block them or silently cancel existing challenges.
  await Promise.all([saveState(env, user.id, mine), saveState(env, friendId, theirs)]);
  return json({ ok: true });
}

async function cancelChallenge(env, user, id) {
  const challenge = await loadChallenge(env, id);
  if (!challenge) return json({ error: "Challenge not found." }, 404);
  if (challenge.creatorId !== user.id) return json({ error: "Only the creator can cancel this challenge." }, 403);
  // Keep a separate tombstone so a concurrent acceptance/share write cannot resurrect it.
  await env.TOKEN_STORE.put("social-challenge-cancelled:" + id, "1", {
    expirationTtl: Math.max(60, Math.ceil((Date.parse(challenge.endsAt) - Date.now()) / 1000) + 60 * 60 * 24 * 14),
  });
  return json({ ok: true });
}

async function createChallenge(request, env, user, ctx) {
  const body = await readBody(request, 4096);
  if (body.error) return body.error;
  const title = typeof body.value.title === "string" ? body.value.title.trim().slice(0, 60) : "";
  const metric = body.value.metric;
  const mode = body.value.mode ?? "competitive";
  const targetTotal = body.value.targetTotal ?? null;
  if (!["competitive", "coop"].includes(mode) || (mode === "coop" && (!Number.isSafeInteger(targetTotal) || targetTotal < 1 || targetTotal > 1_000_000_000))) return json({ error: "Ortak hedef geçersiz. Pozitif bir tam sayı seç." }, 400);
  const friendIds = Array.isArray(body.value.friendIds) ? [...new Set(body.value.friendIds.filter(value => typeof value === "string"))] : [];
  if (!title) return json({ error: "Yarışmaya kısa bir ad ver." }, 400);
  const cooldownKey = "social-challenge-create-cooldown:" + user.id;
  const cooldown = await claimCooldown(env.TOKEN_STORE, cooldownKey, 10);
  if (!cooldown.allowed) {
    return json({ error: cooldown.unavailable ? "Yarışma şu anda oluşturulamıyor. Biraz sonra tekrar dene." : "Çok hızlı deneme yapıldı. Birkaç saniye sonra tekrar dene." }, cooldown.unavailable ? 503 : 429);
  }
  const moderation = await moderateCommunityText(env, title);
  if (moderation.unavailable) return json({ error: "Yarışma adı denetimi şu anda kullanılamıyor. Biraz sonra tekrar dene." }, 503);
  if (!moderation.allowed) return json({ error: "Bu yarışma adı topluluk kurallarına uygun değil." }, 400);
  if (!["steps", "exerciseMinutes", "movementDays", "sleepDays", "hydrationDays"].includes(metric)) return json({ error: "Yarışma hedefi geçersiz." }, 400);
  if (friendIds.length < 1 || friendIds.length > MAX_CHALLENGE_MEMBERS - 1) return json({ error: "En az bir arkadaş seç; yarışmaya en fazla 20 arkadaş eklenebilir." }, 400);
  const state = await readState(env, user.id);
  await pruneExpiredChallenges(env, user.id, state);
  if (friendIds.some(id => !state.friends.includes(id))) return json({ error: "Yarışmaya yalnızca arkadaş listendeki kişileri ekleyebilirsin." }, 403);
  if (state.challenges.length >= 40) return json({ error: "Aktif yarışma sınırına ulaştın." }, 429);
  const now = new Date();
  const startsAt = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
  const endsAt = new Date(startsAt.getTime() + CHALLENGE_SECONDS * 1000);
  const id = crypto.randomUUID();
  const participants = [{ userId: user.id, status: "accepted", shareHealth: body.value.shareHealth === true, joinedAt: now.toISOString() }]
    .concat(friendIds.map(userId => ({ userId, status: "invited", shareHealth: false, invitedAt: now.toISOString() })));
  const challenge = { id, creatorId: user.id, title, metric, mode, targetTotal: mode === "coop" ? targetTotal : null, startsAt: startsAt.toISOString(), endsAt: endsAt.toISOString(), participants };
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
  await Promise.all(friendIds.map(friendId => queueSocialNotification(env, ctx, friendId, "challenge_invite", id)));
  return json({ ok: true, challenge: await presentChallenge(env, challenge, user.id) }, 201);
}

async function updateChallenge(request, env, user, id) {
  const key = "social-challenge:" + id;
  const challenge = await loadChallenge(env, id);
  if (!challenge) return json({ error: "Yarışma bulunamadı veya süresi doldu." }, 404);
  if (Date.parse(challenge.endsAt) <= Date.now()) return json({ error: "Bu yarışmanın süresi doldu." }, 409);
  const participant = challenge.participants.find(item => item.userId === user.id);
  if (!participant) return json({ error: "Bu yarışmaya davetin yok." }, 403);
  const body = await readBody(request, 1024);
  if (body.error) return body.error;
  if (body.value.action === "accept" || body.value.action === "decline") {
    if (participant.status !== "invited") return json({ error: "Bu davet daha önce yanıtlanmış." }, 409);
    participant.status = body.value.action === "accept" ? "accepted" : "declined";
    participant.respondedAt = new Date().toISOString();
    participant.shareHealth = body.value.action === "accept" && body.value.share === true;
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
  const viewerAccepted = challenge.participants.some(item => item.userId === viewerId && item.status === "accepted");
  const participants = await Promise.all(challenge.participants.map(async participant => {
    const profile = await loadPublicUser(env, participant.userId);
    const result = {
      userId: participant.userId,
      status: participant.status,
      shareHealth: participant.shareHealth === true,
      user: profile,
      score: null,
    };
    if (viewerAccepted && profile && participant.status === "accepted" && participant.shareHealth === true) {
      result.score = await challengeScore(env, participant.userId, challenge);
    }
    return result;
  }));
  return {
    id: challenge.id,
    creatorId: challenge.creatorId,
    myUserId: viewerId,
    title: challenge.title,
    metric: challenge.metric,
    mode: challenge.mode === "coop" ? "coop" : "competitive",
    targetTotal: challenge.mode === "coop" ? challenge.targetTotal : null,
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
  const today = new Date().toISOString().slice(0, 10);
  let total = 0;
  let hasMeasurement = false;
  for (const [day, values] of Object.entries(health?.days || {})) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < startDay || day >= endDayExclusive || day > today || Date.now() < Date.parse(challenge.startsAt)) continue;
    if (challenge.metric === "sleepDays" || challenge.metric === "hydrationDays") {
      const value = challenge.metric === "sleepDays" ? values?.sleepMinutes : values?.waterMl;
      const threshold = challenge.metric === "sleepDays" ? 420 : 2000;
      if (typeof value === "number" && Number.isFinite(value) && value >= 0) {
        hasMeasurement = true;
        if (value >= threshold) total += 1;
      }
      continue;
    }
    if (challenge.metric === "movementDays") {
      const steps = values?.steps;
      const minutes = values?.exerciseMinutes;
      const hasSteps = typeof steps === "number" && Number.isFinite(steps) && steps >= 0;
      const hasMinutes = typeof minutes === "number" && Number.isFinite(minutes) && minutes >= 0;
      if (hasSteps || hasMinutes) {
        hasMeasurement = true;
        if ((hasSteps && steps >= 3_000) || (hasMinutes && minutes >= 10)) total += 1;
      }
      continue;
    }
    const value = values?.[challenge.metric];
    if (typeof value === "number" && Number.isFinite(value) && value >= 0) { total += value; hasMeasurement = true; }
  }
  return hasMeasurement ? Math.round(total) : null;
}

async function findRequestsBetween(env, mine, theirs, from, to) {
  const ids = [...new Set([...mine.outgoing, ...mine.incoming, ...theirs.outgoing, ...theirs.incoming])];
  const records = await Promise.all(ids.map(id => loadRequest(env, id)));
  return records.filter(item => item?.status === "pending" && ((item.from === from && item.to === to) || (item.from === to && item.to === from)));
}

function retainPendingRequests(state, userId, records) {
  const pending = new Map(records.filter(record => record?.status === "pending").map(record => [record.id, record]));
  const incoming = state.incoming.filter(id => pending.get(id)?.to === userId);
  const outgoing = state.outgoing.filter(id => pending.get(id)?.from === userId);
  const changed = incoming.length !== state.incoming.length || outgoing.length !== state.outgoing.length;
  state.incoming = incoming;
  state.outgoing = outgoing;
  return changed;
}

async function prunePendingRequests(env, userId, state) {
  const ids = [...new Set([...state.incoming, ...state.outgoing])];
  if (!ids.length) return;
  const records = await Promise.all(ids.map(id => loadRequest(env, id)));
  // The caller saves after its mutation; two writes to the same key here
  // would hit Cloudflare KV's one-write-per-second limit.
  retainPendingRequests(state, userId, records);
}

async function readState(env, userId) {
  const state = await env.TOKEN_STORE.get("social-state:" + userId, "json");
  return {
    friends: Array.isArray(state?.friends) ? state.friends : [],
    incoming: Array.isArray(state?.incoming) ? state.incoming : [],
    outgoing: Array.isArray(state?.outgoing) ? state.outgoing : [],
    challenges: Array.isArray(state?.challenges) ? state.challenges : [],
    blocked: Array.isArray(state?.blocked) ? state.blocked : [],
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
async function loadChallenge(env, id) {
  const [cancelled, challenge] = await Promise.all([
    env.TOKEN_STORE.get("social-challenge-cancelled:" + id),
    env.TOKEN_STORE.get("social-challenge:" + id, "json"),
  ]);
  return cancelled ? null : challenge;
}

function publicProfile(user) {
  return { id: user.id, username: user.username, displayName: user.displayName || user.username, avatarBase64: user.avatarBase64 || null };
}

function normalizeUsername(value) {
  return typeof value === "string" ? value.trim().replace(/^@/, "").toLowerCase() : "";
}

function constantTimeEqual(left, right) {
  if (typeof left !== "string" || typeof right !== "string" || left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}

function hasModerationToken(env) {
  return typeof env.MODERATION_TOKEN === "string" && env.MODERATION_TOKEN.length >= 32;
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

