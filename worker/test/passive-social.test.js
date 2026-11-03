import test from "node:test";
import assert from "node:assert/strict";
import { PASSIVE_SOCIAL_POLICY as P, nextPledgeWeek, createPledge, acceptPledge,
  applyTrustedReceipt, applyTrustedSync, advancePledge, withdrawPledgeConsent,
  pledgeProjection, passiveMemberStatus, nudgeDecision, makeGhostTrace,
  compareGhostTraces, createGhostMatch, finishGhostMatch } from "../src/passive-social-core.js";

const DAY = 86400000, NOW = Date.UTC(2026, 10, 3, 12), START = nextPledgeWeek(NOW);
const members = ["alice", "bob", "carol"];
const terms = { version: 1, activity: true, creditLoss: true };
function pledge(overrides = {}) {
  return createPledge({ id: "week1", members, startsAt: START,
    balances: { alice: 100, bob: 100, carol: 100 }, ...overrides }, NOW);
}
function armed(overrides = {}) { return members.reduce((s, id) => acceptPledge(s, id, terms, NOW), pledge(overrides)); }
function receipt(owner, day, overrides = {}) {
  const start = START + day * DAY + 3600000, end = start + 1800000;
  return { id: owner + "_" + day, fingerprint: "source_" + owner + "_" + day,
    owner, source: "healthkit", assurance: "sensor-source", policyVersion: 1,
    wasManuallyEntered: false, start, end, verifiedAt: end, ...overrides };
}
function addDays(state, id, count) {
  for (let i = 0; i < count; i++) state = applyTrustedReceipt(state, receipt(id, i), state.endsAt + DAY);
  return state;
}
function completeSync(state) { return members.reduce((s, id) => applyTrustedSync(s, id, s.endsAt, s.endsAt + DAY), state); }
const total = s => Object.values(s.balances).reduce((a,b) => a+b,0) + Object.values(s.escrow).reduce((a,b)=>a+b,0);

