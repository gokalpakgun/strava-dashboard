// Saf alan kurallarıdır; HTTP endpoint'i veya HealthKit doğrulayıcısı değildir.
// TrustedReceipt ve eşitleme bilgisi yalnız sunucu doğrulama portundan gelir.
// İstemciden gelen source/verified bayrakları bu fonksiyonlara doğrudan verilmez.
export const PASSIVE_SOCIAL_POLICY = Object.freeze({
  version: 1, minMembers: 3, maxMembers: 6, weekMs: 7 * 86400000,
  syncGraceMs: 48 * 3600000, inactivityMs: 4 * 86400000,
  freshSyncMs: 24 * 3600000, minimumSessionSeconds: 900,
  maximumSessionSeconds: 14400, maximumDailyNudges: 1,
});
const P = PASSIVE_SOCIAL_POLICY;
const terminal = state => ["settled", "void"].includes(state.status);
const clone = value => structuredClone(value);
const fail = code => { throw new Error(code); };
const finite = n => typeof n === "number" && Number.isFinite(n);
const integer = (n, low, high) => Number.isSafeInteger(n) && n >= low && n <= high;
const validID = id => typeof id === "string" && /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(id)
  && id !== "prototype" && !Object.hasOwn(Object.prototype, id);
const dayKey = time => new Date(time).toISOString().slice(0, 10);
const requireMember = (state, userId) => { if (!state.members.includes(userId)) fail("not_member"); };

export function nextPledgeWeek(now) {
  if (!finite(now)) fail("invalid_clock");
  const day = new Date(now);
  day.setUTCHours(0, 0, 0, 0);
  day.setUTCDate(day.getUTCDate() + (8 - (day.getUTCDay() || 7)));
  return day.getTime();
}

// Bakiye HTTP body'sinden değil, gruba ait kalıcı ve atomik defterden okunur.
// Krediler yalnız bu kapalı grupta geçer; nakde/ödüle dönüştürülemez.
export function createPledge({ id, members, startsAt, target = 3, stake = 20,
  goal = "sensorSessions", balances, consentVersion = 1 }, now) {
  if (!finite(now) || !validID(id) || !Array.isArray(members)
      || !integer(members.length, P.minMembers, P.maxMembers)
      || new Set(members).size !== members.length || !members.every(validID)
      || !finite(startsAt) || startsAt !== nextPledgeWeek(now)
      || !integer(target, 1, 5) || !integer(stake, 1, 50)
      || !["sensorSessions", "venueVisits"].includes(goal) || consentVersion !== 1) fail("invalid_pledge");
  const wallet = {};
  for (const member of members) {
    if (!integer(balances?.[member], stake, 1000000)) fail("invalid_balance");
    wallet[member] = balances[member];
  }
  return { id, policyVersion: P.version, consentVersion, members: [...members].sort(),
    startsAt, endsAt: startsAt + P.weekMs, finalizeAt: startsAt + P.weekMs + P.syncGraceMs,
    target, stake, goal, status: "inviting", balances: wallet, escrow: {},
    consent: {}, receipts: [], syncThrough: {}, settlement: null };
}

export function acceptPledge(original, userId, consent, now) {
  requireMember(original, userId);
  if (!finite(now) || now >= original.startsAt || terminal(original)
      || consent?.version !== original.consentVersion
      || consent?.activity !== true || consent?.creditLoss !== true) fail("consent_required");
  if (original.escrow[userId] !== undefined) return clone(original);
  const state = clone(original);
  if (state.balances[userId] < state.stake) fail("insufficient_credits");
  state.balances[userId] -= state.stake; state.escrow[userId] = state.stake;
  state.consent[userId] = { version: state.consentVersion, activity: true, acceptedAt: now };
  if (state.members.every(id => state.escrow[id] === state.stake)) state.status = "armed";
  return state;
}

function voidPledge(original, reason, now) {
  const state = clone(original);
  if (terminal(state)) return state;
  for (const id of state.members) state.balances[id] += state.escrow[id] || 0;
  state.escrow = {}; state.status = "void";
  state.settlement = { id: state.id + ":void:v1", at: now, reason, transfers: {} };
  return state;
}

