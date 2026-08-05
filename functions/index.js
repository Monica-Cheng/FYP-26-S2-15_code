// functions/index.js
// Cloud Functions for WiseWorkout.
//
// checkChallengeProgressOnSessionCreate is a server-side port of
// FirestoreService.computeChallengeProgress() / _maybeNotifyFriendsOfProgress()
// (lib/services/firestore_service.dart) — same date-range query, same
// isManuallyLogged exclusion, same 3-way distance branch (cardio/combined/
// gym), same calorie/duration summing, same unit conversion, same
// progressCache/progressNotifications paths and once-per-day dedup. It
// exists so challenge-progress notifications fire immediately on a new
// session write instead of waiting for the client to next open a
// Challenges screen and call computeChallengeProgress() itself.

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// Holds the OpenAI key as a Cloud Functions secret (v2 API) rather than a
// plaintext .env value — the previous approach in the Flutter app bundled
// .env as a Flutter asset (pubspec.yaml's flutter:assets:), which ships it
// inside every compiled APK/IPA. Set via `firebase functions:secrets:set
// OPENAI_API_KEY` (see deployment notes); never committed to source.
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

/**
 * Sums this user's progress toward `challenge` over its date range, using
 * the exact same logic as computeChallengeProgress() in
 * firestore_service.dart, then — if progress increased since the last
 * cached value — notifies friends among the other participants, honoring
 * the same once-per-day dedup marker the client-side version uses.
 *
 * @param {string} uid
 * @param {{id: string, startDate: FirebaseFirestore.Timestamp, endDate: FirebaseFirestore.Timestamp, metricType?: string, unit?: string, name?: string, participantUids?: string[]}} challenge
 */
