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
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

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