// İzin geri çekme/seans görünürlüğünü kapatma bir kredi cezasına dönüşmez.
export function withdrawPledgeConsent(state, userId, now) {
  requireMember(state, userId);
  if (!finite(now)) fail("invalid_clock");
  const result = voidPledge(state, "consent_withdrawn", now);
  result.receipts = result.receipts.filter(r => r.owner !== userId);
  delete result.syncThrough[userId]; delete result.consent[userId];
  return result;
}

export function applyTrustedReceipt(original, receipt, now) {
  const state = clone(original);
  requireMember(state, receipt?.owner);
  if (!finite(now) || now < state.startsAt || now >= state.finalizeAt
      || terminal(state) || !state.members.every(id => state.escrow[id] === state.stake)
      || !state.consent[receipt.owner]?.activity) fail("pledge_not_receiving");
  const prior = state.receipts.find(r => r.id === receipt.id);
  if (prior) { if (prior.owner !== receipt.owner) fail("receipt_owner_mismatch"); return state; }
  const expected = state.goal === "sensorSessions" ? "sensor-source" : "venue-presence";
  const source = state.goal === "sensorSessions" ? "healthkit" : "corelocation";
  const seconds = (receipt.end - receipt.start) / 1000;
  if (!validID(receipt.id) || !validID(receipt.fingerprint) || receipt.source !== source
      || receipt.assurance !== expected || receipt.policyVersion !== P.version
      || receipt.wasManuallyEntered !== false || !finite(receipt.start) || !finite(receipt.end)
      || !finite(receipt.verifiedAt) || receipt.verifiedAt > now || receipt.verifiedAt < receipt.end
      || !finite(seconds) || seconds < P.minimumSessionSeconds || seconds > P.maximumSessionSeconds
      || receipt.start < state.startsAt || receipt.end > state.endsAt || receipt.end > now) fail("ineligible_receipt");
  const sameOwner = state.receipts.filter(r => r.owner === receipt.owner);
  if (sameOwner.some(r => r.fingerprint === receipt.fingerprint
      || (receipt.start < r.end && receipt.end > r.start))) return state;
  const day = dayKey(receipt.start);
  // Bir günü parçalayarak hedef tamamlama yok: en fazla bir uygun gün sayılır.
  if (sameOwner.some(r => r.day === day)) return state;
  state.receipts.push({ id: receipt.id, fingerprint: receipt.fingerprint,
    owner: receipt.owner, start: receipt.start, end: receipt.end, day });
  return state;
}

// Bu işaret de yalnız sorgu/izin durumunu bilen güvenilir eşitleme adapterinden gelir.
export function applyTrustedSync(original, userId, through, now) {
  requireMember(original, userId);
  if (!finite(now) || !finite(through) || through > now || through < original.startsAt
      || terminal(original) || !original.consent[userId]?.activity) fail("invalid_sync");
  const state = clone(original);
  state.syncThrough[userId] = Math.max(state.syncThrough[userId] || 0, through);
  return state;
}

export function advancePledge(original, now) {
  if (!finite(now)) fail("invalid_clock");
  if (terminal(original) || now < original.startsAt) return clone(original);
  if (!original.members.every(id => original.escrow[id] === original.stake)) return voidPledge(original, "invitations_incomplete", now);
  const state = clone(original);
  if (now < state.endsAt) { state.status = "active"; return state; }
  if (now < state.finalizeAt) { state.status = "awaiting_sync"; return state; }
  if (!state.members.every(id => state.consent[id]?.activity && state.syncThrough[id] >= state.endsAt)) {
    return voidPledge(state, "incomplete_evidence", now);
  }
  const counts = Object.fromEntries(state.members.map(id => [id, state.receipts.filter(r => r.owner === id).length]));
  const winners = state.members.filter(id => counts[id] >= state.target);
  // Kimse tamamlamadıysa havuz operatöre gitmez ve puan yakılmaz.
  if (!winners.length) return voidPledge(state, "no_qualifiers", now);
  const pool = state.members.filter(id => !winners.includes(id)).reduce((sum, id) => sum + state.escrow[id], 0);
  const share = Math.floor(pool / winners.length), remainder = pool % winners.length;
  const transfers = {};
  for (const [index, id] of winners.entries()) {
    transfers[id] = state.escrow[id] + share + (index < remainder ? 1 : 0);
    state.balances[id] += transfers[id];
  }
  state.escrow = {}; state.status = "settled";
  state.settlement = { id: state.id + ":settle:v1", at: now, transfers, counts };
  return state;
}