async function computeAndNotify(uid, challenge) {
  const startDate = challenge.startDate;
  const endDate = challenge.endDate;
  const metricType = challenge.metricType || "distance";
  const unit = challenge.unit || "";

  // Same date-range shape as getSessionStats()/computeChallengeProgress():
  // date >= startDate AND date < endDate.
  const snapshot = await db
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .where("date", ">=", startDate)
      .where("date", "<", endDate)
      .get();

  let total = 0;
  snapshot.forEach((doc) => {
    const data = doc.data();
    // Manual sessions excluded entirely, not just deprioritized.
    if (data.isManuallyLogged === true) return;
    const type = data.type || "";

    switch (metricType) {
      case "distance":
        if (type === "cardio") {
          total += Number(data.distanceMeters) || 0;
        } else if (type === "combined") {
          const blocks = data.cardioBlocks;
          if (Array.isArray(blocks)) {
            blocks.forEach((b) => {
              if (b && typeof b === "object") {
                total += Number(b.distanceMeters) || 0;
              }
            });
          }
        }
        // 'gym' (and 'manual', already excluded) contribute 0.
        break;
      case "calories":
        total += Number(data.caloriesBurned) || 0;
        break;
      case "duration":
        total += Number(data.durationSeconds) || 0;
        break;
      default:
        break;
    }
  });

  // Raw totals are always in meters/calories/seconds — convert to the
  // challenge's own unit, same as computeChallengeProgress().
  let converted;
  if (metricType === "distance") {
    converted = unit === "km" ? total / 1000 : total;
  } else if (metricType === "duration") {
    if (unit === "min") {
      converted = total / 60;
    } else if (unit === "hr") {
      converted = total / 3600;
    } else {
      converted = total;
    }
  } else {
    converted = total; // calories: no conversion.
  }

  const challengeId = challenge.id;
  const cacheRef = db
      .collection("challenges")
      .doc(challengeId)
      .collection("progressCache")
      .doc(uid);
  const cacheDoc = await cacheRef.get();
  const previous =
      cacheDoc.exists && typeof cacheDoc.data().value === "number" ?
        cacheDoc.data().value :
        0;

  // Refresh the cache to the latest value regardless of outcome, so the
  // next comparison (from either this function or the client fallback)
  // always has today's true baseline.
  await cacheRef.set({
    value: converted,
    updatedAt: FieldValue.serverTimestamp(),
  });

  if (converted <= previous) return;

  const participantUids = Array.isArray(challenge.participantUids) ?
    challenge.participantUids :
    [];
  if (participantUids.length <= 1) return;

  const friendsSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("friends")
      .get();
  const friendUids = new Set(friendsSnapshot.docs.map((d) => d.id));

  const recipientUids = participantUids.filter(
      (p) => p !== uid && friendUids.has(p),
  );
  if (recipientUids.length === 0) return;

  const userDoc = await db.collection("users").doc(uid).get();
  const myName = (userDoc.exists && userDoc.data().displayName) || "A friend";
  const challengeName = challenge.name || "a challenge";

  const now = new Date();
  const dateKey = `${now.getFullYear()}-` +
      `${String(now.getMonth() + 1).padStart(2, "0")}-` +
      `${String(now.getDate()).padStart(2, "0")}`;

  for (const recipientUid of recipientUids) {
    // Same path/doc-id shape as _maybeNotifyFriendsOfProgress()'s dedup
    // marker: challenges/{challengeId}/progressNotifications/
    // {recipientUid}_{friendUid}_{yyyy-mm-dd}.
    const dedupRef = db
        .collection("challenges")
        .doc(challengeId)
        .collection("progressNotifications")
        .doc(`${recipientUid}_${uid}_${dateKey}`);
    const dedupDoc = await dedupRef.get();
    if (dedupDoc.exists) continue;

    const batch = db.batch();
    batch.set(dedupRef, {sentAt: FieldValue.serverTimestamp()});
    const notificationRef = db
        .collection("users")
        .doc(recipientUid)
        .collection("notifications")
        .doc();
    batch.set(notificationRef, {
      type: "challenge_friend_progress",
      challengeId,
      challengeName,
      fromUid: uid,
      fromDisplayName: myName,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}

exports.checkChallengeProgressOnSessionCreate = onDocumentCreated(
    "users/{uid}/sessions/{sessionId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const session = snap.data();
      const uid = event.params.uid;

      if (session.isManuallyLogged === true) return;

      const sessionDate = session.date;
      if (!sessionDate || typeof sessionDate.toMillis !== "function") return;
      const sessionMillis = sessionDate.toMillis();

      // Fetch every challenge uid participates in (cheap — arrayContains on
      // a single-field auto index, no composite index required since there's
      // no orderBy here), then filter to ones whose date range actually
      // covers this session in-memory. Combining array-contains with range
      // filters on two different fields (startDate/endDate) in one Firestore
      // query would need Firestore's multi-field-inequality support and a
      // matching composite index — filtering the (typically small)
      // already-fetched set in-memory is simpler and avoids that dependency.
      const challengesSnap = await db
          .collection("challenges")
          .where("participantUids", "array-contains", uid)
          .get();

      for (const doc of challengesSnap.docs) {
        const challenge = {id: doc.id, ...doc.data()};
        const startDate = challenge.startDate;
        const endDate = challenge.endDate;
        if (!startDate || !endDate) continue;
        const startMillis = startDate.toMillis();
        const endMillis = endDate.toMillis();
        // Same boundary semantics as computeChallengeProgress()'s own
        // session query: startDate <= session.date < endDate.
        if (sessionMillis < startMillis || sessionMillis >= endMillis) {
          continue;
        }

        try {
          await computeAndNotify(uid, challenge);
        } catch (err) {
          console.error(
              `checkChallengeProgressOnSessionCreate: failed for ` +
              `challenge ${challenge.id}, uid ${uid}:`,
              err,
          );
        }
      }
    },
);

/**
 * sendAdminBroadcast — fans an admin-authored message out to every user's
 * own users/{uid}/notifications subcollection, reusing the exact same
 * notification document shape/conventions as the friend-request/challenge-
 * invite notifications already in use (see the doc-writing shape in
 * lib/services/firestore_service.dart's sendFriendRequest()/
 * _writeChallengeInviteNotifications()).
 *
 * Triggered by the admin (React) dashboard creating a document in the new
 * adminBroadcasts collection via its own privileged Admin SDK connection —
 * never by the Flutter app's client SDK, which has no write path to this
 * collection at all (no rule grants it).
 *
 * Idempotency: `processed` starts false and is set true only once the
 * entire fan-out has committed successfully. If this function is ever
 * re-triggered on the same already-completed document (Cloud Functions'
 * at-least-once delivery guarantee), the processed check below exits
 * immediately instead of re-sending to every user a second time. This does
 * NOT protect against a mid-flight crash between two chunked batches within
 * a single execution (some users could already have been notified before a
 * later batch fails) — an acceptable, known limitation for a broadcast
 * feature at this project's current scale, not a full exactly-once
 * guarantee; documented in ADMIN_BROADCAST_SCHEMA.md.
 */
exports.sendAdminBroadcast = onDocumentCreated(
    "adminBroadcasts/{broadcastId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const broadcastId = event.params.broadcastId;
      const broadcast = snap.data();

      if (broadcast.processed === true) {
        // Already fully sent — a re-trigger on the same doc must never
        // double-send.
        return;
      }

      // Only 'all' is implemented today. Any other value fails loudly here
      // (logged, function exits) rather than silently doing nothing or
      // guessing at a segmentation rule that doesn't exist yet — adding a
      // new audience value requires updating this function's matching
      // logic, not just writing a new string from the dashboard.
      if (broadcast.audience !== "all") {
        console.error(
            `sendAdminBroadcast: unsupported audience "${broadcast.audience}" ` +
            `on adminBroadcasts/${broadcastId} — only 'all' is implemented ` +
            "today. Not processing.",
        );
        return;
      }

      const message = broadcast.message;
      if (typeof message !== "string" || message.trim() === "") {
        console.error(
            `sendAdminBroadcast: adminBroadcasts/${broadcastId} has no ` +
            "usable message field — nothing to send.",
        );
        return;
      }

      // Full collection read — acceptable at this project's current small
      // user count; the fan-out writes below are chunked regardless of
      // that count.
      const usersSnap = await db.collection("users").get();
      const uids = usersSnap.docs.map((d) => d.id);

      // Chunk into batches of <=500 — Firestore's hard per-batch write
      // limit — same defensive chunking convention already used elsewhere
      // in this codebase (e.g. getFriendsLeaderboardStream()'s 30-value
      // whereIn chunks), just at Firestore's write-batch cap instead of a
      // query's whereIn cap.
      for (let i = 0; i < uids.length; i += 500) {
        const chunk = uids.slice(i, i + 500);
        const batch = db.batch();
        for (const uid of chunk) {
          const notificationRef = db
              .collection("users")
              .doc(uid)
              .collection("notifications")
              .doc();
          batch.set(notificationRef, {
            type: "admin_broadcast",
            message,
            fromDisplayName: "WiseWorkout",
            read: false,
            createdAt: FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      await snap.ref.update({processed: true});
    },
);

// ---------------------------------------------------------------------------
// Shared helpers for the week-over-week delta (chat) and the 3 insight
// lines (chat + post-session summary) — see buildInsights() below for the
// orchestrator and callWiseCoachOpenAI for how the two features wire these
// in differently (consent-gated vs always-on).
// ---------------------------------------------------------------------------

/**
 * Monday-start week boundaries, weekOffset weeks from `now`'s week
 * (0 = this week, -1 = last week). Mirrors firestore_service.dart's
 * getWeeklySessionStats(): `today.subtract(Duration(days: today.weekday -
 * 1))`, i.e. Mon..Sun, [weekStart, weekEnd) half-open like every other
 * date-range query in this file.
 *
 * @param {Date} now
 * @param {number} weekOffset
 * @return {{weekStart: Date, weekEnd: Date}}
 */
function getWeekRange(now, weekOffset) {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const jsDay = today.getDay(); // 0=Sun..6=Sat
  const isoWeekday = jsDay === 0 ? 7 : jsDay; // 1=Mon..7=Sun
  const weekStart = new Date(today);
  weekStart.setDate(today.getDate() - (isoWeekday - 1) + weekOffset * 7);
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekStart.getDate() + 7);
  return {weekStart, weekEnd};
}

/**
 * Totals-only mirror of getSessionStats() in firestore_service.dart for a
 * [startDate, endDate) range — same fields summed the same way (no
 * isManuallyLogged exclusion, matching that method exactly since it backs
 * the Progress tab's chart filters). The bucket/day-array breakdown that
 * method also computes is omitted here — nothing downstream needs it.
 *
 * @param {string} uid
 * @param {Date} startDate
 * @param {Date} endDate
 * @return {Promise<{totalCalories: number, totalVolume: number,
 *   totalSessions: number, gymSessions: number, cardioSessions: number}>}
 */
async function computeSessionStats(uid, startDate, endDate) {
  const snapshot = await db
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .where("date", ">=", startDate)
      .where("date", "<", endDate)
      .get();

  let totalCalories = 0;
  let totalVolume = 0;
  let totalSessions = 0;
  let gymSessions = 0;
  let cardioSessions = 0;

  snapshot.forEach((doc) => {
    const data = doc.data();
    const cals = Number(data.caloriesBurned) || 0;
    const vol = Number(data.totalVolume) || 0;
    const type = data.type || "";
    totalCalories += Math.round(cals);
    totalVolume += vol;
    totalSessions++;
    if (type === "gym") gymSessions++;
    if (type === "cardio") cardioSessions++;
  });

  return {
    totalCalories,
    totalVolume: Math.round(totalVolume),
    totalSessions,
    gymSessions,
    cardioSessions,
  };
}

/**
 * Formats the week-over-week delta line for chat's personalization
 * context (decision: replaces the old flat "last 5 sessions" list) — the
 * percentage is pre-computed here, not left for the LLM to derive from
 * two raw numbers.
 *
 * @param {{totalSessions: number, totalVolume: number}} thisWeek
 * @param {{totalSessions: number, totalVolume: number}} lastWeek
 * @return {string}
 */
function formatWeekDeltaLine(thisWeek, lastWeek) {
  const plural = (n) => (n === 1 ? "session" : "sessions");
  let deltaPart = "";
  if (lastWeek.totalVolume > 0) {
    const pct = Math.round(
        ((thisWeek.totalVolume - lastWeek.totalVolume) / lastWeek.totalVolume) * 100,
    );
    const sign = pct >= 0 ? "+" : "";
    deltaPart = ` (${sign}${pct}% vs last week: ${lastWeek.totalSessions} ` +
        `${plural(lastWeek.totalSessions)}, ${lastWeek.totalVolume}kg)`;
  } else if (lastWeek.totalSessions > 0) {
    deltaPart = ` (vs last week: ${lastWeek.totalSessions} ` +
        `${plural(lastWeek.totalSessions)}, ${lastWeek.totalVolume}kg)`;
  }
  return `This week: ${thisWeek.totalSessions} ${plural(thisWeek.totalSessions)}, ` +
      `${thisWeek.totalVolume}kg volume${deltaPart}.`;
}

/**
 * Total distance for one session doc, handling the 3-way branch other
 * server-side code in this file already uses (computeAndNotify() above):
 * cardio reads its own top-level distanceMeters; combined has to sum
 * cardioBlocks[].distanceMeters instead, since combined sessions never get
 * a top-level distanceMeters field. Fixes the bug where earlier insight
 * code (and buildPersonalizationContext's old flat session list) only
 * checked top-level distanceMeters and silently read 0 for combined
 * sessions with real cardio blocks.
 *
 * @param {FirebaseFirestore.DocumentData} data
 * @return {number}
 */
function sessionDistanceMeters(data) {
  const type = data.type || "";
  if (type === "cardio") {
    return Number(data.distanceMeters) || 0;
  }
  if (type === "combined") {
    const blocks = data.cardioBlocks;
    let total = 0;
    if (Array.isArray(blocks)) {
      blocks.forEach((b) => {
        if (b && typeof b === "object") total += Number(b.distanceMeters) || 0;
      });
    }
    return total;
  }
  return 0;
}

// Which prior session types are a meaningful comparison for a given
// just-completed session type — decision: "compare whatever data types
// actually overlap". 'manual' is deliberately absent as a key AND never
// appears in any value list — manual logs have no volume/distance/exercise
// data worth comparing, so they're excluded by construction rather than an
// extra isManuallyLogged check at every call site.
const COMPARABLE_TYPES = {
  gym: ["gym", "combined"],
  cardio: ["cardio", "combined"],
  combined: ["gym", "cardio", "combined"],
};

/**
 * Finds up to `count` prior sessions comparable to `latestType`, per
 * decision 2's type-matching rules (COMPARABLE_TYPES above), excluding
 * `excludeId` (the just-completed/most-recent session itself). Reuses
 * getSessionsPage()'s plain orderBy('date','desc') shape (no equality
 * filter alongside it, so no composite index needed) rather than a new
 * query shape — the type/manual filtering happens in-memory over one
 * fetched page, same "filter the already-fetched set" approach
 * checkChallengeProgressOnSessionCreate uses above for its own composite-
 * index-avoidance reasons.
 *
 * @param {string} uid
 * @param {string} excludeId
 * @param {string} latestType
 * @param {number} count
 * @return {Promise<FirebaseFirestore.DocumentData[]>}
 */
async function findSimilarSessions(uid, excludeId, latestType, count) {
  const compatibleTypes = COMPARABLE_TYPES[latestType];
  if (!compatibleTypes) return [];

  const snapshot = await db
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .orderBy("date", "desc")
      .limit(30)
      .get();

  const results = [];
  for (const doc of snapshot.docs) {
    if (doc.id === excludeId) continue;
    const data = doc.data();
    if (!compatibleTypes.includes(data.type)) continue;
    results.push({id: doc.id, ...data});
    if (results.length >= count) break;
  }
  return results;
}

/**
 * Insight (a): volume trend (gym/combined) and/or distance trend
 * (cardio/combined) for `latest` against `comparable` sessions — a
 * combined-type `latest` can produce both lines since it has both kinds of
 * data. Each trend line is only built when there's at least one comparable
 * session with real (>0) data for that metric — per decision 2, never
 * force a comparison using a field a prior session doesn't meaningfully
 * have.
 *
 * @param {FirebaseFirestore.DocumentData} latest
 * @param {FirebaseFirestore.DocumentData[]} comparable
 * @return {string[]}
 */
function buildVolumeTrendLines(latest, comparable) {
  const average = (nums) =>
    nums.reduce((a, b) => a + b, 0) / nums.length;
  const type = latest.type || "";
  const lines = [];

  if (type === "gym" || type === "combined") {
    const curVolume = Number(latest.totalVolume) || 0;
    const priorVolumes = comparable
        .filter((s) => s.type === "gym" || s.type === "combined")
        .map((s) => Number(s.totalVolume) || 0)
        .filter((v) => v > 0);
    if (curVolume > 0 && priorVolumes.length > 0) {
      const avg = average(priorVolumes);
      const pct = avg > 0 ? Math.round(((curVolume - avg) / avg) * 100) : 0;
      const trendWord = pct >= 0 ? `up ~${pct}%` : `down ~${Math.abs(pct)}%`;
      lines.push(
          `Volume: ${Math.round(curVolume)}kg - ${trendWord} from your last ` +
          `${priorVolumes.length} comparable session${priorVolumes.length === 1 ? "" : "s"} ` +
          `(avg ${Math.round(avg)}kg).`,
      );
    }
  }

  if (type === "cardio" || type === "combined") {
    const curDistance = sessionDistanceMeters(latest);
    const priorDistances = comparable
        .map((s) => sessionDistanceMeters(s))
        .filter((d) => d > 0);
    if (curDistance > 0 && priorDistances.length > 0) {
      const avg = average(priorDistances);
      const pct = avg > 0 ? Math.round(((curDistance - avg) / avg) * 100) : 0;
      const trendWord = pct >= 0 ? `up ~${pct}%` : `down ~${Math.abs(pct)}%`;
      lines.push(
          `Distance: ${(curDistance / 1000).toFixed(1)}km - ${trendWord} from your last ` +
          `${priorDistances.length} comparable session${priorDistances.length === 1 ? "" : "s"} ` +
          `(avg ${(avg / 1000).toFixed(1)}km).`,
      );
    }
  }

  return lines;
}

/**
 * Insight (b): plan-frequency adherence — this week's totalSessions
 * (already computed by the caller via computeSessionStats(), not
 * recomputed here) against the tracked plan's daysPerWeek field. Returns
 * null (omit this insight) when there's no tracked plan or the plan doc
 * has no usable daysPerWeek, same "omit rather than send a placeholder"
 * convention buildPersonalizationContext's other categories already use.
 *
 * @param {FirebaseFirestore.DocumentData} userData
 * @param {number} thisWeekSessions
 * @return {Promise<string|null>}
 */
async function buildPlanAdherenceLine(userData, thisWeekSessions) {
  const trackedPlanId = userData.trackedPlanId;
  if (typeof trackedPlanId !== "string" || trackedPlanId === "") return null;
  try {
    const planDoc = await db.collection("plans").doc(trackedPlanId).get();
    if (!planDoc.exists) return null;
    const daysPerWeek = Number(planDoc.data().daysPerWeek) || 0;
    if (daysPerWeek <= 0) return null;
    return `${thisWeekSessions} of your planned ${daysPerWeek} sessions this week.`;
  } catch (err) {
    console.error(
        `buildPlanAdherenceLine: plan read failed for planId ${trackedPlanId}:`,
        err,
    );
    return null;
  }
}

function dateKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/**
 * Insight (c): streak/rest-day consistency — a JS port of
 * calculateStreakDates() in firestore_service.dart (same backward walk
 * from today/yesterday, same isManuallyLogged exclusion on session dates,
 * same dailyActivityLog isRestDay-protected rest days), plus a count of
 * how many of the in-progress streak's dates fall in the current week and
 * were rest days rather than real sessions, for the "including N protected
 * rest days this week" clause.
 *
 * @param {string} uid
 * @param {Date} now
 * @return {Promise<string|null>} null if there's no active streak at all.
 */
async function buildStreakLine(uid, now) {
  const sessionsSnap = await db
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .get();
  const sessionDates = new Set();
  sessionsSnap.forEach((doc) => {
    const data = doc.data();
    if (data.isManuallyLogged === true) return;
    const ts = data.date;
    if (ts && typeof ts.toDate === "function") {
      sessionDates.add(dateKey(ts.toDate()));
    }
  });

  const restLogSnap = await db
      .collection("users")
      .doc(uid)
      .collection("dailyActivityLog")
      .get();
  const restDates = new Set();
  restLogSnap.forEach((doc) => {
    if (doc.data().isRestDay === true) restDates.add(doc.id);
  });

  if (sessionDates.size === 0 && restDates.size === 0) return null;

  const dayCounts = (d) =>
    sessionDates.has(dateKey(d)) || restDates.has(dateKey(d));

  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let check = dayCounts(today) ?
    new Date(today) :
    new Date(today.getTime() - 86400000);
  if (!dayCounts(check)) return null;

  const streakDates = [];
  while (dayCounts(check)) {
    streakDates.push(new Date(check));
    check = new Date(check.getTime() - 86400000);
  }

  const {weekStart, weekEnd} = getWeekRange(now, 0);
  const restDaysThisWeekInStreak = streakDates.filter(
      (d) => d >= weekStart && d < weekEnd && restDates.has(dateKey(d)),
  ).length;

  const restPart = restDaysThisWeekInStreak > 0 ?
    `, including ${restDaysThisWeekInStreak} protected rest day` +
      `${restDaysThisWeekInStreak === 1 ? "" : "s"} this week` :
    "";
  return `${streakDates.length}-day active streak${restPart}.`;
}

/**
 * Orchestrates the 3 shared insight lines (decision 3) used by BOTH chat's
 * personalization context and post-session summary — see
 * callWiseCoachOpenAI for how each feature wires this in differently
 * (consent-gated for chat, always-on for post-session summary; that
 * distinction lives entirely in the caller, not here).
 *
 * "Just completed" session, for insight (a)'s comparison, is always this
 * user's single most-recent session doc: literally true when called right
 * after post-session summary saves a session, and "the last session you
 * logged" is the correct analogous reference point for an ongoing chat
 * too — so both features share this one fetch instead of the caller having
 * to pass a session in.
 *
 * @param {string} uid
 * @param {FirebaseFirestore.DocumentData} userData
 * @param {Date} now
 * @return {Promise<{insightLines: string[], thisWeekStats: object}>}
 */
async function buildInsights(uid, userData, now) {
  const insightLines = [];

  const recentSnap = await db
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .orderBy("date", "desc")
      .limit(1)
      .get();
  if (!recentSnap.empty) {
    const doc = recentSnap.docs[0];
    const latest = {id: doc.id, ...doc.data()};
    if (latest.isManuallyLogged !== true) {
      const similar = await findSimilarSessions(uid, latest.id, latest.type, 5);
      buildVolumeTrendLines(latest, similar).forEach((l) => insightLines.push(l));
    }
  }

  const {weekStart: thisStart, weekEnd: thisEnd} = getWeekRange(now, 0);
  const thisWeekStats = await computeSessionStats(uid, thisStart, thisEnd);
  const planLine = await buildPlanAdherenceLine(userData, thisWeekStats.totalSessions);
  if (planLine) insightLines.push(planLine);

  const streakLine = await buildStreakLine(uid, now);
  if (streakLine) insightLines.push(streakLine);

  return {insightLines, thisWeekStats};
}

/**
 * Builds a compact, one-line-per-category personalization summary for
 * uid from their body profile, injury profile, active plan, and the
 * week-over-week delta + 3 shared insight lines (see buildInsights()
 * above) — omitting any category that's empty/missing entirely rather
 * than sending a placeholder/empty value to the LLM. Mirrors the exact
 * shapes/defaults FirestoreService already uses client-side
 * (getUserInjuryData()'s injuries:[]/injuryFilteringEnabled:false
 * defaults, planProgress/{planId}'s currentDayIndex/lastCompletedDate/
 * breakModeActive fields) — kept in sync by hand since this runs via
 * firebase-admin instead of the Flutter client. Only ever called when
 * aiPersonalizationConsent is already confirmed true by the caller.
 *
 * The flat "last 5 sessions" list this used to end with has been replaced
 * by a pre-computed week-over-week delta line (this week vs last week,
 * percentage already computed here rather than left for the LLM to derive)
 * plus the same 3 insight lines post-session summary also gets — see
 * buildInsights().
 *
 * Deliberately sends only short summarized text, never raw documents —
 * in particular, session docs' full `exercises` array and any
 * `photoBase64` field are never read into this summary at all (only the
 * headline stat per session), per this phase's scope.
 *
 * @param {string} uid
 * @param {FirebaseFirestore.DocumentData} userData - the already-fetched
 *   users/{uid} doc (avoids a second read of the same doc — body-profile
 *   fields and trackedPlanId/trackedPlanName live on it alongside
 *   aiPersonalizationConsent).
 * @param {Date} now
 * @return {Promise<string>} non-empty categories joined by newlines, or
 *   "" if nothing was available (brand-new user).
 */
async function buildPersonalizationContext(uid, userData, now) {
  const lines = [];

  // Body profile — only fields that are actually present are included;
  // a missing/undefined field is omitted, never sent as a blank value.
  const bodyParts = [];
  if (userData.dob) bodyParts.push(`DOB ${userData.dob}`);
  if (userData.biologicalSex) bodyParts.push(userData.biologicalSex);
  if (typeof userData.heightCm === "number") {
    bodyParts.push(`${userData.heightCm}cm`);
  }
  if (typeof userData.weightKg === "number") {
    bodyParts.push(`${userData.weightKg}kg`);
  }
  if (userData.experienceLevel) bodyParts.push(userData.experienceLevel);
  if (userData.primaryGoal) bodyParts.push(`goal: ${userData.primaryGoal}`);
  if (bodyParts.length > 0) {
    lines.push(`Body profile: ${bodyParts.join(", ")}.`);
  }

  // Injury profile — same shape/defaults as getUserInjuryData(): an
  // empty/missing injuries array means "omit this category" entirely.
  const injuries = Array.isArray(userData.injuries) ? userData.injuries : [];
  if (injuries.length > 0) {
    const injuryList = injuries
        .map((i) => `${i.name || i.bodyPart || "unspecified"}` +
            (i.severity ? ` (${i.severity})` : ""))
        .join(", ");
    lines.push(`Reported injuries: ${injuryList}.`);
  }

  // Active plan — trackedPlanId === '' (the same sentinel every existing
  // client-side consumer already checks) means nothing tracked, so this
  // category is omitted rather than fetched.
  const trackedPlanId = userData.trackedPlanId;
  if (typeof trackedPlanId === "string" && trackedPlanId !== "") {
    try {
      const progressDoc = await db
          .collection("users")
          .doc(uid)
          .collection("planProgress")
          .doc(trackedPlanId)
          .get();
      const progress = progressDoc.exists ? progressDoc.data() : null;
      const planName = userData.trackedPlanName || "their tracked plan";
      const parts = [`Currently tracking "${planName}"`];
      if (progress) {
        if (typeof progress.currentDayIndex === "number") {
          parts.push(`on day ${progress.currentDayIndex}`);
        }
        if (progress.breakModeActive === true) {
          parts.push("currently on a break");
        } else if (progress.lastCompletedDate) {
          parts.push(`last completed session ${progress.lastCompletedDate}`);
        }
      }
      lines.push(`${parts.join(", ")}.`);
    } catch (err) {
      console.error(
          `buildPersonalizationContext: planProgress read failed for ` +
          `uid ${uid}:`, err,
      );
    }
  }

  // Recent activity — week-over-week delta line, then the 3 shared insight
  // lines (volume/distance trend, plan adherence, streak/rest-day) — see
  // buildInsights() above. Replaces the old flat "last 5 sessions" list.
  try {
    const {weekStart: lastStart, weekEnd: lastEnd} = getWeekRange(now, -1);
    const [{insightLines, thisWeekStats}, lastWeekStats] = await Promise.all([
      buildInsights(uid, userData, now),
      computeSessionStats(uid, lastStart, lastEnd),
    ]);
    lines.push(formatWeekDeltaLine(thisWeekStats, lastWeekStats));
    insightLines.forEach((l) => lines.push(l));
  } catch (err) {
    console.error(
        `buildPersonalizationContext: insight computation failed for uid ` +
        `${uid}:`, err,
    );
  }

  return lines.join("\n");
}

/**
 * callWiseCoachOpenAI — server-side relay to OpenAI's chat completions
 * endpoint, shared by both WiseCoach features that currently call OpenAI:
 * the Coach tab chat (coach_screen.dart's _sendToOpenAI()) and the
 * post-session AI summary (post_session_summary_screen.dart's
 * _generateWiseCoachSummary()). Both features already assemble their own
 * full messages array (system prompt + conversation history for chat; a
 * single user-role prompt string for the summary) — this function is a
 * thin relay by default: it forwards the messages/params the client
 * assembled to OpenAI and returns the reply text unchanged. Message-limit
 * gating and referral logic are still later phases per the PRD's Section
 * 5.6 rollout; this phase adds only the personalization context below.
 *
 * One shared function rather than two separate ones: both features hit
 * the identical OpenAI endpoint/shape (a messages array + generation
 * params), differing only in the messages content and max_tokens the
 * client already computes — splitting that into two near-identical
 * relay functions would just duplicate the fetch/error-handling logic
 * below for no behavioral benefit. Matches the PRD's own framing too
 * ("a WiseCoach HTTPS Cloud Function", singular).
 *
 * Personalization (Phase 2): gated server-side on aiPersonalizationConsent
 * — never trusted from the client, since a client-side-only gate could be
 * bypassed by calling this function directly. request.auth.uid comes from
 * the verified Firebase Auth ID token Cloud Functions' callable protocol
 * attaches automatically (the cloud_functions Flutter SDK sends it for any
 * signed-in caller) — not a client-supplied field, so it can't be spoofed
 * to read another user's data. When consent is true, a compact context
 * summary (see buildPersonalizationContext() above — never raw Firestore
 * documents) is appended onto the EXISTING system-role message in the
 * incoming array, if one exists. It's deliberately never used to inject a
 * brand-new system message: post_session_summary_screen.dart's
 * _generateWiseCoachSummary() sends only a single user-role prompt with no
 * system message at all, and this is what keeps that feature's request
 * shape (and therefore its behavior) completely untouched by this gate,
 * without needing an explicit per-feature flag from the client. Any
 * failure while assembling personalization (a Firestore read error, etc.)
 * is caught and logged, never allowed to block the underlying chat reply —
 * personalization is additive and best-effort, not a hard dependency.
 *
 * Post-session summary insights (later phase): the absence of a
 * system-role message is what identifies a request as post-session
 * summary rather than chat (see the two branches below) — it's the same
 * signal the personalization comment above already relied on to know it's
 * safe to skip system-message injection for that feature. Unlike chat,
 * this branch is NOT gated by aiPersonalizationConsent: post-session
 * summary is a separate feature that has never had a consent gate, and
 * this phase doesn't add one. It always appends the 3 shared insight
 * lines (see buildInsights()) onto the single user-role message when uid
 * is present, best-effort/non-blocking exactly like the chat branch.
 *
 * @param {{messages: {role: string, content: string}[], maxTokens?: number, temperature?: number}} request.data
 * @return {Promise<{content: string}>}
 */
exports.callWiseCoachOpenAI = onCall(
    {secrets: [OPENAI_API_KEY]},
    async (request) => {
      const data = request.data || {};
      const messages = data.messages;
      if (!Array.isArray(messages) || messages.length === 0) {
        throw new HttpsError(
            "invalid-argument",
            "messages must be a non-empty array of {role, content}.",
        );
      }

      const uid = request.auth && request.auth.uid;
      if (uid) {
        try {
          const now = new Date();
          const systemMessage = messages.find((m) => m.role === "system");
          if (systemMessage) {
            // Chat — personalization (including the 3 shared insights)
            // only when the user has explicitly consented.
            const userDoc = await db.collection("users").doc(uid).get();
            const userData = userDoc.exists ? userDoc.data() : {};
            if (userData.aiPersonalizationConsent === true) {
              const context = await buildPersonalizationContext(uid, userData, now);
              if (context) {
                systemMessage.content =
                    `${systemMessage.content}\n\nWhat you know about this ` +
                    "user (reference this naturally where relevant, don't " +
                    `recite it verbatim):\n${context}`;
              }
            }
          } else {
            // Post-session summary — no system message, no consent gate
            // (never had one, see doc comment above). The 3 shared insight
            // lines are always appended onto the single user-role message.
            const userMessage = messages.find((m) => m.role === "user");
            if (userMessage) {
              const userDoc = await db.collection("users").doc(uid).get();
              const userData = userDoc.exists ? userDoc.data() : {};
              const {insightLines} = await buildInsights(uid, userData, now);
              if (insightLines.length > 0) {
                userMessage.content =
                    `${userMessage.content}\n\nAdditional context on this ` +
                    "user's recent training (weave this in naturally, " +
                    `don't just list it):\n${insightLines.join("\n")}`;
              }
            }
          }
        } catch (err) {
          console.error(
              `callWiseCoachOpenAI: personalization/insights failed for ` +
              `uid ${uid}:`, err,
          );
        }
      }

      const maxTokens =
        typeof data.maxTokens === "number" ? data.maxTokens : 300;
      const temperature =
        typeof data.temperature === "number" ? data.temperature : 0.7;

      let response;
      try {
        response = await fetch(
            "https://api.openai.com/v1/chat/completions",
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${OPENAI_API_KEY.value()}`,
              },
              body: JSON.stringify({
                model: "gpt-4o-mini",
                messages,
                max_tokens: maxTokens,
                temperature,
              }),
            },
        );
      } catch (err) {
        console.error("callWiseCoachOpenAI: fetch to OpenAI failed:", err);
        throw new HttpsError("unavailable", "Could not reach OpenAI.");
      }

      if (!response.ok) {
        const errText = await response.text();
        console.error(
            `callWiseCoachOpenAI: OpenAI error ${response.status}: ` +
            errText,
        );
        throw new HttpsError("internal", "OpenAI request failed.");
      }

      const json = await response.json();
      const content = json.choices &&
          json.choices[0] &&
          json.choices[0].message &&
          json.choices[0].message.content;

      if (typeof content !== "string") {
        console.error(
            "callWiseCoachOpenAI: unexpected OpenAI response shape:",
            JSON.stringify(json),
        );
        throw new HttpsError("internal", "Unexpected OpenAI response shape.");
      }

      return {content};
    },
);