test("UTC week boundaries are future Mondays including Sunday and Monday starts", () => {
  assert.equal(new Date(START).toISOString(), "2026-11-09T00:00:00.000Z");
  assert.equal(nextPledgeWeek(Date.UTC(2026,10,8,23)), START);
  assert.equal(nextPledgeWeek(START), START + 7*DAY);
});
test("closed pledge rejects wrong group sizes, duplicate IDs, prototype keys and arbitrary start", () => {
  for (const ids of [["alice", "bob"], ["alice", "alice", "bob"], ["__proto__", "bob", "carol"], ["toString", "bob", "carol"], [...members,"d","e","f","g"]]) assert.throws(() => pledge({ members: ids }));
  assert.throws(() => pledge({ startsAt: START + 1000 }));
  assert.throws(() => pledge({ target: 7 }));
  assert.throws(() => pledge({ stake: 100 }));
  assert.throws(() => pledge({ balances: { alice: -1, bob: 100, carol: 100 } }));
});
test("each person separately consents to activity sharing and the fixed credit loss", () => {
  for (const consent of [null, { ...terms, creditLoss: false }, { ...terms, activity: false }, { ...terms, version: 2 }]) assert.throws(() => acceptPledge(pledge(), "alice", consent, NOW));
  assert.throws(() => acceptPledge(pledge(), "outsider", terms, NOW));
  assert.throws(() => acceptPledge(pledge(), "alice", terms, START));
});
test("duplicate acceptance reserves stake once, conserves credits and never mutates original", () => {
  const initial = pledge(), once = acceptPledge(initial, "alice", terms, NOW);
  assert.equal(initial.balances.alice, 100); assert.equal(once.balances.alice, 80);
  assert.deepEqual(acceptPledge(once, "alice", terms, NOW), once);
  assert.equal(total(once), 300); assert.equal(armed().status, "armed");
});
test("unfinished invitations refund reserves at start without penalizing invitees", () => {
  const partly = acceptPledge(pledge(), "alice", terms, NOW);
  const result = advancePledge(partly, START);
  assert.equal(result.status, "void"); assert.equal(result.balances.alice, 100);
  assert.equal(total(result), 300);
});
test("manual, Strava, venue, missing trust, future, short and old evidence never enter sensor pledge", () => {
  const s = armed(), good = receipt("alice", 0), now = good.end + 1000;
  for (const fields of [{ source: "strava" }, { source: "corelocation", assurance: "venue-presence" },
    { wasManuallyEntered: true }, { wasManuallyEntered: undefined }, { assurance: "client-verified" },
    { end: good.start + 1000 }, { start: START - 1000 }, { end: now + 1000 },
    { start: NaN }, { verifiedAt: now + 1000 }, { policyVersion: 99 }]) {
    assert.throws(() => applyTrustedReceipt(s, { ...good, ...fields }, now));
  }
  assert.throws(() => applyTrustedReceipt(s, receipt("outsider",0), now));
});
test("valid receipt replay is idempotent and an owner cannot claim another owner's receipt ID", () => {
  const r = receipt("alice",0), s = applyTrustedReceipt(armed(),r,r.end);
  assert.deepEqual(applyTrustedReceipt(s,r,r.end+1000), s);
  assert.throws(() => applyTrustedReceipt(s,{...r,owner:"bob"},r.end+1000), /receipt_owner_mismatch/);
});
test("overlap, mirror fingerprints and splitting a day cannot inflate session-days", () => {
  const r = receipt("alice",0), s = applyTrustedReceipt(armed(),r,r.end);
  for (const fields of [{ id:"mirror" }, { id:"same",start:r.start+2000,end:r.end+2000 },
    { id:"sameDay",fingerprint:"second",start:r.start+3*3600000,end:r.end+3*3600000 }]) {
    assert.deepEqual(applyTrustedReceipt(s,{...r,...fields,verifiedAt:s.endsAt},s.endsAt),s);
  }
});
test("presence-only contracts stay separate from sensor-workout contracts", () => {
  const s = armed({ goal: "venueVisits" }), r = receipt("alice",0,{source:"corelocation",assurance:"venue-presence"});
  const updated = applyTrustedReceipt(s,r,r.end);
  assert.equal(updated.receipts.length,1);
  assert.throws(()=>applyTrustedReceipt(s,receipt("alice",0),r.end));
});
test("late sync grace accepts in-week evidence and rejects sessions crossing the boundary", () => {
  let s = armed(); const r = receipt("alice",6);
  s = applyTrustedReceipt(s,r,s.endsAt+DAY); assert.equal(s.receipts.length,1);
  assert.throws(()=>applyTrustedReceipt(armed(),{...r,start:START-1000},s.endsAt));
  assert.throws(()=>applyTrustedReceipt(armed(),{...r,end:s.endsAt+1000},s.endsAt+DAY));
  assert.throws(()=>applyTrustedReceipt(armed(),r,s.finalizeAt));
});
test("no settlement occurs before grace and no missing sync is interpreted as failure", () => {
  let s = addDays(armed(),"alice",3);
  assert.equal(advancePledge(s,START).status,"active");
  assert.equal(advancePledge(s,s.endsAt).status,"awaiting_sync");
  const result=advancePledge(s,s.finalizeAt);
  assert.equal(result.status,"void"); assert.equal(result.settlement.reason,"incomplete_evidence");
  assert.deepEqual(result.balances,{alice:100,bob:100,carol:100});
});
test("settlement pays qualifiers once and conserves the full escrow pool", () => {
  let s=completeSync(addDays(armed(),"alice",3));
  s=advancePledge(s,s.finalizeAt);
  assert.equal(s.status,"settled");assert.deepEqual(s.balances,{alice:140,bob:80,carol:80});
  assert.equal(total(s),300);assert.deepEqual(advancePledge(s,s.finalizeAt+DAY),s);
  assert.equal(s.settlement.id,"week1:settle:v1");
});
test("deterministic integer remainder never mints or loses a credit", () => {
  const ids=[...members,"d","e"];
  let s=createPledge({id:"odd",members:ids,startsAt:START,target:1,stake:1,balances:Object.fromEntries(ids.map(id=>[id,100]))},NOW);
  for(const id of ids)s=acceptPledge(s,id,terms,NOW);
  for(const id of ["alice","bob"])s=applyTrustedReceipt(s,receipt(id,0),s.endsAt);
  for(const id of ids)s=applyTrustedSync(s,id,s.endsAt,s.endsAt+DAY);
  s=advancePledge(s,s.finalizeAt);
  assert.equal(s.balances.alice,102);assert.equal(s.balances.bob,101);assert.equal(total(s),500);
});
test("all complete returns stakes; no qualifiers refunds everyone instead of burning points", () => {
  let all=armed();for(const id of members)all=addDays(all,id,3);
  all=completeSync(all);assert.deepEqual(advancePledge(all,all.finalizeAt).balances,{alice:100,bob:100,carol:100});
  const none=completeSync(armed()),result=advancePledge(none,none.finalizeAt);
  assert.equal(result.settlement.reason,"no_qualifiers");assert.equal(total(result),300);
});
test("every outcome across groups of 3 to 6 preserves credits and settles idempotently", () => {
  for (let count=3;count<=6;count++) {
    const ids=Array.from({length:count},(_,i)=>"member"+i);
    for (let mask=0;mask<2**count;mask++) {
      let s=createPledge({id:"matrix",members:ids,startsAt:START,target:1,stake:17,balances:Object.fromEntries(ids.map(id=>[id,100]))},NOW);
      for (const id of ids) s=acceptPledge(s,id,terms,NOW);
      for (let i=0;i<count;i++) if (mask & (1<<i)) s=applyTrustedReceipt(s,receipt(ids[i],0),s.endsAt);
      for (const id of ids) s=applyTrustedSync(s,id,s.endsAt,s.endsAt+DAY);
      const result=advancePledge(s,s.finalizeAt);
      assert.equal(total(result),count*100);
      assert.ok(Object.values(result.balances).every(n=>Number.isSafeInteger(n)&&n>=0));
      assert.deepEqual(advancePledge(result,result.finalizeAt+DAY),result);
    }
  }
});
test("consent withdrawal voids unsettled pledge, refunds all reserves and erases that person's receipts", () => {
  const s=addDays(armed(),"alice",3),result=withdrawPledgeConsent(s,"alice",s.endsAt-1);
  assert.equal(result.status,"void");assert.equal(result.receipts.some(r=>r.owner==="alice"),false);
  assert.equal(result.consent.alice,undefined);assert.equal(total(result),300);
});
test("sync coverage is monotonic and cannot claim future coverage",()=>{
  let s=armed();s=applyTrustedSync(s,"alice",START+DAY,START+DAY);
  assert.equal(applyTrustedSync(s,"alice",START,START+DAY).syncThrough.alice,START+DAY);
  assert.throws(()=>applyTrustedSync(s,"alice",START+2*DAY,START+DAY));
});
test("projection contains counts, own wallet and membership but no biometrics or exact sessions",()=>{
  const s=addDays(armed(),"alice",3),projection=pledgeProjection(s,"bob");
  assert.equal(projection.members[0].days,3);assert.equal(projection.balance,80);
  for(const key of ["receipts","syncThrough","consent","fingerprint","heartRate","latitude"])assert.equal(JSON.stringify(projection).includes('"'+key+'"'),false);
  assert.throws(()=>pledgeProjection(s,"outsider"));
});