// Başkasına ham seans saatleri, nabız, salon koordinatı veya izin ayrıntısı sızdırılmaz.
export function pledgeProjection(state, viewer) {
  requireMember(state, viewer);
  return { id: state.id, status: state.status, startsAt: state.startsAt, endsAt: state.endsAt,
    finalizeAt: state.finalizeAt, goal: state.goal, target: state.target, stake: state.stake,
    balance: state.balances[viewer], locked: state.escrow[viewer] || 0,
    members: state.members.map(id => ({ id, accepted: Boolean(state.consent[id]?.activity),
      days: state.receipts.filter(r => r.owner === id).length })),
    settlementId: state.settlement?.id || null };
}

export function passiveMemberStatus({ optedIn, paused, joinedAt, lastSessionAt, lastSyncAt }, now) {
  if (!finite(now) || !finite(joinedAt) || joinedAt > now || optedIn !== true || paused !== false) return "hidden";
  if (finite(lastSessionAt) && lastSessionAt >= joinedAt && lastSessionAt <= now
      && now - lastSessionAt < P.inactivityMs) return "active";
  // Eşitleme yokluğu hareketsizlik değildir; bilinmeyen üyeyi kırmızı gösterme.
  if (!finite(lastSyncAt) || lastSyncAt > now || now - lastSyncAt > P.freshSyncMs) return "hidden";
  const anchor = finite(lastSessionAt) && lastSessionAt >= joinedAt && lastSessionAt <= now ? lastSessionAt : joinedAt;
  return now - anchor >= P.inactivityMs ? "atRisk" : "active";
}

export function nudgeDecision({ groupId, sender, recipient, members, friends, blocked,
  optedIn, status, lastRecipientNudgeAt, timeZone = "UTC", quietStart = 22, quietEnd = 8 }, now) {
  if (!finite(now) || !validID(groupId) || !validID(sender) || !validID(recipient)
      || !Array.isArray(members) || members.length < 3 || members.length > 6
      || new Set(members).size !== members.length || !members.every(validID)
      || sender === recipient || !members.includes(sender) || !members.includes(recipient)
      || friends !== true || blocked !== false || optedIn !== true) return { allowed: false, reason: "not_authorized" };
  if (status !== "atRisk") return { allowed: false, reason: "not_inactive" };
  if (!integer(quietStart, 0, 23) || !integer(quietEnd, 0, 23) || quietStart === quietEnd) return { allowed: false, reason: "invalid_quiet_hours" };
  let hour;
  try { hour = Number(new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", hourCycle: "h23" }).format(new Date(now))); }
  catch { return { allowed: false, reason: "invalid_time_zone" }; }
  const quiet = quietStart < quietEnd ? hour >= quietStart && hour < quietEnd : hour >= quietStart || hour < quietEnd;
  if (quiet) return { allowed: false, reason: "quiet_hours" };
  // Global alıcı kotası: farklı gruplar üzerinden aynı kişiye yeniden dürtme yok.
  if (lastRecipientNudgeAt != null && (!finite(lastRecipientNudgeAt) || now - lastRecipientNudgeAt < 86400000)) return { allowed: false, reason: "recipient_cooldown" };
  return { allowed: true, eventId: "nudge:" + recipient + ":" + dayKey(now),
    recipient, interruptionLevel: "active", sound: "default", destination: "social" };
}

export function makeGhostTrace({ id, owner, sport, metric, startedAt, durationSeconds, points, consentVersion }, now) {
  if (!finite(now) || !validID(id) || !validID(owner) || !validID(sport)
      || !["relativeEffort", "distanceMeters"].includes(metric) || consentVersion !== 1
      || !finite(startedAt) || !integer(durationSeconds, 900, 14400)
      || startedAt + durationSeconds * 1000 > now || now - startedAt > P.weekMs
      || !Array.isArray(points) || points.length !== Math.ceil(durationSeconds / 60)
      || (metric === "distanceMeters" && !["running", "walking", "cycling", "swimming"].includes(sport))) fail("invalid_ghost_trace");
  const limit = metric === "relativeEffort" ? 100 : sport === "cycling" ? 1500 : 1000;
  const curve = points.map((p, index) => {
    const available = Math.min(60, durationSeconds - index * 60);
    if (!p || !finite(p.observedSeconds) || p.observedSeconds < 0 || p.observedSeconds > available
        || (p.value !== null && (!finite(p.value) || p.value < 0 || p.value > limit))
        || (p.observedSeconds === 0 && p.value !== null)) fail("invalid_ghost_point");
    return { value: p.value, observedSeconds: p.observedSeconds };
  });
  return { id, owner, sport, metric, startedAt, durationSeconds, points: curve, consentVersion,
    expiresAt: startedAt + P.weekMs };
}

// Ortak gözlenen dakikalar karşılaştırılır; boşluklar çizgiyle doldurulmaz.
export function compareGhostTraces(ghost, own, elapsedSeconds) {
  ghost = makeGhostTrace(ghost, ghost.startedAt + ghost.durationSeconds * 1000);
  own = makeGhostTrace(own, own.startedAt + own.durationSeconds * 1000);
  if (ghost.owner === own.owner || ghost.metric !== own.metric || ghost.sport !== own.sport
      || !integer(elapsedSeconds, 1, 14400)) fail("incompatible_ghosts");
  const duration = Math.min(elapsedSeconds, ghost.durationSeconds, own.durationSeconds);
  const minutes = Math.floor(duration / 60);
  let sharedSeconds = 0, ghostDose = 0, ownDose = 0;
  for (let i = 0; i < minutes; i++) {
    const a = ghost.points[i], b = own.points[i];
    if (!a || !b || a.value === null || b.value === null || a.observedSeconds < 45 || b.observedSeconds < 45) continue;
    const shared = Math.min(a.observedSeconds, b.observedSeconds);
    sharedSeconds += shared;
    if (ghost.metric === "relativeEffort") { ghostDose += a.value * shared / 60; ownDose += b.value * shared / 60; }
    else { ghostDose += a.value * shared / a.observedSeconds; ownDose += b.value * shared / b.observedSeconds; }
  }
  const coverage = minutes ? sharedSeconds / (minutes * 60) : 0;
  if (minutes < 5 || coverage < 0.7 || ghostDose <= 0) return { status: "insufficient", elapsedSeconds: duration, coverage, leadPercent: null };
  const leadPercent = Math.round((ownDose - ghostDose) / ghostDose * 1000) / 10;
  // Eforun daha yüksek olması daha sağlıklı/başarılı olmak anlamına gelmez.
  return { status: "comparable", elapsedSeconds: duration, coverage, sharedSeconds, ghostDose, ownDose,
    leadPercent, winner: ghost.metric === "relativeEffort" ? null : ownDose === ghostDose ? "tie" : ownDose > ghostDose ? own.owner : ghost.owner };
}

export function createGhostMatch({ id, groupId, members, ghost, challenger, ghostConsent, challengerConsent }, now) {
  if (!finite(now) || !validID(id) || !validID(groupId) || !validID(challenger)
      || !Array.isArray(members) || members.length < 3 || members.length > 6 || new Set(members).size !== members.length
      || !members.includes(ghost?.owner) || !members.includes(challenger) || ghost.owner === challenger
      || ghostConsent !== true || challengerConsent !== true || ghost.consentVersion !== 1 || ghost.expiresAt <= now) fail("ghost_consent_required");
  ghost = makeGhostTrace(ghost, now);
  return { id, groupId, ghost: clone(ghost), challenger, createdAt: now,
    expiresAt: Math.min(ghost.expiresAt, now + 86400000), status: "pending", result: null };
}

export function finishGhostMatch(original, trace, now) {
  if (!finite(now) || trace?.owner !== original.challenger) fail("not_challenger");
  if (original.status === "finished") return clone(original);
  trace = makeGhostTrace(trace, now);
  if (original.status !== "pending" || now > original.expiresAt || trace.startedAt < original.createdAt
      || trace.startedAt + trace.durationSeconds * 1000 > now) fail("ghost_expired");
  const state = clone(original);
  state.result = compareGhostTraces(state.ghost, trace, Math.min(state.ghost.durationSeconds, trace.durationSeconds));
  state.status = "finished";
  state.events = [state.ghost.owner, state.challenger].map(recipient => ({
    id: state.id + ":result:" + recipient, recipient, type: "ghost_result", destination: "social",
  }));
  return state;
}