const activity=(changes={})=>({optedIn:true,paused:false,joinedAt:NOW-10*DAY,lastSessionAt:NOW-5*DAY,lastSyncAt:NOW,...changes});
test("activity status never calls stale/missing telemetry inactive",()=>{
  assert.equal(passiveMemberStatus(activity(),NOW),"atRisk");
  assert.equal(passiveMemberStatus(activity({lastSessionAt:NOW-DAY}),NOW),"active");
  assert.equal(passiveMemberStatus(activity({joinedAt:NOW-1000,lastSessionAt:NOW-3600000}),NOW),"active");
  for(const changes of [{lastSyncAt:null},{lastSyncAt:NOW-2*DAY},{optedIn:false},{paused:true},{joinedAt:NOW+DAY}])assert.equal(passiveMemberStatus(activity(changes),NOW),"hidden");
  assert.equal(passiveMemberStatus(activity({lastSessionAt:null,joinedAt:NOW-DAY}),NOW),"active");
});
const nudge=(changes={})=>({groupId:"group1",sender:"alice",recipient:"bob",members,friends:true,blocked:false,optedIn:true,status:"atRisk",lastRecipientNudgeAt:null,...changes});
test("nudge needs mutual relationship, group membership, recipient consent and inactivity",()=>{
  assert.equal(nudgeDecision(nudge(),NOW).allowed,true);
  for(const c of [{sender:"outsider"},{sender:"bob"},{friends:false},{blocked:true},{optedIn:false},{status:"hidden"},{status:"active"}])assert.equal(nudgeDecision(nudge(c),NOW).allowed,false);
});
test("recipient-wide cooldown prevents separate groups from piling on and respects quiet hours",()=>{
  assert.equal(nudgeDecision(nudge({groupId:"another",lastRecipientNudgeAt:NOW-1000}),NOW).reason,"recipient_cooldown");
  assert.equal(nudgeDecision(nudge(),Date.UTC(2026,10,3,23)).reason,"quiet_hours");
  assert.equal(nudgeDecision(nudge({timeZone:"Asia/Tokyo"}),NOW+2*3600000).reason,"quiet_hours");
  assert.equal(nudgeDecision(nudge({timeZone:"invalid"}),NOW).allowed,false);
  assert.equal(nudgeDecision(nudge(),NOW).interruptionLevel,"active");
  assert.equal(nudgeDecision(nudge(),NOW).eventId,nudgeDecision(nudge({groupId:"another"}),NOW).eventId);
});

function trace(owner,overrides={}) {
  return makeGhostTrace({id:owner+"Trace",owner,sport:"running",metric:"relativeEffort",startedAt:NOW-3600000,durationSeconds:1800,
    points:Array.from({length:30},()=>({value:50,observedSeconds:60})),consentVersion:1,...overrides},NOW);
}
test("ghost traces have bounded minute curves, consent and no inferred gap filling",()=>{
  for(const c of [{consentVersion:0},{durationSeconds:300},{startedAt:NOW},{points:[]},{metric:"rawHeartRate"}])assert.throws(()=>trace("alice",c));
  const points=trace("alice").points;points[0]={value:NaN,observedSeconds:60};assert.throws(()=>trace("alice",{points}));
  points[0]={value:null,observedSeconds:0};assert.equal(trace("alice",{points}).points[0].value,null);
});
test("ghost comparison uses matched observed minutes and reports an 8 percent effort difference without declaring a health winner",()=>{
  const a=trace("alice"),b=trace("bob",{points:Array.from({length:30},()=>({value:54,observedSeconds:60}))});
  const result=compareGhostTraces(a,b,1500);
  assert.equal(result.leadPercent,8);assert.equal(result.coverage,1);assert.equal(result.winner,null);
  assert.equal(compareGhostTraces(a,b,240).status,"insufficient");
});
test("gaps and zero ghost dose cannot produce a fabricated lead",()=>{
  const zero=trace("alice",{points:Array.from({length:30},()=>({value:0,observedSeconds:60}))});
  assert.equal(compareGhostTraces(zero,trace("bob"),1800).leadPercent,null);
  const gaps=trace("alice",{points:Array.from({length:30},(_,i)=>({value:i<8?50:null,observedSeconds:i<8?60:0}))});
  assert.equal(compareGhostTraces(gaps,trace("bob"),1800).status,"insufficient");
});
test("ghosts never compare different sports, units or the same person",()=>{
  assert.throws(()=>compareGhostTraces(trace("alice"),trace("bob",{sport:"cycling"}),1800));
  assert.throws(()=>compareGhostTraces(trace("alice"),trace("bob",{metric:"distanceMeters"}),1800));
  assert.throws(()=>compareGhostTraces(trace("alice"),trace("alice"),1800));
});
test("distance match has a winner only with the same sport and observed telemetry",()=>{
  const a=trace("alice",{metric:"distanceMeters"}),b=trace("bob",{metric:"distanceMeters",points:Array.from({length:30},()=>({value:60,observedSeconds:60}))});
  assert.equal(compareGhostTraces(a,b,1800).winner,"bob");
});
test("ghost pairing is frozen, explicitly consented, member-only and expires",()=>{
  const options={id:"duel1",groupId:"group1",members,ghost:trace("alice"),challenger:"bob",ghostConsent:true,challengerConsent:true};
  for(const c of [{challengerConsent:false},{ghostConsent:false},{challenger:"outsider"},{challenger:"alice"}])assert.throws(()=>createGhostMatch({...options,...c},NOW));
  const match=createGhostMatch(options,NOW);options.ghost.points[0].value=99;assert.equal(match.ghost.points[0].value,50);
  assert.throws(()=>createGhostMatch(options,NOW+8*DAY));
});
test("completed duel creates two stable result events once and rejects pre-pairing workouts",()=>{
  const match=createGhostMatch({id:"duel1",groupId:"group1",members,ghost:trace("alice"),challenger:"bob",ghostConsent:true,challengerConsent:true},NOW);
  const own=makeGhostTrace({...trace("bob"),id:"later",startedAt:NOW,durationSeconds:1800},NOW+1800000);
  const result=finishGhostMatch(match,own,NOW+1800000);
  assert.equal(result.status,"finished");assert.equal(result.events.length,2);
  assert.deepEqual(finishGhostMatch(result,own,NOW+2000000),result);
  assert.throws(()=>finishGhostMatch(match,trace("bob"),NOW));
  assert.throws(()=>finishGhostMatch(match,own,match.expiresAt+1));
});
