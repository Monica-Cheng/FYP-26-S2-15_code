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

const crypto = require("crypto");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");

initializeApp();
const db = getFirestore();
const adminAuth = getAuth();

/**
 * Confirms that the caller is signed in and has an active admin record at:
 * admins/{firebaseAuthUid}
 *
 * @param {object} request Callable Cloud Function request.
 * @return {Promise<string>} The authenticated admin UID.
 */
async function requireAdmin(request) {
  const uid = request.auth && request.auth.uid;

  if (!uid) {
    throw new HttpsError(
        "unauthenticated",
        "You must sign in before accessing the admin portal.",
    );
  }

  const adminDoc = await db.collection("admins").doc(uid).get();

  if (!adminDoc.exists || adminDoc.data().active !== true) {
    throw new HttpsError(
        "permission-denied",
        "This account does not have administrator access.",
    );
  }

  return uid;
}

/**
 * Lets the React dashboard verify that the signed-in account is an admin.
 */
exports.adminCheckAccess = onCall(async (request) => {
  const uid = await requireAdmin(request);

  return {
    authorized: true,
    uid,
  };
});

/**
 * Returns the user fields required by the React Users page.
 * This uses Firebase Admin SDK on the server, so it does not depend on
 * the browser's restricted Firestore permissions.
 */
exports.adminListUsers = onCall(async (request) => {
  await requireAdmin(request);

  const snapshot = await db.collection("users").get();

  const users = snapshot.docs.map((userDoc) => {
    const data = userDoc.data();

    return {
      id: userDoc.id,
      displayName: data.displayName || "",
      username: data.username || "",
      email: data.email || "",
      level: typeof data.level === "number" ? data.level : 1,
      onboardingComplete: data.onboardingComplete === true,
      healthConnected: data.healthConnected === true,
      wearableConnected: data.wearableConnected === true,
      isPremium: data.isPremium === true,
      accountStatus:
        data.accountStatus === "suspended" ? "suspended" : "active",
      planMatchGoal: data.planMatchGoal || "",
      primaryGoal: data.primaryGoal || "",
      hometown: data.hometown || "",
      totalXp: typeof data.totalXp === "number" ? data.totalXp : 0,
      weeklyXp: typeof data.weeklyXp === "number" ? data.weeklyXp : 0,
      trackedPlanName: data.trackedPlanName || "",
      savedPlanIds: Array.isArray(data.savedPlanIds) ?
        data.savedPlanIds :
        [],
        bio: data.bio || "",
        preferredUnits: data.preferredUnits || "",
        
        notificationsEnabled: data.notificationsEnabled !== false,
        workoutReminders: data.workoutReminders !== false,
        streakAlerts: data.streakAlerts !== false,
        wiseCoachMessages: data.wiseCoachMessages !== false,
        
        reminderHour:
          typeof data.reminderHour === "number" ? data.reminderHour : 7,
        reminderMinute:
          typeof data.reminderMinute === "number" ? data.reminderMinute : 0,
        
        trackedPlanId: data.trackedPlanId || "",
        planMatchLevel: data.planMatchLevel || "",
        planMatchSport: data.planMatchSport || "",
        planMatchDays: data.planMatchDays || "",
        planMatchEquipment: data.planMatchEquipment || [],
    };
  });

  return {users};
});

/**
 * Suspends or reinstates a WiseWorkout account.
 *
 * Updates both Firebase Authentication and the Firestore user document.
 */
exports.adminSetUserSuspended = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const data = request.data || {};

  const targetUid = data.uid;
  const suspended = data.suspended;

  if (typeof targetUid !== "string" || targetUid.trim() === "") {
    throw new HttpsError(
        "invalid-argument",
        "A valid user UID is required.",
    );
  }

  if (typeof suspended !== "boolean") {
    throw new HttpsError(
        "invalid-argument",
        "suspended must be true or false.",
    );
  }

  if (targetUid === adminUid) {
    throw new HttpsError(
        "failed-precondition",
        "You cannot suspend your own admin account.",
    );
  }

  try {
    await adminAuth.updateUser(targetUid, {
      disabled: suspended,
    });

    await db.collection("users").doc(targetUid).set(
        {
          accountStatus: suspended ? "suspended" : "active",
          accountStatusUpdatedAt: FieldValue.serverTimestamp(),
          accountStatusUpdatedBy: adminUid,
        },
        {merge: true},
    );

    return {
      uid: targetUid,
      accountStatus: suspended ? "suspended" : "active",
    };
  } catch (err) {
    console.error(
        `adminSetUserSuspended failed for ${targetUid}:`,
        err,
    );

    if (err.code === "auth/user-not-found") {
      throw new HttpsError(
          "not-found",
          "The Firebase Authentication account was not found.",
      );
    }

    throw new HttpsError(
        "internal",
        "Failed to update the account status.",
    );
  }
});

/**
 * Updates the safe profile fields managed by the React User Detail panel.
 */
exports.adminUpdateUser = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const data = request.data || {};

  const targetUid = data.uid;
  const requestedChanges = data.changes;

  if (typeof targetUid !== "string" || targetUid.trim() === "") {
    throw new HttpsError(
        "invalid-argument",
        "A valid user UID is required.",
    );
  }

  if (
    !requestedChanges ||
    typeof requestedChanges !== "object" ||
    Array.isArray(requestedChanges)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "changes must be an object.",
    );
  }

  const allowedFields = new Set([
    "displayName",
    "username",
    "level",
    "isPremium",
    "planMatchGoal",
    "hometown",
    "bio",
    "preferredUnits",
    "notificationsEnabled",
    "workoutReminders",
    "streakAlerts",
    "wiseCoachMessages",
    "reminderHour",
    "reminderMinute",
  ]);

  const changes = {};

  for (const [field, value] of Object.entries(requestedChanges)) {
    if (!allowedFields.has(field)) {
      throw new HttpsError(
          "invalid-argument",
          `The field "${field}" cannot be edited from the admin dashboard.`,
      );
    }

    changes[field] = value;
  }

  if (Object.keys(changes).length === 0) {
    throw new HttpsError(
        "invalid-argument",
        "No profile changes were supplied.",
    );
  }

  if (
    "displayName" in changes &&
    (
      typeof changes.displayName !== "string" ||
      changes.displayName.trim() === ""
    )
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Display name cannot be empty.",
    );
  }

  if (
    "username" in changes &&
    typeof changes.username !== "string"
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Username must be a string.",
    );
  }

  if (
    "level" in changes &&
    (
      typeof changes.level !== "number" ||
      !Number.isInteger(changes.level) ||
      changes.level < 1
    )
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Level must be a positive whole number.",
    );
  }

  if (
    "isPremium" in changes &&
    typeof changes.isPremium !== "boolean"
  ) {
    throw new HttpsError(
        "invalid-argument",
        "isPremium must be true or false.",
    );
  }

  if (
    "preferredUnits" in changes &&
    !["", "metric", "imperial"].includes(changes.preferredUnits)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Preferred units must be metric, imperial, or empty.",
    );
  }

  if (
    "planMatchGoal" in changes &&
    ![
      "",
      "Build Muscle",
      "Improve Endurance",
      "Lose Weight",
      "Build Strength",
    ].includes(changes.planMatchGoal)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Invalid plan-match goal.",
    );
  }

  if (
    "reminderHour" in changes &&
    (
      typeof changes.reminderHour !== "number" ||
      !Number.isInteger(changes.reminderHour) ||
      changes.reminderHour < 0 ||
      changes.reminderHour > 23
    )
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Reminder hour must be between 0 and 23.",
    );
  }

  if (
    "reminderMinute" in changes &&
    (
      typeof changes.reminderMinute !== "number" ||
      !Number.isInteger(changes.reminderMinute) ||
      changes.reminderMinute < 0 ||
      changes.reminderMinute > 59
    )
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Reminder minute must be between 0 and 59.",
    );
  }

  const booleanFields = [
    "notificationsEnabled",
    "workoutReminders",
    "streakAlerts",
    "wiseCoachMessages",
  ];

  for (const field of booleanFields) {
    if (field in changes && typeof changes[field] !== "boolean") {
      throw new HttpsError(
          "invalid-argument",
          `${field} must be true or false.`,
      );
    }
  }

  changes.adminUpdatedAt = FieldValue.serverTimestamp();
  changes.adminUpdatedBy = adminUid;

  await db.collection("users").doc(targetUid).update(changes);

  const responseChanges = {...changes};
  delete responseChanges.adminUpdatedAt;

  return {
    uid: targetUid,
    changes: responseChanges,
  };
});

/**
 * Returns the selected user's tracked-plan progress for the admin panel.
 */
exports.adminGetUserPlanProgress = onCall(async (request) => {
  await requireAdmin(request);

  const data = request.data || {};
  const targetUid = data.uid;
  const planId = data.planId;

  if (typeof targetUid !== "string" || targetUid.trim() === "") {
    throw new HttpsError(
        "invalid-argument",
        "A valid user UID is required.",
    );
  }

  if (typeof planId !== "string" || planId.trim() === "") {
    throw new HttpsError(
        "invalid-argument",
        "A valid tracked plan ID is required.",
    );
  }

  const progressDoc = await db
      .collection("users")
      .doc(targetUid)
      .collection("planProgress")
      .doc(planId)
      .get();

  if (!progressDoc.exists) {
    return {
      exists: false,
      progress: null,
    };
  }

  const progress = progressDoc.data();

  return {
    exists: true,
    progress: {
      currentDayIndex:
        typeof progress.currentDayIndex === "number" ?
          progress.currentDayIndex :
          1,
      breakModeActive: progress.breakModeActive === true,
      breakStartDate: progress.breakStartDate || null,
      breakEndDate: progress.breakEndDate || null,
      breakDays:
        typeof progress.breakDays === "number" ?
          progress.breakDays :
          null,
      compressedDays: Array.isArray(progress.compressedDays) ?
        progress.compressedDays :
        [],
    },
  };
});

/**
 * Starts or ends Break Mode for a user's tracked plan.
 */
exports.adminSetUserBreakMode = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const data = request.data || {};
  const targetUid = data.uid;
  const planId = data.planId;
  const active = data.active;
  const days = data.days;

  if (typeof targetUid !== "string" || targetUid.trim() === "") {
    throw new HttpsError(
        "invalid-argument",
        "A valid user UID is required.",
    );
  }

  if (typeof planId !== "string" || planId.trim() === "") {
    throw new HttpsError(
        "invalid-argument",
        "A valid tracked plan ID is required.",
    );
  }

  if (typeof active !== "boolean") {
    throw new HttpsError(
        "invalid-argument",
        "active must be true or false.",
    );
  }

  const progressRef = db
      .collection("users")
      .doc(targetUid)
      .collection("planProgress")
      .doc(planId);

  const progressDoc = await progressRef.get();

  if (!progressDoc.exists) {
    throw new HttpsError(
        "not-found",
        "The user's tracked-plan progress document was not found.",
    );
  }

  if (active) {
    if (
      typeof days !== "number" ||
      !Number.isInteger(days) ||
      days < 1 ||
      days > 14
    ) {
      throw new HttpsError(
          "invalid-argument",
          "Break duration must be between 1 and 14 days.",
      );
    }

    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Singapore",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });

    const startDate = new Date();
    const endDate = new Date(startDate);
    endDate.setUTCDate(endDate.getUTCDate() + days);

    await progressRef.update({
      breakModeActive: true,
      breakStartDate: formatter.format(startDate),
      breakEndDate: formatter.format(endDate),
      breakDays: days,
      adminUpdatedAt: FieldValue.serverTimestamp(),
      adminUpdatedBy: adminUid,
    });
  } else {
    await progressRef.update({
      breakModeActive: false,
      breakStartDate: null,
      breakEndDate: null,
      breakDays: null,
      adminUpdatedAt: FieldValue.serverTimestamp(),
      adminUpdatedBy: adminUid,
    });
  }

  const updatedDoc = await progressRef.get();
  const updated = updatedDoc.data();

  return {
    progress: {
      currentDayIndex:
        typeof updated.currentDayIndex === "number" ?
          updated.currentDayIndex :
          1,
      breakModeActive: updated.breakModeActive === true,
      breakStartDate: updated.breakStartDate || null,
      breakEndDate: updated.breakEndDate || null,
      breakDays:
        typeof updated.breakDays === "number" ?
          updated.breakDays :
          null,
      compressedDays: Array.isArray(updated.compressedDays) ?
        updated.compressedDays :
        [],
    },
  };
});

/**
 * Compresses or restores the current tracked-plan day.
 */
exports.adminSetUserCompressedDay = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const data = request.data || {};
  const targetUid = data.uid;
  const planId = data.planId;
  const compressed = data.compressed;

  if (typeof targetUid !== "string" || targetUid.trim() === "") {
    throw new HttpsError(
        "invalid-argument",
        "A valid user UID is required.",
    );
  }

  if (typeof planId !== "string" || planId.trim() === "") {
    throw new HttpsError(
        "invalid-argument",
        "A valid tracked plan ID is required.",
    );
  }

  if (typeof compressed !== "boolean") {
    throw new HttpsError(
        "invalid-argument",
        "compressed must be true or false.",
    );
  }

  const progressRef = db
      .collection("users")
      .doc(targetUid)
      .collection("planProgress")
      .doc(planId);

  const progressDoc = await progressRef.get();

  if (!progressDoc.exists) {
    throw new HttpsError(
        "not-found",
        "The user's tracked-plan progress document was not found.",
    );
  }

  const progress = progressDoc.data();

  const currentDayIndex =
    typeof progress.currentDayIndex === "number" ?
      progress.currentDayIndex :
      1;

  const existingDays = Array.isArray(progress.compressedDays) ?
    progress.compressedDays :
    [];

  const compressedDays = compressed ?
    Array.from(new Set([...existingDays, currentDayIndex])) :
    existingDays.filter((day) => day !== currentDayIndex);

  await progressRef.update({
    compressedDays,
    adminUpdatedAt: FieldValue.serverTimestamp(),
    adminUpdatedBy: adminUid,
  });

  return {
    currentDayIndex,
    compressedDays,
  };
});

/**
 * Permanently deletes a WiseWorkout user and their related project data.
 *
 * Cleanup includes:
 * - Firebase Authentication account
 * - users/{uid} and every nested subcollection
 * - publicProfiles/{uid}
 * - posts created by the user, including comments/reactions
 * - follow relationships involving the user
 * - user-created challenges
 * - memberships/invitations in other challenges
 * - mirrored friend/request records under other users
 *
 * This operation is permanent.
 */
exports.adminDeleteUser = onCall(
  {
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (request) => {
    const adminUid = await requireAdmin(request);
    const data = request.data || {};

    const targetUid = data.uid;
    const confirmUid = data.confirmUid;

    if (typeof targetUid !== "string" || targetUid.trim() === "") {
      throw new HttpsError(
          "invalid-argument",
          "A valid user UID is required.",
      );
    }

    // Extra protection against an accidental or altered request.
    if (confirmUid !== targetUid) {
      throw new HttpsError(
          "failed-precondition",
          "The deletion confirmation does not match the target UID.",
      );
    }

    if (targetUid === adminUid) {
      throw new HttpsError(
          "failed-precondition",
          "You cannot delete your own administrator account.",
      );
    }

    // Do not permit deletion of another approved administrator.
    const targetAdminDoc = await db
        .collection("admins")
        .doc(targetUid)
        .get();

    if (
      targetAdminDoc.exists &&
      targetAdminDoc.data().active === true
    ) {
      throw new HttpsError(
          "failed-precondition",
          "An active administrator account cannot be deleted.",
      );
    }

    const userRef = db.collection("users").doc(targetUid);
    const userDoc = await userRef.get();

    let authUserExists = true;

    try {
      await adminAuth.getUser(targetUid);
    } catch (err) {
      if (err.code === "auth/user-not-found") {
        authUserExists = false;
      } else {
        console.error(
            `adminDeleteUser: Auth lookup failed for ${targetUid}:`,
            err,
        );

        throw new HttpsError(
            "internal",
            "Unable to verify the Firebase Authentication account.",
        );
      }
    }

    if (!userDoc.exists && !authUserExists) {
      throw new HttpsError(
          "not-found",
          "The selected user no longer exists.",
      );
    }

    // Disable login before cleanup begins. If the operation is retried,
    // the remaining deletions are designed to be safe to run again.
    if (authUserExists) {
      await adminAuth.updateUser(targetUid, {
        disabled: true,
      });
    }

    const deletedCounts = {
      posts: 0,
      follows: 0,
      createdChallenges: 0,
      updatedChallenges: 0,
      mirroredRecords: 0,
      notifications: 0,
    };

    try {
      // ---------------------------------------------------------------
      // 1. Delete posts authored by the user, including each post's
      // reactions and comments subcollections.
      // ---------------------------------------------------------------
      const postsSnapshot = await db
          .collection("posts")
          .where("uid", "==", targetUid)
          .get();

      for (const postDoc of postsSnapshot.docs) {
        await db.recursiveDelete(postDoc.ref);
        deletedCounts.posts += 1;
      }

      // ---------------------------------------------------------------
      // 2. Delete top-level follow relationships in both directions.
      // ---------------------------------------------------------------
      const [followingSnapshot, followerSnapshot] = await Promise.all([
        db
            .collection("follows")
            .where("followerUid", "==", targetUid)
            .get(),
        db
            .collection("follows")
            .where("followingUid", "==", targetUid)
            .get(),
      ]);

      const followRefs = new Map();

      for (const followDoc of followingSnapshot.docs) {
        followRefs.set(followDoc.ref.path, followDoc.ref);
      }

      for (const followDoc of followerSnapshot.docs) {
        followRefs.set(followDoc.ref.path, followDoc.ref);
      }

      if (followRefs.size > 0) {
        const writer = db.bulkWriter();

        for (const followRef of followRefs.values()) {
          writer.delete(followRef);
        }

        await writer.close();
        deletedCounts.follows = followRefs.size;
      }

      // ---------------------------------------------------------------
      // 3. Delete challenges created by the user, including progress
      // caches and progress-notification subcollections.
      // ---------------------------------------------------------------
      const createdChallengesSnapshot = await db
          .collection("challenges")
          .where("createdBy", "==", targetUid)
          .get();

      const deletedChallengeIds = new Set();

      for (const challengeDoc of createdChallengesSnapshot.docs) {
        deletedChallengeIds.add(challengeDoc.id);
        await db.recursiveDelete(challengeDoc.ref);
        deletedCounts.createdChallenges += 1;
      }

      // ---------------------------------------------------------------
      // 4. Remove the UID from other challenge memberships/invitations.
      // ---------------------------------------------------------------
      const [
        participantChallengesSnapshot,
        invitedChallengesSnapshot,
      ] = await Promise.all([
        db
            .collection("challenges")
            .where(
                "participantUids",
                "array-contains",
                targetUid,
            )
            .get(),
        db
            .collection("challenges")
            .where(
                "invitedUids",
                "array-contains",
                targetUid,
            )
            .get(),
      ]);

      const challengeRefs = new Map();

      for (const challengeDoc of participantChallengesSnapshot.docs) {
        if (!deletedChallengeIds.has(challengeDoc.id)) {
          challengeRefs.set(
              challengeDoc.ref.path,
              challengeDoc.ref,
          );
        }
      }

      for (const challengeDoc of invitedChallengesSnapshot.docs) {
        if (!deletedChallengeIds.has(challengeDoc.id)) {
          challengeRefs.set(
              challengeDoc.ref.path,
              challengeDoc.ref,
          );
        }
      }

      if (challengeRefs.size > 0) {
        const writer = db.bulkWriter();

        for (const challengeRef of challengeRefs.values()) {
          writer.update(challengeRef, {
            participantUids: FieldValue.arrayRemove(targetUid),
            invitedUids: FieldValue.arrayRemove(targetUid),
          });
        }

        await writer.close();
        deletedCounts.updatedChallenges = challengeRefs.size;
      }

      // ---------------------------------------------------------------
      // 5. Remove mirrored social records stored under other users.
      //
      // WiseWorkout stores friends and friend requests under each
      // user's own users/{uid} document, so deleting only the target
      // tree would leave references inside other users' trees.
      // ---------------------------------------------------------------
      const allUsersSnapshot = await db.collection("users").get();
      const socialWriter = db.bulkWriter();

      for (const otherUserDoc of allUsersSnapshot.docs) {
        if (otherUserDoc.id === targetUid) continue;

        const otherUserRef = otherUserDoc.ref;

        socialWriter.delete(
            otherUserRef
                .collection("friends")
                .doc(targetUid),
        );

        socialWriter.delete(
            otherUserRef
                .collection("friendRequests")
                .doc(targetUid),
        );

        socialWriter.delete(
            otherUserRef
                .collection("sentFriendRequests")
                .doc(targetUid),
        );

        deletedCounts.mirroredRecords += 3;

        // Remove notifications whose sender was the deleted user.
        const notificationSnapshot = await otherUserRef
            .collection("notifications")
            .where("fromUid", "==", targetUid)
            .get();

        for (const notificationDoc of notificationSnapshot.docs) {
          socialWriter.delete(notificationDoc.ref);
          deletedCounts.notifications += 1;
        }
      }

      await socialWriter.close();

      // ---------------------------------------------------------------
      // 6. Remove the public profile.
      // ---------------------------------------------------------------
      await db
          .collection("publicProfiles")
          .doc(targetUid)
          .delete();

      // Remove an inactive admins record if one happens to exist.
      await db
          .collection("admins")
          .doc(targetUid)
          .delete();

      // ---------------------------------------------------------------
      // 7. Recursively remove the private user tree and every nested
      // collection: sessions, notifications, friends, planProgress,
      // nutrition logs, XP events and any future subcollections.
      // ---------------------------------------------------------------
      await db.recursiveDelete(userRef);

      // ---------------------------------------------------------------
      // 8. Delete Firebase Authentication last. The account remains
      // disabled throughout cleanup and disappears once this succeeds.
      // ---------------------------------------------------------------
      if (authUserExists) {
        try {
          await adminAuth.deleteUser(targetUid);
        } catch (err) {
          if (err.code !== "auth/user-not-found") {
            throw err;
          }
        }
      }

      console.log(
          `adminDeleteUser: ${adminUid} permanently deleted ` +
          `${targetUid}`,
          deletedCounts,
      );

      return {
        deleted: true,
        uid: targetUid,
        deletedCounts,
      };
    } catch (err) {
      console.error(
          `adminDeleteUser failed for ${targetUid}:`,
          err,
      );

      // The account stays disabled if cleanup fails. This prevents a
      // partially deleted account from signing back in. The admin can
      // safely retry the same deletion operation.
      throw new HttpsError(
          "internal",
          "User deletion was not completed. The account has been " +
          "disabled and the deletion can be retried.",
      );
    }
  },
);

/**
 * Validates and normalizes exercise data sent by the admin dashboard.
 */
function normalizeAdminExerciseData(rawData) {
  const data = rawData || {};

  const name = typeof data.name === "string" ? data.name.trim() : "";
  const difficulty =
    typeof data.difficulty === "string" ? data.difficulty.trim() : "Beginner";
  const equipment =
    typeof data.equipment === "string" ? data.equipment.trim() : "";
  const muscle =
    typeof data.muscle === "string" ? data.muscle.trim() : "";
  const muscleGroup =
    typeof data.muscleGroup === "string" ? data.muscleGroup.trim() : "";
  const gifUrl =
    typeof data.gifUrl === "string" ? data.gifUrl.trim() : "";

  if (!name) {
    throw new HttpsError(
      "invalid-argument",
      "Exercise name is required.",
    );
  }

  if (!["Beginner", "Intermediate", "Advanced"].includes(difficulty)) {
    throw new HttpsError(
      "invalid-argument",
      "Difficulty must be Beginner, Intermediate, or Advanced.",
    );
  }

  const secondaryMuscles = Array.isArray(data.secondaryMuscles) ?
    data.secondaryMuscles
        .filter((value) => typeof value === "string")
        .map((value) => value.trim())
        .filter(Boolean) :
    [];

  const injuryRisk = Array.isArray(data.injuryRisk) ?
    data.injuryRisk
        .filter((value) => typeof value === "string")
        .map((value) => value.trim())
        .filter(Boolean) :
    [];

  const instructionSteps = Array.isArray(data.instructionSteps) ?
    data.instructionSteps
        .filter((value) => typeof value === "string")
        .map((value) => value.trim())
        .filter(Boolean) :
    [];

  const minReps = Number(data.minReps);
  const maxReps = Number(data.maxReps);
  const minKg = Number(data.minKg);
  const maxKg = Number(data.maxKg);

  if (!Number.isFinite(minReps) || minReps < 1) {
    throw new HttpsError(
      "invalid-argument",
      "Minimum reps must be at least 1.",
    );
  }

  if (!Number.isFinite(maxReps) || maxReps < minReps) {
    throw new HttpsError(
      "invalid-argument",
      "Maximum reps must be greater than or equal to minimum reps.",
    );
  }

  if (!Number.isFinite(minKg) || minKg < 0) {
    throw new HttpsError(
      "invalid-argument",
      "Minimum weight cannot be negative.",
    );
  }

  if (!Number.isFinite(maxKg) || maxKg < minKg) {
    throw new HttpsError(
      "invalid-argument",
      "Maximum weight must be greater than or equal to minimum weight.",
    );
  }

  if (instructionSteps.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "At least one instruction step is required.",
    );
  }

  return {
    name,
    difficulty,
    equipment,
    muscle,
    muscleGroup,
    secondaryMuscles,
    injuryRisk,
    instructionSteps,
    minReps,
    maxReps,
    minKg,
    maxKg,
    gifUrl: gifUrl || null,
  };
}

/**
 * Creates a new exercise in the shared exercise library.
 */
exports.adminCreateExercise = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const exerciseData = normalizeAdminExerciseData(
      request.data?.exercise,
  );

  const documentRef = await db.collection("exercises").add({
    ...exerciseData,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdByAdminUid: adminUid,
  });

  return {
    success: true,
    exerciseId: documentRef.id,
    exercise: exerciseData,
  };
});

/**
 * Updates an existing exercise without replacing unrelated fields.
 */
exports.adminUpdateExercise = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const exerciseId = request.data?.exerciseId;

  if (typeof exerciseId !== "string" || !exerciseId.trim()) {
    throw new HttpsError(
      "invalid-argument",
      "Exercise ID is required.",
    );
  }

  const exerciseData = normalizeAdminExerciseData(
      request.data?.exercise,
  );

  const documentRef = db
      .collection("exercises")
      .doc(exerciseId.trim());

  const snapshot = await documentRef.get();

  if (!snapshot.exists) {
    throw new HttpsError(
      "not-found",
      "Exercise not found.",
    );
  }

  await documentRef.update({
    ...exerciseData,
    updatedAt: FieldValue.serverTimestamp(),
    updatedByAdminUid: adminUid,
  });

  return {
    success: true,
    exerciseId: exerciseId.trim(),
    exercise: exerciseData,
  };
});

/**
 * Permanently deletes an exercise definition.
 *
 * Existing plans retain their embedded exercise copies.
 */
exports.adminDeleteExercise = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const exerciseId = request.data?.exerciseId;

  if (typeof exerciseId !== "string" || !exerciseId.trim()) {
    throw new HttpsError(
      "invalid-argument",
      "Exercise ID is required.",
    );
  }

  const documentRef = db
      .collection("exercises")
      .doc(exerciseId.trim());

  const snapshot = await documentRef.get();

  if (!snapshot.exists) {
    throw new HttpsError(
      "not-found",
      "Exercise not found.",
    );
  }

  await documentRef.delete();

  console.log(
      `adminDeleteExercise: ${adminUid} deleted ${exerciseId.trim()}`,
  );

  return {
    success: true,
    exerciseId: exerciseId.trim(),
  };
});

/**
 * Converts Firestore values into data that can safely be returned through
 * a callable Cloud Function.
 */
function serializeAdminFirestoreValue(value) {
  if (value === null || value === undefined) return value;

  if (value && typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }

  if (Array.isArray(value)) {
    return value.map((item) => serializeAdminFirestoreValue(item));
  }

  if (typeof value === "object") {
    const converted = {};

    for (const [key, nestedValue] of Object.entries(value)) {
      converted[key] = serializeAdminFirestoreValue(nestedValue);
    }

    return converted;
  }

  return value;
}

/**
 * Returns everything required by the React Challenges dashboard.
 *
 * Admin SDK bypasses client Firestore rules, so this includes private
 * challenges as well as global challenges.
 */
exports.adminListChallengeDashboard = onCall(async (request) => {
  await requireAdmin(request);

  const [
    challengeSnapshot,
    categorySnapshot,
    userSnapshot,
  ] = await Promise.all([
    db.collection("challenges").get(),
    db.collection("challengeCategories").orderBy("name").get(),
    db.collection("users").get(),
  ]);

  const challenges = challengeSnapshot.docs.map((challengeDoc) => ({
    id: challengeDoc.id,
    ...serializeAdminFirestoreValue(challengeDoc.data()),
  }));

  const categories = categorySnapshot.docs.map((categoryDoc) => ({
    id: categoryDoc.id,
    ...serializeAdminFirestoreValue(categoryDoc.data()),
  }));

  const users = userSnapshot.docs.map((userDoc) => {
    const data = userDoc.data();

    return {
      id: userDoc.id,
      displayName: data.displayName || "",
      username: data.username || "",
      email: data.email || "",
      accountStatus:
        data.accountStatus === "suspended" ? "suspended" : "active",
    };
  });

  return {
    challenges,
    categories,
    users,
  };
});

const ADMIN_CHALLENGE_METRIC_TYPES = [
  "distance",
  "calories",
  "duration",
];

function normalizeChallengeCategoryData(rawData) {
  const data = rawData || {};

  const name =
    typeof data.name === "string" ? data.name.trim() : "";

  const unit =
    typeof data.unit === "string" ? data.unit.trim() : "";

  const metricType =
    typeof data.metricType === "string" ?
      data.metricType.trim() :
      "";

  const minGoal = Number(data.minGoal);
  const maxGoal = Number(data.maxGoal);

  if (!name) {
    throw new HttpsError(
        "invalid-argument",
        "Category name is required.",
    );
  }

  if (!unit) {
    throw new HttpsError(
        "invalid-argument",
        "Category unit is required.",
    );
  }

  if (!ADMIN_CHALLENGE_METRIC_TYPES.includes(metricType)) {
    throw new HttpsError(
        "invalid-argument",
        "Metric type must be distance, calories, or duration.",
    );
  }

  if (!Number.isFinite(minGoal) || minGoal < 0) {
    throw new HttpsError(
        "invalid-argument",
        "Minimum goal must be a non-negative number.",
    );
  }

  if (!Number.isFinite(maxGoal) || maxGoal < minGoal) {
    throw new HttpsError(
        "invalid-argument",
        "Maximum goal must be greater than or equal to minimum goal.",
    );
  }

  return {
    name,
    unit,
    metricType,
    minGoal,
    maxGoal,
  };
}

/**
 * Creates an admin-managed challenge category.
 */
exports.adminCreateChallengeCategory = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const categoryData = normalizeChallengeCategoryData(
      request.data?.category,
  );

  const categoryRef = await db
      .collection("challengeCategories")
      .add({
        ...categoryData,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        createdByAdminUid: adminUid,
      });

  return {
    success: true,
    categoryId: categoryRef.id,
    category: categoryData,
  };
});

/**
 * Updates an existing challenge category.
 */
exports.adminUpdateChallengeCategory = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const categoryId = request.data?.categoryId;
  const requestedChanges = request.data?.changes || {};

  if (typeof categoryId !== "string" || !categoryId.trim()) {
    throw new HttpsError(
        "invalid-argument",
        "Category ID is required.",
    );
  }

  const categoryRef = db
      .collection("challengeCategories")
      .doc(categoryId.trim());

  const categorySnapshot = await categoryRef.get();

  if (!categorySnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Challenge category not found.",
    );
  }

  const existingData = categorySnapshot.data() || {};

  const normalizedData = normalizeChallengeCategoryData({
    name:
      requestedChanges.name !== undefined ?
        requestedChanges.name :
        existingData.name,
    unit:
      requestedChanges.unit !== undefined ?
        requestedChanges.unit :
        existingData.unit,
    metricType:
      requestedChanges.metricType !== undefined ?
        requestedChanges.metricType :
        existingData.metricType,
    minGoal:
      requestedChanges.minGoal !== undefined ?
        requestedChanges.minGoal :
        existingData.minGoal,
    maxGoal:
      requestedChanges.maxGoal !== undefined ?
        requestedChanges.maxGoal :
        existingData.maxGoal,
  });

  await categoryRef.update({
    ...normalizedData,
    updatedAt: FieldValue.serverTimestamp(),
    updatedByAdminUid: adminUid,
  });

  return {
    success: true,
    categoryId: categoryId.trim(),
    category: normalizedData,
  };
});

/**
 * Deletes an unused challenge category.
 */
exports.adminDeleteChallengeCategory = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const categoryId = request.data?.categoryId;

  if (typeof categoryId !== "string" || !categoryId.trim()) {
    throw new HttpsError(
        "invalid-argument",
        "Category ID is required.",
    );
  }

  const normalizedCategoryId = categoryId.trim();

  const categoryRef = db
      .collection("challengeCategories")
      .doc(normalizedCategoryId);

  const categorySnapshot = await categoryRef.get();

  if (!categorySnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Challenge category not found.",
    );
  }

  const challengeSnapshot = await db
      .collection("challenges")
      .where("categoryId", "==", normalizedCategoryId)
      .limit(1)
      .get();

  if (!challengeSnapshot.empty) {
    throw new HttpsError(
        "failed-precondition",
        "This category is still used by at least one challenge.",
    );
  }

  await categoryRef.delete();

  console.log(
      `adminDeleteChallengeCategory: ${adminUid} deleted ` +
      `${normalizedCategoryId}`,
  );

  return {
    success: true,
    categoryId: normalizedCategoryId,
  };
});

function normalizeGlobalChallengeData(rawData) {
  const data = rawData || {};

  const name =
    typeof data.name === "string" ? data.name.trim() : "";

  const categoryId =
    typeof data.categoryId === "string" ? data.categoryId.trim() : "";

  const metricType =
    typeof data.metricType === "string" ? data.metricType.trim() : "";

  const unit =
    typeof data.unit === "string" ? data.unit.trim() : "";

  const goalValue = Number(data.goalValue);

  const startDate = new Date(data.startDate);
  const endDate = new Date(data.endDate);

  if (!name) {
    throw new HttpsError(
        "invalid-argument",
        "Challenge name is required.",
    );
  }

  if (!categoryId) {
    throw new HttpsError(
        "invalid-argument",
        "Challenge category is required.",
    );
  }

  if (!ADMIN_CHALLENGE_METRIC_TYPES.includes(metricType)) {
    throw new HttpsError(
        "invalid-argument",
        "Metric type must be distance, calories, or duration.",
    );
  }

  if (!unit) {
    throw new HttpsError(
        "invalid-argument",
        "Challenge unit is required.",
    );
  }

  if (!Number.isFinite(goalValue)) {
    throw new HttpsError(
        "invalid-argument",
        "Goal value must be a valid number.",
    );
  }

  if (
    Number.isNaN(startDate.getTime()) ||
    Number.isNaN(endDate.getTime())
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Start date and end date must be valid.",
    );
  }

  if (endDate <= startDate) {
    throw new HttpsError(
        "invalid-argument",
        "End date must be after start date.",
    );
  }

  return {
    name,
    categoryId,
    metricType,
    unit,
    goalValue,
    startDate,
    endDate,
  };
}

/**
 * Creates a global challenge that users can discover and join.
 */
exports.adminCreateGlobalChallenge = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const challengeData = normalizeGlobalChallengeData(
      request.data?.challenge,
  );

  const categoryRef = db
      .collection("challengeCategories")
      .doc(challengeData.categoryId);

  const categorySnapshot = await categoryRef.get();

  if (!categorySnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Challenge category not found.",
    );
  }

  const category = categorySnapshot.data() || {};

  if (
    category.metricType !== challengeData.metricType ||
    category.unit !== challengeData.unit
  ) {
    throw new HttpsError(
        "failed-precondition",
        "Challenge category values do not match.",
    );
  }

  const minGoal = Number(category.minGoal);
  const maxGoal = Number(category.maxGoal);

  if (
    challengeData.goalValue < minGoal ||
    challengeData.goalValue > maxGoal
  ) {
    throw new HttpsError(
        "invalid-argument",
        `Goal value must be between ${minGoal} and ${maxGoal} ${category.unit}.`,
    );
  }

  const challengeRef = await db.collection("challenges").add({
    name: challengeData.name,
    categoryId: challengeData.categoryId,
    metricType: challengeData.metricType,
    unit: challengeData.unit,
    goalValue: challengeData.goalValue,
    startDate: challengeData.startDate,
    endDate: challengeData.endDate,
    isGlobal: true,
    createdBy: adminUid,
    participantUids: [],
    invitedUids: [],
    createdAt: FieldValue.serverTimestamp(),
  });


  return {
    success: true,
    challengeId: challengeRef.id,
    challenge: {
      name: challengeData.name,
      categoryId: challengeData.categoryId,
      metricType: challengeData.metricType,
      unit: challengeData.unit,
      goalValue: challengeData.goalValue,
      startDate: challengeData.startDate.toISOString(),
      endDate: challengeData.endDate.toISOString(),
      isGlobal: true,
      createdBy: adminUid,
      participantUids: [],
      invitedUids: [],
    },
  };
});

/**
 * Permanently deletes a challenge.
 */
exports.adminDeleteChallenge = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const challengeId = request.data?.challengeId;

  if (typeof challengeId !== "string" || !challengeId.trim()) {
    throw new HttpsError(
        "invalid-argument",
        "Challenge ID is required.",
    );
  }

  const challengeRef = db
      .collection("challenges")
      .doc(challengeId.trim());

  const challengeSnapshot = await challengeRef.get();

  if (!challengeSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Challenge not found.",
    );
  }

  const challenge = challengeSnapshot.data() || {};

  if (challenge.isGlobal !== true) {
    throw new HttpsError(
        "failed-precondition",
        "Admin deletion is limited to global challenges.",
    );
  }

  const participantUids = Array.isArray(challenge.participantUids)
    ? challenge.participantUids
    : [];

  if (participantUids.length > 0) {
    throw new HttpsError(
        "failed-precondition",
        "Cannot delete a global challenge after users have joined.",
    );
  }

  await challengeRef.delete();

  console.log(
      `adminDeleteChallenge: ${adminUid} deleted ${challengeId.trim()}`,
  );

  return {
    success: true,
    challengeId: challengeId.trim(),
  };
});

/**
 * Returns everything required by the React Plans dashboard.
 *
 * Includes official and custom plans, limited user fields for creator
 * labels, and the exercise catalog used by the plan session editor.
 */
exports.adminListPlansDashboard = onCall(async (request) => {
  await requireAdmin(request);

  const [
    plansSnapshot,
    usersSnapshot,
    exercisesSnapshot,
  ] = await Promise.all([
    db.collection("plans").get(),
    db.collection("users").get(),
    db.collection("exercises").get(),
  ]);

  const plans = plansSnapshot.docs.map((planDoc) => ({
    id: planDoc.id,
    ...serializeAdminFirestoreValue(planDoc.data()),
  }));

  const users = usersSnapshot.docs.map((userDoc) => {
    const data = userDoc.data();

    return {
      id: userDoc.id,
      displayName: data.displayName || "",
      email: data.email || "",
      username: data.username || "",
    };
  });

  const exercises = exercisesSnapshot.docs.map((exerciseDoc) => {
    const data = exerciseDoc.data();

    return {
      id: exerciseDoc.id,
      name: data.name || "",
      muscleGroup: data.muscleGroup || "",
    };
  });

  return {
    plans,
    users,
    exercises,
  };
});

function requireNonEmptyAdminString(value, fieldName) {
  const normalized =
    typeof value === "string" ? value.trim() : "";

  if (!normalized) {
    throw new HttpsError(
        "invalid-argument",
        `${fieldName} is required.`,
    );
  }

  return normalized;
}

function normalizeAdminStringArray(value) {
  if (!Array.isArray(value)) return [];

  return value
      .filter((item) => typeof item === "string")
      .map((item) => item.trim())
      .filter(Boolean);
}

function normalizeAdminPlanSessions(value) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpsError(
        "invalid-argument",
        "At least one plan session is required.",
    );
  }

  return value.map((rawSession, sessionIndex) => {
    const session =
      rawSession && typeof rawSession === "object" ?
        rawSession :
        {};

    const isRestDay = session.isRestDay === true;
    const name =
      typeof session.name === "string" ?
        session.name.trim() :
        "";

    if (!isRestDay && !name) {
      throw new HttpsError(
          "invalid-argument",
          `Session ${sessionIndex + 1} requires a name.`,
      );
    }

    const rawExercises = Array.isArray(session.exercises) ?
      session.exercises :
      [];

    if (!isRestDay && rawExercises.length === 0) {
      throw new HttpsError(
          "invalid-argument",
          `Session ${sessionIndex + 1} requires an exercise.`,
      );
    }

    const exercises = rawExercises.map((rawExercise, exerciseIndex) => {
      const exercise =
        rawExercise && typeof rawExercise === "object" ?
          {...rawExercise} :
          {};

      if (exercise.isCardio === true) {
        const cardioActivity = requireNonEmptyAdminString(
            exercise.cardioActivity,
            `Session ${sessionIndex + 1}, cardio activity`,
        );

        const cardioMinutes = Number(exercise.cardioMinutes);

        if (!Number.isInteger(cardioMinutes) || cardioMinutes <= 0) {
          throw new HttpsError(
              "invalid-argument",
              `Session ${sessionIndex + 1}, cardio block ` +
              `${exerciseIndex + 1} requires valid minutes.`,
          );
        }

        return {
          ...exercise,
          isCardio: true,
          cardioActivity,
          cardioMinutes,
        };
      }

      const exerciseName = requireNonEmptyAdminString(
          exercise.name,
          `Session ${sessionIndex + 1}, exercise ${exerciseIndex + 1} name`,
      );

      const muscle = requireNonEmptyAdminString(
          exercise.muscle,
          `Session ${sessionIndex + 1}, exercise ${exerciseIndex + 1} muscle`,
      );

      return {
        ...exercise,
        name: exerciseName,
        muscle,
      };
    });

    return {
      ...session,
      name: name || "Rest",
      isRestDay,
      exercises: isRestDay ? [] : exercises,
    };
  });
}

function normalizeAdminDesignedBy(value) {
  if (!value || typeof value !== "object") return null;

  const normalized = {};

  for (const field of ["name", "title", "credential", "quote"]) {
    if (typeof value[field] === "string" && value[field].trim()) {
      normalized[field] = value[field].trim();
    }
  }

  return Object.keys(normalized).length > 0 ? normalized : null;
}

// Canonical plan.type values. "Running" was renamed to "Cardio" (see
// functions/scripts/migrate_running_to_cardio.js for the one-time data
// migration this pairs with) and "Combine" added as a new third value —
// this only governs plans/{id}.type (validated below) and, by extension,
// matchSport when it defaults to type. matchSport itself stays free-text
// when the admin sets it explicitly (see normalizeOfficialPlanData below),
// since it's used for fuzzy substring matching in plan_match_screen.dart,
// not as a strict enum. Never touches the unrelated lowercase 'gym'/
// 'rest'/'cardio'/'combined' type fields on plan.sessions[] entries or on
// sessions/{id} docs (logged workouts) — those are separate namespaces.
const VALID_PLAN_TYPES = ["Gym", "Cardio", "Combine"];

function requireValidPlanType(value, fieldName) {
  const normalized = requireNonEmptyAdminString(value, fieldName);

  if (!VALID_PLAN_TYPES.includes(normalized)) {
    throw new HttpsError(
        "invalid-argument",
        `${fieldName} must be one of: ${VALID_PLAN_TYPES.join(", ")}.`,
    );
  }

  return normalized;
}

function normalizeOfficialPlanData(rawData) {
  const data = rawData || {};

  const name = requireNonEmptyAdminString(data.name, "Plan name");
  const level = requireNonEmptyAdminString(data.level, "Level");
  const type = requireValidPlanType(data.type, "Type");

  const daysPerWeek = Number(data.daysPerWeek);
  const durationWeeks = Number(data.durationWeeks);

  if (!Number.isInteger(daysPerWeek) || daysPerWeek <= 0) {
    throw new HttpsError(
        "invalid-argument",
        "Days per week must be a positive integer.",
    );
  }

  if (!Number.isInteger(durationWeeks) || durationWeeks <= 0) {
    throw new HttpsError(
        "invalid-argument",
        "Duration must be a positive number of weeks.",
    );
  }

  const sessions = normalizeAdminPlanSessions(data.sessions);

  const actualTrainingDays =
    sessions.filter((session) => session.isRestDay !== true).length;

  if (actualTrainingDays !== daysPerWeek) {
    throw new HttpsError(
        "invalid-argument",
        `Days per week (${daysPerWeek}) must match the number of ` +
        `training sessions (${actualTrainingDays}).`,
    );
  }

  const normalized = {
    name,
    level,
    type,
    daysPerWeek,
    durationWeeks,
    description:
      typeof data.description === "string" ?
        data.description.trim() :
        "",
    equipment: normalizeAdminStringArray(data.equipment),
    goals: normalizeAdminStringArray(data.goals),
    sessions,
    isActive: data.isActive !== false,
    matchGoals: normalizeAdminStringArray(data.matchGoals),
    matchLevel:
      typeof data.matchLevel === "string" && data.matchLevel.trim() ?
        data.matchLevel.trim() :
        level,
    matchSport:
      typeof data.matchSport === "string" && data.matchSport.trim() ?
        data.matchSport.trim() :
        type,
    imageUrl:
      typeof data.imageUrl === "string" ?
        data.imageUrl.trim() :
        "",
    // Admin-only curation flag for a future "Featured Plans" admin UI —
    // defaults to false for every official plan, including brand-new ones
    // (adminCreateOfficialPlan below has no separate default to set; it
    // gets this for free by calling this same normalizer). Deliberately
    // absent from the custom-plan update path in adminUpdatePlan's
    // allowedFields — custom/coach plans can never set this field, by
    // omission from that allowlist rather than a runtime check here.
    featured: data.featured === true,
  };

  const designedBy = normalizeAdminDesignedBy(data.designedBy);

  if (designedBy) {
    normalized.designedBy = designedBy;
  }

  return normalized;
}

/**
 * Creates a new official WiseWorkout plan.
 *
 * Official plans deliberately omit isCustom and createdBy.
 */
exports.adminCreateOfficialPlan = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const planData = normalizeOfficialPlanData(
      request.data?.plan,
  );

  const planRef = await db.collection("plans").add({
    ...planData,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdByAdminUid: adminUid,
  });

  return {
    success: true,
    planId: planRef.id,
    plan: planData,
  };
});

/**
 * Updates either an official plan or a user-created custom plan.
 *
 * Custom-plan ownership and identity fields are never changed.
 */
exports.adminUpdatePlan = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const planId = request.data?.planId;
  const requestedChanges = request.data?.changes;

  if (typeof planId !== "string" || !planId.trim()) {
    throw new HttpsError(
        "invalid-argument",
        "Plan ID is required.",
    );
  }

  if (
    !requestedChanges ||
    typeof requestedChanges !== "object" ||
    Array.isArray(requestedChanges)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Plan changes are required.",
    );
  }

  const normalizedPlanId = planId.trim();
  const planRef = db.collection("plans").doc(normalizedPlanId);
  const planSnapshot = await planRef.get();

  if (!planSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Plan not found.",
    );
  }

  const existing = planSnapshot.data() || {};
  const isCustom = existing.isCustom === true;

  let updateData;

  if (isCustom) {
    const allowedFields = new Set([
      "name",
      "description",
      "daysPerWeek",
      "sessions",
    ]);

    const unsafeField = Object.keys(requestedChanges)
        .find((field) => !allowedFields.has(field));

    if (unsafeField) {
      throw new HttpsError(
          "invalid-argument",
          `Custom-plan field "${unsafeField}" cannot be changed.`,
      );
    }

    const mergedName =
      requestedChanges.name !== undefined ?
        requestedChanges.name :
        existing.name;

    const mergedDays =
      requestedChanges.daysPerWeek !== undefined ?
        Number(requestedChanges.daysPerWeek) :
        Number(existing.daysPerWeek);

    const mergedSessions =
      requestedChanges.sessions !== undefined ?
        requestedChanges.sessions :
        existing.sessions;

    const name = requireNonEmptyAdminString(
        mergedName,
        "Plan name",
    );

    if (!Number.isInteger(mergedDays) || mergedDays <= 0) {
      throw new HttpsError(
          "invalid-argument",
          "Days per week must be a positive integer.",
      );
    }

    const sessions = normalizeAdminPlanSessions(mergedSessions);

    updateData = {
      name,
      description:
        requestedChanges.description !== undefined ?
          String(requestedChanges.description || "").trim() :
          String(existing.description || "").trim(),
      daysPerWeek: mergedDays,
      sessions,
    };
  } else {
    const allowedFields = new Set([
      "name",
      "description",
      "level",
      "type",
      "daysPerWeek",
      "durationWeeks",
      "equipment",
      "goals",
      "sessions",
      "isActive",
      "matchGoals",
      "matchLevel",
      "matchSport",
      "imageUrl",
      "designedBy",
      "featured",
    ]);

    const unsafeField = Object.keys(requestedChanges)
        .find((field) => !allowedFields.has(field));

    if (unsafeField) {
      throw new HttpsError(
          "invalid-argument",
          `Official-plan field "${unsafeField}" cannot be changed.`,
      );
    }

    const merged = {};

    for (const field of allowedFields) {
      merged[field] =
        requestedChanges[field] !== undefined ?
          requestedChanges[field] :
          existing[field];
    }

    updateData = normalizeOfficialPlanData(merged);
  }

  await planRef.update({
    ...updateData,
    updatedAt: FieldValue.serverTimestamp(),
    updatedByAdminUid: adminUid,
  });

  return {
    success: true,
    planId: normalizedPlanId,
    plan: updateData,
  };
});

/**
 * Permanently deletes a plan.
 *
 * Custom-plan cleanup mirrors FirestoreService.deleteCustomPlan():
 * matching customRoutines documents and planProgress are also removed.
 */
exports.adminDeletePlan = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const planId = request.data?.planId;

  if (typeof planId !== "string" || !planId.trim()) {
    throw new HttpsError(
        "invalid-argument",
        "Plan ID is required.",
    );
  }

  const normalizedPlanId = planId.trim();
  const planRef = db.collection("plans").doc(normalizedPlanId);
  const planSnapshot = await planRef.get();

  if (!planSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Plan not found.",
    );
  }

  const plan = planSnapshot.data() || {};
  const isCustom = plan.isCustom === true;
  const creatorUid =
    typeof plan.createdBy === "string" ?
      plan.createdBy.trim() :
      "";

  const batch = db.batch();
  batch.delete(planRef);

  if (isCustom && creatorUid) {
    const routineSnapshot = await db
        .collection("users")
        .doc(creatorUid)
        .collection("customRoutines")
        .where("name", "==", plan.name || "")
        .get();

    for (const routineDoc of routineSnapshot.docs) {
      batch.delete(routineDoc.ref);
    }

    const progressRef = db
        .collection("users")
        .doc(creatorUid)
        .collection("planProgress")
        .doc(normalizedPlanId);

    batch.delete(progressRef);
  }

  await batch.commit();

  console.log(
      `adminDeletePlan: ${adminUid} deleted ${normalizedPlanId}`,
  );

  return {
    success: true,
    planId: normalizedPlanId,
    planType: isCustom ? "custom" : "official",
  };
});

/**
 * Returns broadcast history and the current number of possible recipients.
 */
exports.adminListBroadcastDashboard = onCall(async (request) => {
  await requireAdmin(request);

  const [broadcastsSnapshot, usersSnapshot] = await Promise.all([
    db.collection("adminBroadcasts").get(),
    db.collection("users").get(),
  ]);

  const broadcasts = broadcastsSnapshot.docs.map((broadcastDoc) => ({
    id: broadcastDoc.id,
    ...serializeAdminFirestoreValue(broadcastDoc.data()),
  }));

  broadcasts.sort((a, b) => {
    const dateA = a.createdAt ? new Date(a.createdAt).getTime() : 0;
    const dateB = b.createdAt ? new Date(b.createdAt).getTime() : 0;
    return dateB - dateA;
  });

  return {
    broadcasts,
    recipientCount: usersSnapshot.size,
  };
});

/**
 * Queues one broadcast for the existing sendAdminBroadcast Firestore trigger.
 *
 * The callable performs the privileged Admin SDK document creation. The
 * existing onDocumentCreated trigger performs the notification fan-out.
 */
exports.adminCreateBroadcast = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const rawMessage = request.data?.message;
  const confirmation = request.data?.confirmation;

  const message =
    typeof rawMessage === "string" ? rawMessage.trim() : "";

  if (!message) {
    throw new HttpsError(
        "invalid-argument",
        "Broadcast message is required.",
    );
  }

  if (message.length > 500) {
    throw new HttpsError(
        "invalid-argument",
        "Broadcast message cannot exceed 500 characters.",
    );
  }

  if (confirmation !== "SEND TO ALL USERS") {
    throw new HttpsError(
        "failed-precondition",
        "Broadcast confirmation text is incorrect.",
    );
  }

  const usersSnapshot = await db.collection("users").get();

  if (usersSnapshot.empty) {
    throw new HttpsError(
        "failed-precondition",
        "There are no users available to receive this broadcast.",
    );
  }

  const broadcastRef = await db.collection("adminBroadcasts").add({
    message,
    audience: "all",
    createdAt: FieldValue.serverTimestamp(),
    processed: false,
    createdByAdminUid: adminUid,
    recipientCount: usersSnapshot.size,
  });

  return {
    success: true,
    broadcastId: broadcastRef.id,
    recipientCount: usersSnapshot.size,
  };
});

/**
 * Returns all posts required by the React admin Posts dashboard.
 */
exports.adminListPostsDashboard = onCall(async (request) => {
  await requireAdmin(request);

  const postsSnapshot = await db.collection("posts").get();

  const posts = postsSnapshot.docs.map((postDoc) => ({
    id: postDoc.id,
    ...serializeAdminFirestoreValue(postDoc.data()),
  }));

  posts.sort((a, b) => {
    const dateA = a.createdAt ? new Date(a.createdAt).getTime() : 0;
    const dateB = b.createdAt ? new Date(b.createdAt).getTime() : 0;
    return dateB - dateA;
  });

  return {posts};
});

/**
 * Updates admin-editable post content.
 *
 * Ownership, image, reaction counts, comment counts and timestamps are
 * deliberately protected from arbitrary admin edits.
 */
exports.adminUpdatePost = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const postId =
    typeof request.data?.postId === "string" ?
      request.data.postId.trim() :
      "";

  const requestedChanges = request.data?.changes;

  if (!postId) {
    throw new HttpsError(
        "invalid-argument",
        "Post ID is required.",
    );
  }

  if (
    !requestedChanges ||
    typeof requestedChanges !== "object" ||
    Array.isArray(requestedChanges)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Post changes are required.",
    );
  }

  const postRef = db.collection("posts").doc(postId);
  const postSnapshot = await postRef.get();

  if (!postSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Post not found.",
    );
  }

  const allowedFields = new Set([
    "foodName",
    "caption",
    "calories",
    "proteinG",
    "carbsG",
    "fatG",
  ]);

  const unsafeField = Object.keys(requestedChanges)
      .find((field) => !allowedFields.has(field));

  if (unsafeField) {
    throw new HttpsError(
        "invalid-argument",
        `Post field "${unsafeField}" cannot be changed.`,
    );
  }

  const updateData = {};

  for (const field of ["foodName", "caption"]) {
    if (requestedChanges[field] !== undefined) {
      if (requestedChanges[field] === null) {
        updateData[field] = null;
      } else if (typeof requestedChanges[field] === "string") {
        updateData[field] = requestedChanges[field].trim();
      } else {
        throw new HttpsError(
            "invalid-argument",
            `${field} must be text.`,
        );
      }
    }
  }

  for (const field of ["calories", "proteinG", "carbsG", "fatG"]) {
    if (requestedChanges[field] === undefined) continue;

    if (requestedChanges[field] === null) {
      updateData[field] = null;
      continue;
    }

    const value = Number(requestedChanges[field]);

    if (!Number.isFinite(value) || value < 0) {
      throw new HttpsError(
          "invalid-argument",
          `${field} must be a valid non-negative number.`,
      );
    }

    updateData[field] = value;
  }

  if (Object.keys(updateData).length === 0) {
    throw new HttpsError(
        "invalid-argument",
        "No valid post changes were supplied.",
    );
  }

  await postRef.update({
    ...updateData,
    adminUpdatedAt: FieldValue.serverTimestamp(),
    updatedByAdminUid: adminUid,
  });

  return {
    success: true,
    postId,
    changes: updateData,
  };
});

/**
 * Hides or unhides one post.
 */
exports.adminSetPostHidden = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const postId =
    typeof request.data?.postId === "string" ?
      request.data.postId.trim() :
      "";

  const isHidden = request.data?.isHidden;

  if (!postId) {
    throw new HttpsError(
        "invalid-argument",
        "Post ID is required.",
    );
  }

  if (typeof isHidden !== "boolean") {
    throw new HttpsError(
        "invalid-argument",
        "isHidden must be true or false.",
    );
  }

  const postRef = db.collection("posts").doc(postId);
  const postSnapshot = await postRef.get();

  if (!postSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Post not found.",
    );
  }

  await postRef.update({
    isHidden,
    moderationUpdatedAt: FieldValue.serverTimestamp(),
    moderatedByAdminUid: adminUid,
  });

  return {
    success: true,
    postId,
    isHidden,
  };
});

/**
 * Permanently deletes a post and its reactions/comments subcollections.
 */
exports.adminDeletePost = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const postId =
    typeof request.data?.postId === "string" ?
      request.data.postId.trim() :
      "";

  const confirmation = request.data?.confirmation;

  if (!postId) {
    throw new HttpsError(
        "invalid-argument",
        "Post ID is required.",
    );
  }

  if (confirmation !== "DELETE POST") {
    throw new HttpsError(
        "failed-precondition",
        "Post deletion confirmation is incorrect.",
    );
  }

  const postRef = db.collection("posts").doc(postId);
  const postSnapshot = await postRef.get();

  if (!postSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Post not found.",
    );
  }

  await db.recursiveDelete(postRef);

  console.log(
      `adminDeletePost: ${adminUid} permanently deleted ${postId}`,
  );

  return {
    success: true,
    postId,
  };
});

function normalizeInjuryCategoryInput(rawData) {
  const data =
    rawData && typeof rawData === "object" && !Array.isArray(rawData) ?
      rawData :
      {};

  const name =
    typeof data.name === "string" ?
      data.name.trim() :
      "";

  const bodyPart =
    typeof data.bodyPart === "string" ?
      data.bodyPart.trim() :
      "";

  const description =
    typeof data.description === "string" ?
      data.description.trim() :
      "";

  if (!name) {
    throw new HttpsError(
        "invalid-argument",
        "Injury category name is required.",
    );
  }

  if (!bodyPart) {
    throw new HttpsError(
        "invalid-argument",
        "Body part is required.",
    );
  }

  if (!description) {
    throw new HttpsError(
        "invalid-argument",
        "Description is required.",
    );
  }

  if (name.length > 100) {
    throw new HttpsError(
        "invalid-argument",
        "Injury category name cannot exceed 100 characters.",
    );
  }

  if (bodyPart.length > 100) {
    throw new HttpsError(
        "invalid-argument",
        "Body part cannot exceed 100 characters.",
    );
  }

  if (description.length > 500) {
    throw new HttpsError(
        "invalid-argument",
        "Description cannot exceed 500 characters.",
    );
  }

  return {
    name,
    bodyPart,
    description,
  };
}

async function ensureUniqueInjuryCategoryName(
    name,
    excludedCategoryId = null,
) {
  const snapshot = await db.collection("injuryCategories").get();
  const normalizedName = name.trim().toLowerCase();

  const duplicate = snapshot.docs.find((categoryDoc) => {
    if (excludedCategoryId && categoryDoc.id === excludedCategoryId) {
      return false;
    }

    const existingName = categoryDoc.data()?.name;

    return (
      typeof existingName === "string" &&
      existingName.trim().toLowerCase() === normalizedName
    );
  });

  if (duplicate) {
    throw new HttpsError(
        "already-exists",
        `An injury category named "${name}" already exists.`,
    );
  }
}

function exerciseUsesInjuryName(exerciseData, injuryName) {
  const injuryRisks = exerciseData?.injuryRisk;

  if (!Array.isArray(injuryRisks)) return false;

  const normalizedName = injuryName.trim().toLowerCase();

  return injuryRisks.some((risk) =>
    typeof risk === "string" &&
    risk.trim().toLowerCase() === normalizedName
  );
}

/**
 * Returns the injury categories and the limited exercise data required
 * by the React Injuries dashboard.
 */
exports.adminListInjuriesDashboard = onCall(async (request) => {
  await requireAdmin(request);

  const [injuriesSnapshot, exercisesSnapshot] = await Promise.all([
    db.collection("injuryCategories").get(),
    db.collection("exercises").get(),
  ]);

  const injuries = injuriesSnapshot.docs.map((categoryDoc) => ({
    id: categoryDoc.id,
    ...serializeAdminFirestoreValue(categoryDoc.data()),
  }));

  injuries.sort((a, b) =>
    String(a.name || "").localeCompare(String(b.name || ""))
  );

  const exercises = exercisesSnapshot.docs.map((exerciseDoc) => {
    const data = exerciseDoc.data();

    return {
      id: exerciseDoc.id,
      name:
        typeof data.name === "string" ?
          data.name :
          "",
      injuryRisk:
        Array.isArray(data.injuryRisk) ?
          data.injuryRisk :
          [],
    };
  });

  return {
    injuries,
    exercises,
  };
});

/**
 * Creates one admin-managed injury category.
 */
exports.adminCreateInjuryCategory = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const category = normalizeInjuryCategoryInput(
      request.data?.category,
  );

  await ensureUniqueInjuryCategoryName(category.name);

  const categoryRef = await db.collection("injuryCategories").add({
    ...category,
    createdAt: FieldValue.serverTimestamp(),
    createdByAdminUid: adminUid,
  });

  return {
    success: true,
    categoryId: categoryRef.id,
    category,
  };
});

/**
 * Updates one admin-managed injury category.
 *
 * Renaming is blocked while exercises still reference the previous name,
 * because exercise.injuryRisk stores category names rather than document IDs.
 */
exports.adminUpdateInjuryCategory = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const categoryId =
    typeof request.data?.categoryId === "string" ?
      request.data.categoryId.trim() :
      "";

  const requestedChanges = request.data?.changes;

  if (!categoryId) {
    throw new HttpsError(
        "invalid-argument",
        "Injury category ID is required.",
    );
  }

  if (
    !requestedChanges ||
    typeof requestedChanges !== "object" ||
    Array.isArray(requestedChanges)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Injury category changes are required.",
    );
  }

  const allowedFields = new Set([
    "name",
    "bodyPart",
    "description",
  ]);

  const unsafeField = Object.keys(requestedChanges)
      .find((field) => !allowedFields.has(field));

  if (unsafeField) {
    throw new HttpsError(
        "invalid-argument",
        `Injury category field "${unsafeField}" cannot be changed.`,
    );
  }

  const categoryRef =
    db.collection("injuryCategories").doc(categoryId);

  const categorySnapshot = await categoryRef.get();

  if (!categorySnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Injury category not found.",
    );
  }

  const existing = categorySnapshot.data() || {};

  const mergedCategory = normalizeInjuryCategoryInput({
    name:
      requestedChanges.name !== undefined ?
        requestedChanges.name :
        existing.name,
    bodyPart:
      requestedChanges.bodyPart !== undefined ?
        requestedChanges.bodyPart :
        existing.bodyPart,
    description:
      requestedChanges.description !== undefined ?
        requestedChanges.description :
        existing.description,
  });

  const oldName =
    typeof existing.name === "string" ?
      existing.name.trim() :
      "";

  const nameChanged =
    mergedCategory.name.toLowerCase() !== oldName.toLowerCase();

  if (nameChanged) {
    await ensureUniqueInjuryCategoryName(
        mergedCategory.name,
        categoryId,
    );

    const exercisesSnapshot =
      await db.collection("exercises").get();

    const usageCount = exercisesSnapshot.docs.filter((exerciseDoc) =>
      exerciseUsesInjuryName(exerciseDoc.data(), oldName)
    ).length;

    if (usageCount > 0) {
      throw new HttpsError(
          "failed-precondition",
          `"${oldName}" is used by ${usageCount} exercise` +
          `${usageCount === 1 ? "" : "s"}. Update those exercises ` +
          "before renaming this category.",
      );
    }
  }

  await categoryRef.update({
    ...mergedCategory,
    updatedAt: FieldValue.serverTimestamp(),
    updatedByAdminUid: adminUid,
  });

  return {
    success: true,
    categoryId,
    category: mergedCategory,
  };
});

/**
 * Deletes one injury category only when no exercise still references it.
 */
exports.adminDeleteInjuryCategory = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const categoryId =
    typeof request.data?.categoryId === "string" ?
      request.data.categoryId.trim() :
      "";

  const confirmation = request.data?.confirmation;

  if (!categoryId) {
    throw new HttpsError(
        "invalid-argument",
        "Injury category ID is required.",
    );
  }

  if (confirmation !== "DELETE INJURY") {
    throw new HttpsError(
        "failed-precondition",
        "Injury category deletion confirmation is incorrect.",
    );
  }

  const categoryRef =
    db.collection("injuryCategories").doc(categoryId);

  const categorySnapshot = await categoryRef.get();

  if (!categorySnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Injury category not found.",
    );
  }

  const category = categorySnapshot.data() || {};
  const injuryName =
    typeof category.name === "string" ?
      category.name.trim() :
      "";

  const exercisesSnapshot =
    await db.collection("exercises").get();

  const referencingExercises = exercisesSnapshot.docs
      .filter((exerciseDoc) =>
        exerciseUsesInjuryName(exerciseDoc.data(), injuryName)
      )
      .map((exerciseDoc) => ({
        id: exerciseDoc.id,
        name: exerciseDoc.data()?.name || exerciseDoc.id,
      }));

  if (referencingExercises.length > 0) {
    throw new HttpsError(
        "failed-precondition",
        `"${injuryName}" is still used by ` +
        `${referencingExercises.length} exercise` +
        `${referencingExercises.length === 1 ? "" : "s"}. ` +
        "Remove the injury risk from those exercises first.",
    );
  }

  await categoryRef.delete();

  console.log(
      `adminDeleteInjuryCategory: ${adminUid} deleted ${categoryId}`,
  );

  return {
    success: true,
    categoryId,
  };
});

const ADMIN_BADGE_STAT_TYPES = [
  "level",
  "totalXp",
  "sessionCount",
  "totalVolume",
  "totalDistance",
  "streak",
  "gymSessionCount",
  "cardioSessionCount",
  "combinedSessionCount",
];

function normalizeAdminBadgeConditions(rawConditions) {
  if (!Array.isArray(rawConditions) || rawConditions.length === 0) {
    throw new HttpsError(
        "invalid-argument",
        "At least one badge condition is required.",
    );
  }

  const seenStatTypes = new Set();

  return rawConditions.map((rawCondition, index) => {
    const condition =
      rawCondition &&
      typeof rawCondition === "object" &&
      !Array.isArray(rawCondition) ?
        rawCondition :
        {};

    const statType =
      typeof condition.statType === "string" ?
        condition.statType.trim() :
        "";

    if (!ADMIN_BADGE_STAT_TYPES.includes(statType)) {
      throw new HttpsError(
          "invalid-argument",
          `Condition ${index + 1} has an unsupported stat type.`,
      );
    }

    if (seenStatTypes.has(statType)) {
      throw new HttpsError(
          "invalid-argument",
          `The stat type "${statType}" is used more than once.`,
      );
    }

    seenStatTypes.add(statType);

    const value = Number(condition.value);

    if (!Number.isFinite(value) || value < 0) {
      throw new HttpsError(
          "invalid-argument",
          `Condition ${index + 1} requires a valid non-negative value.`,
      );
    }

    return {
      statType,
      value,
    };
  });
}

function normalizeAdminBadgeInput(rawData) {
  const data =
    rawData &&
    typeof rawData === "object" &&
    !Array.isArray(rawData) ?
      rawData :
      {};

  const name =
    typeof data.name === "string" ?
      data.name.trim() :
      "";

  const description =
    typeof data.description === "string" ?
      data.description.trim() :
      "";

  const imageUrl =
    typeof data.imageUrl === "string" ?
      data.imageUrl.trim() :
      "";

  if (!name) {
    throw new HttpsError(
        "invalid-argument",
        "Badge name is required.",
    );
  }

  if (!description) {
    throw new HttpsError(
        "invalid-argument",
        "Badge description is required.",
    );
  }

  if (name.length > 100) {
    throw new HttpsError(
        "invalid-argument",
        "Badge name cannot exceed 100 characters.",
    );
  }

  if (description.length > 500) {
    throw new HttpsError(
        "invalid-argument",
        "Badge description cannot exceed 500 characters.",
    );
  }

  if (
    imageUrl &&
    !/^https?:\/\//i.test(imageUrl)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Badge image URL must begin with http:// or https://.",
    );
  }

  return {
    name,
    description,
    imageUrl,
    conditions: normalizeAdminBadgeConditions(data.conditions),
  };
}

async function ensureUniqueAdminBadgeName(
    badgeName,
    excludedBadgeId = null,
) {
  const badgesSnapshot = await db.collection("badges").get();
  const normalizedName = badgeName.trim().toLowerCase();

  const duplicate = badgesSnapshot.docs.find((badgeDoc) => {
    if (excludedBadgeId && badgeDoc.id === excludedBadgeId) {
      return false;
    }

    const existingName = badgeDoc.data()?.name;

    return (
      typeof existingName === "string" &&
      existingName.trim().toLowerCase() === normalizedName
    );
  });

  if (duplicate) {
    throw new HttpsError(
        "already-exists",
        `A badge named "${badgeName}" already exists.`,
    );
  }
}

/**
 * Returns all badge definitions for the React admin dashboard.
 */
exports.adminListBadgesDashboard = onCall(async (request) => {
  await requireAdmin(request);

  const badgesSnapshot = await db.collection("badges").get();

  const badges = badgesSnapshot.docs.map((badgeDoc) => ({
    id: badgeDoc.id,
    ...serializeAdminFirestoreValue(badgeDoc.data()),
  }));

  badges.sort((a, b) =>
    String(a.name || "").localeCompare(String(b.name || ""))
  );

  return {
    badges,
    supportedStatTypes: ADMIN_BADGE_STAT_TYPES,
  };
});

/**
 * Creates one admin-managed badge definition.
 */
exports.adminCreateBadge = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const badge = normalizeAdminBadgeInput(
      request.data?.badge,
  );

  await ensureUniqueAdminBadgeName(badge.name);

  const badgeRef = await db.collection("badges").add({
    ...badge,
    createdAt: FieldValue.serverTimestamp(),
    createdByAdminUid: adminUid,
  });

  return {
    success: true,
    badgeId: badgeRef.id,
    badge,
  };
});

/**
 * Updates one badge definition.
 *
 * Users who already earned the badge keep it. Edited conditions only affect
 * users who have not earned the badge yet, matching the Flutter logic.
 */
exports.adminUpdateBadge = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const badgeId =
    typeof request.data?.badgeId === "string" ?
      request.data.badgeId.trim() :
      "";

  const requestedChanges = request.data?.changes;

  if (!badgeId) {
    throw new HttpsError(
        "invalid-argument",
        "Badge ID is required.",
    );
  }

  if (
    !requestedChanges ||
    typeof requestedChanges !== "object" ||
    Array.isArray(requestedChanges)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Badge changes are required.",
    );
  }

  const allowedFields = new Set([
    "name",
    "description",
    "imageUrl",
    "conditions",
  ]);

  const unsafeField = Object.keys(requestedChanges)
      .find((field) => !allowedFields.has(field));

  if (unsafeField) {
    throw new HttpsError(
        "invalid-argument",
        `Badge field "${unsafeField}" cannot be changed.`,
    );
  }

  const badgeRef = db.collection("badges").doc(badgeId);
  const badgeSnapshot = await badgeRef.get();

  if (!badgeSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Badge not found.",
    );
  }

  const existing = badgeSnapshot.data() || {};

  const mergedBadge = normalizeAdminBadgeInput({
    name:
      requestedChanges.name !== undefined ?
        requestedChanges.name :
        existing.name,
    description:
      requestedChanges.description !== undefined ?
        requestedChanges.description :
        existing.description,
    imageUrl:
      requestedChanges.imageUrl !== undefined ?
        requestedChanges.imageUrl :
        existing.imageUrl,
    conditions:
      requestedChanges.conditions !== undefined ?
        requestedChanges.conditions :
        existing.conditions,
  });

  await ensureUniqueAdminBadgeName(
      mergedBadge.name,
      badgeId,
  );

  await badgeRef.update({
    ...mergedBadge,
    updatedAt: FieldValue.serverTimestamp(),
    updatedByAdminUid: adminUid,
  });

  return {
    success: true,
    badgeId,
    badge: mergedBadge,
  };
});

/**
 * Deletes a badge only when no user has already earned it.
 *
 * Earned-badge documents use the badge ID as their document ID. Removing an
 * earned badge definition would make it disappear from the user's badge grid,
 * so deletion is blocked instead of silently breaking existing achievements.
 */
exports.adminDeleteBadge = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const badgeId =
    typeof request.data?.badgeId === "string" ?
      request.data.badgeId.trim() :
      "";

  const confirmation = request.data?.confirmation;

  if (!badgeId) {
    throw new HttpsError(
        "invalid-argument",
        "Badge ID is required.",
    );
  }

  if (confirmation !== "DELETE BADGE") {
    throw new HttpsError(
        "failed-precondition",
        "Badge deletion confirmation is incorrect.",
    );
  }

  const badgeRef = db.collection("badges").doc(badgeId);
  const badgeSnapshot = await badgeRef.get();

  if (!badgeSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Badge not found.",
    );
  }

  const usersSnapshot = await db.collection("users").get();

  const earnedChecks = await Promise.all(
      usersSnapshot.docs.map((userDoc) =>
        userDoc.ref
            .collection("earnedBadges")
            .doc(badgeId)
            .get(),
      ),
  );

  const earnedCount = earnedChecks.filter(
      (earnedDoc) => earnedDoc.exists,
  ).length;

  if (earnedCount > 0) {
    throw new HttpsError(
        "failed-precondition",
        `This badge has already been earned by ${earnedCount} user` +
        `${earnedCount === 1 ? "" : "s"} and cannot be deleted.`,
    );
  }

  await badgeRef.delete();

  console.log(
      `adminDeleteBadge: ${adminUid} deleted ${badgeId}`,
  );

  return {
    success: true,
    badgeId,
  };
});

const ADMIN_GAMIFICATION_UPDATE_PATHS = new Set([
  "cardioAntiCheat.indoor.accrualPauseDebounceTicks",
  "cardioAntiCheat.indoor.accrualResumeDebounceTicks",
  "cardioAntiCheat.indoor.stillnessVarianceThreshold",
  "cardioAntiCheat.indoor.stillnessWindowSeconds",

  "cardioAntiCheat.outdoor.accrualPauseDebounceTicks",
  "cardioAntiCheat.outdoor.accrualResumeDebounceTicks",
  "cardioAntiCheat.outdoor.defaultMaxSpeedKmh",
  "cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Cycle",
  "cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Run",
  "cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Walk",
  "cardioAntiCheat.outdoor.speedRollingWindowSeconds",
  "cardioAntiCheat.outdoor.stationaryThresholdMeters",
  "cardioAntiCheat.outdoor.stationaryWindowSeconds",

  "gymCalories.minCalories",
  "gymCalories.maxCalories",
  "gymCalories.setsCoefficient",
  "gymCalories.volumeCoefficient",

  "gymTiming.minSecondsPerRep",
  "gymTiming.minSetTransitionSeconds",

  "xp.cardioMinXp",
  "xp.cardioMaxXp",
  "xp.cardioPerCalorieRate",
  "xp.gymPerSet",

  "levelThresholds",
]);

const ADMIN_INTEGER_CONFIG_PATHS = new Set([
  "cardioAntiCheat.indoor.accrualPauseDebounceTicks",
  "cardioAntiCheat.indoor.accrualResumeDebounceTicks",
  "cardioAntiCheat.outdoor.accrualPauseDebounceTicks",
  "cardioAntiCheat.outdoor.accrualResumeDebounceTicks",
  "xp.gymPerSet",
]);

const ADMIN_POSITIVE_CONFIG_PATHS = new Set([
  "cardioAntiCheat.outdoor.defaultMaxSpeedKmh",
  "cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Cycle",
  "cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Run",
  "cardioAntiCheat.outdoor.maxSpeedKmhByActivity.Walk",
]);

function normalizeAdminSubscription(rawSubscription) {
  const data =
    rawSubscription &&
    typeof rawSubscription === "object" &&
    !Array.isArray(rawSubscription) ?
      rawSubscription :
      {};

  const freeTierAIMessages = Number(data.freeTierAIMessages);
  const premiumPrice = Number(data.premiumPrice);
  const premiumPriceAnnual = Number(data.premiumPriceAnnual);

  if (
    !Number.isInteger(freeTierAIMessages) ||
    freeTierAIMessages < 0
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Free-tier AI messages must be a non-negative whole number.",
    );
  }

  if (
    !Number.isFinite(premiumPrice) ||
    premiumPrice < 0
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Premium price must be a valid non-negative number.",
    );
  }

  if (
    !Number.isFinite(premiumPriceAnnual) ||
    premiumPriceAnnual < 0
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Annual premium price must be a valid non-negative number.",
    );
  }

  return {
    freeTierAIMessages,
    premiumPrice,
    premiumPriceAnnual,
  };
}

function normalizeAdminLevelThresholds(rawThresholds) {
  if (
    !Array.isArray(rawThresholds) ||
    rawThresholds.length === 0
  ) {
    throw new HttpsError(
        "invalid-argument",
        "At least one level threshold is required.",
    );
  }

  const thresholds = rawThresholds.map((rawValue, index) => {
    const value = Number(rawValue);

    if (
      !Number.isInteger(value) ||
      value < 0
    ) {
      throw new HttpsError(
          "invalid-argument",
          `Level ${index + 1} threshold must be a non-negative whole number.`,
      );
    }

    return value;
  });

  if (thresholds[0] !== 0) {
    throw new HttpsError(
        "invalid-argument",
        "Level 1 threshold must remain 0.",
    );
  }

  for (let index = 1; index < thresholds.length; index++) {
    if (thresholds[index] <= thresholds[index - 1]) {
      throw new HttpsError(
          "invalid-argument",
          `Level ${index + 1} threshold must be greater than Level ${index}.`,
      );
    }
  }

  return thresholds;
}

function normalizeAdminGamificationUpdates(rawUpdates) {
  if (
    !rawUpdates ||
    typeof rawUpdates !== "object" ||
    Array.isArray(rawUpdates)
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Gamification updates must be an object.",
    );
  }

  const updateEntries = Object.entries(rawUpdates);

  const unsupportedPath = updateEntries.find(
      ([path]) => !ADMIN_GAMIFICATION_UPDATE_PATHS.has(path),
  );

  if (unsupportedPath) {
    throw new HttpsError(
        "invalid-argument",
        `Configuration field "${unsupportedPath[0]}" cannot be changed.`,
    );
  }

  const normalized = {};

  for (const [path, rawValue] of updateEntries) {
    if (path === "levelThresholds") {
      normalized[path] =
        normalizeAdminLevelThresholds(rawValue);
      continue;
    }

    const value = Number(rawValue);

    if (!Number.isFinite(value)) {
      throw new HttpsError(
          "invalid-argument",
          `Configuration field "${path}" must be a valid number.`,
      );
    }

    if (
      ADMIN_INTEGER_CONFIG_PATHS.has(path) &&
      (!Number.isInteger(value) || value < 0)
    ) {
      throw new HttpsError(
          "invalid-argument",
          `Configuration field "${path}" must be a non-negative whole number.`,
      );
    }

    if (
      ADMIN_POSITIVE_CONFIG_PATHS.has(path) &&
      value <= 0
    ) {
      throw new HttpsError(
          "invalid-argument",
          `Configuration field "${path}" must be greater than 0.`,
      );
    }

    if (
      !ADMIN_POSITIVE_CONFIG_PATHS.has(path) &&
      !ADMIN_INTEGER_CONFIG_PATHS.has(path) &&
      value < 0
    ) {
      throw new HttpsError(
          "invalid-argument",
          `Configuration field "${path}" cannot be negative.`,
      );
    }

    normalized[path] = value;
  }

  if (
    normalized["gymCalories.minCalories"] !== undefined ||
    normalized["gymCalories.maxCalories"] !== undefined
  ) {
    // The final relationship is also checked again against the stored
    // document inside adminUpdateSettings.
  }

  return normalized;
}

/**
 * Returns the system configuration used by the Settings dashboard.
 */
exports.adminGetSettingsDashboard = onCall(async (request) => {
  await requireAdmin(request);

  const [gamificationSnapshot, subscriptionSnapshot] =
    await Promise.all([
      db.collection("appConfig")
          .doc("gamification")
          .get(),
      db.collection("adminSettings")
          .doc("global")
          .get(),
    ]);

  return {
    gamification: gamificationSnapshot.exists ?
      serializeAdminFirestoreValue(
          gamificationSnapshot.data(),
      ) :
      null,

    subscription: subscriptionSnapshot.exists ?
      serializeAdminFirestoreValue(
          subscriptionSnapshot.data(),
      ) :
      {
        freeTierAIMessages: 10,
        premiumPrice: 9.99,
        premiumPriceAnnual: 79.99,
      },
  };
});

/**
 * Securely updates the gamification configuration and subscription settings.
 *
 * Only the explicitly supported paths used by Settings.js may be changed.
 */
exports.adminUpdateSettings = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const subscription =
    normalizeAdminSubscription(
        request.data?.subscription,
    );

  const gamificationUpdates =
    normalizeAdminGamificationUpdates(
        request.data?.gamificationUpdates || {},
    );

  const gamificationRef =
    db.collection("appConfig").doc("gamification");

  const gamificationSnapshot =
    await gamificationRef.get();

  if (!gamificationSnapshot.exists) {
    throw new HttpsError(
        "failed-precondition",
        "The gamification configuration document does not exist.",
    );
  }

  const existing = gamificationSnapshot.data() || {};

  const currentMinimumCalories =
    Number(existing.gymCalories?.minCalories);

  const currentMaximumCalories =
    Number(existing.gymCalories?.maxCalories);

  const nextMinimumCalories =
    gamificationUpdates["gymCalories.minCalories"] ??
    currentMinimumCalories;

  const nextMaximumCalories =
    gamificationUpdates["gymCalories.maxCalories"] ??
    currentMaximumCalories;

  if (
    Number.isFinite(nextMinimumCalories) &&
    Number.isFinite(nextMaximumCalories) &&
    nextMaximumCalories < nextMinimumCalories
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Maximum gym calories must be greater than or equal to minimum gym calories.",
    );
  }

  const currentMinimumXp =
    Number(existing.xp?.cardioMinXp);

  const currentMaximumXp =
    Number(existing.xp?.cardioMaxXp);

  const nextMinimumXp =
    gamificationUpdates["xp.cardioMinXp"] ??
    currentMinimumXp;

  const nextMaximumXp =
    gamificationUpdates["xp.cardioMaxXp"] ??
    currentMaximumXp;

  if (
    Number.isFinite(nextMinimumXp) &&
    Number.isFinite(nextMaximumXp) &&
    nextMaximumXp < nextMinimumXp
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Maximum cardio XP must be greater than or equal to minimum cardio XP.",
    );
  }

  const batch = db.batch();

  const subscriptionRef =
    db.collection("adminSettings").doc("global");

  batch.set(
      subscriptionRef,
      {
        ...subscription,
        updatedAt: FieldValue.serverTimestamp(),
        updatedByAdminUid: adminUid,
      },
      {merge: true},
  );

  if (Object.keys(gamificationUpdates).length > 0) {
    batch.update(
        gamificationRef,
        {
          ...gamificationUpdates,
          updatedAt: FieldValue.serverTimestamp(),
          updatedByAdminUid: adminUid,
        },
    );
  }

  await batch.commit();

  return {
    success: true,
    subscription,
    gamificationUpdates,
  };
});

function adminAnalyticsAverage(items, fieldName) {
  const values = items
      .map((item) => Number(item?.[fieldName]))
      .filter((value) => Number.isFinite(value));

  if (values.length === 0) return null;

  const total = values.reduce(
      (sum, value) => sum + value,
      0,
  );

  return Math.round((total / values.length) * 10) / 10;
}

function isAdminAnalyticsMealPost(post) {
  const postType =
    typeof post?.type === "string" ?
      post.type.trim().toLowerCase() :
      "";

  if (postType === "meal") return true;

  const hasFoodName =
    typeof post?.foodName === "string" &&
    post.foodName.trim().length > 0;

  const hasNutrition =
    ["proteinG", "carbsG", "fatG"].some(
        (field) => Number.isFinite(Number(post?.[field])),
    );

  return hasFoodName && hasNutrition;
}

function normalizeAdminPartnerStatus(partner) {
  const rawStatus =
    typeof partner?.status === "string" ?
      partner.status.trim().toLowerCase() :
      "";

  if (
    rawStatus === "approved" ||
    partner?.isApproved === true
  ) {
    return "approved";
  }

  if (
    rawStatus === "rejected" ||
    partner?.isRejected === true
  ) {
    return "rejected";
  }

  return "pending";
}

/**
 * Returns aggregated platform analytics to the React admin dashboard.
 *
 * Raw user and platform documents remain on the server. The browser receives
 * only the counts, distributions and recent-activity fields needed by the UI.
 */
exports.adminGetAnalyticsDashboard = onCall(async (request) => {
  await requireAdmin(request);

  const [
    usersSnapshot,
    plansSnapshot,
    exercisesSnapshot,
    partnersSnapshot,
    challengesSnapshot,
    postsSnapshot,
  ] = await Promise.all([
    db.collection("users").get(),
    db.collection("plans").get(),
    db.collection("exercises").get(),
    db.collection("businessPartners").get(),
    db.collection("challenges").get(),
    db.collection("posts").get(),
  ]);

  const users = usersSnapshot.docs.map(
      (document) => document.data(),
  );

  const exercises = exercisesSnapshot.docs.map(
      (document) => document.data(),
  );

  const challenges = challengesSnapshot.docs.map(
      (document) => document.data(),
  );

  const posts = postsSnapshot.docs.map(
      (document) => document.data(),
  );

  const partners = partnersSnapshot.docs.map(
      (document) => document.data(),
  );

  const levelCounts = {};

  for (const user of users) {
    const rawLevel = Number(user?.level);
    const level =
      Number.isInteger(rawLevel) && rawLevel > 0 ?
        rawLevel :
        1;

    levelCounts[level] = (levelCounts[level] || 0) + 1;
  }

  const levelDistribution = Object.keys(levelCounts)
      .map(Number)
      .sort((a, b) => a - b)
      .map((level) => ({
        label: `Lvl ${level}`,
        value: levelCounts[level],
      }));

  const difficultyCounts = {
    Beginner: 0,
    Intermediate: 0,
    Advanced: 0,
  };

  for (const exercise of exercises) {
    const difficulty =
      typeof exercise?.difficulty === "string" &&
      exercise.difficulty.trim() ?
        exercise.difficulty.trim() :
        "Beginner";

    difficultyCounts[difficulty] =
      (difficultyCounts[difficulty] || 0) + 1;
  }

  const challengeTypeCounts = {
    Global: 0,
    Private: 0,
  };

  for (const challenge of challenges) {
    if (challenge?.isGlobal === true) {
      challengeTypeCounts.Global += 1;
    } else {
      challengeTypeCounts.Private += 1;
    }
  }

  const mealPosts = posts.filter(
      isAdminAnalyticsMealPost,
  );

  const totalReactions = posts.reduce(
      (sum, post) =>
        sum + (Number(post?.reactionCount) || 0),
      0,
  );

  const totalComments = posts.reduce(
      (sum, post) =>
        sum + (Number(post?.commentCount) || 0),
      0,
  );

  const partnerStatuses = partners.map(
      normalizeAdminPartnerStatus,
  );

  const recentActivity = [];

  for (const postDocument of postsSnapshot.docs) {
    const post = postDocument.data();

    if (!post?.createdAt) continue;

    recentActivity.push({
      createdAt:
        serializeAdminFirestoreValue(post.createdAt),
      icon: "📝",
      text:
        `${post.authorName || "A user"} posted` +
        `${post.foodName ? ` "${post.foodName}"` : ""}`,
    });
  }

  for (const planDocument of plansSnapshot.docs) {
    const plan = planDocument.data();

    if (!plan?.createdAt) continue;

    recentActivity.push({
      createdAt:
        serializeAdminFirestoreValue(plan.createdAt),
      icon: "📋",
      text:
        `New plan created: ` +
        `"${plan.name || "Untitled plan"}"`,
    });
  }

  for (const partnerDocument of partnersSnapshot.docs) {
    const partner = partnerDocument.data();

    if (!partner?.createdAt) continue;

    recentActivity.push({
      createdAt:
        serializeAdminFirestoreValue(
            partner.createdAt,
        ),
      icon: "🤝",
      text:
        "New business partner application: " +
        (
          partner.displayName ||
          partner.businessName ||
          partner.email ||
          "Unknown"
        ),
    });
  }

  recentActivity.sort((first, second) => {
    const firstDate = new Date(first.createdAt);
    const secondDate = new Date(second.createdAt);

    return secondDate.getTime() - firstDate.getTime();
  });

  return {
    stats: {
      totalUsers: usersSnapshot.size,
      totalPlans: plansSnapshot.size,
      totalExercises: exercisesSnapshot.size,
      totalBP: partnersSnapshot.size,
      totalChallenges: challengesSnapshot.size,

      approvedBP: partnerStatuses.filter(
          (status) => status === "approved",
      ).length,

      pendingBP: partnerStatuses.filter(
          (status) => status === "pending",
      ).length,

      healthConnected: users.filter(
          (user) => user?.healthConnected === true,
      ).length,

      onboarded: users.filter(
          (user) => user?.onboardingComplete === true,
      ).length,

      suspended: users.filter(
          (user) =>
            user?.accountStatus === "suspended",
      ).length,

      premiumUsers: users.filter(
          (user) => user?.isPremium === true,
      ).length,

      levelDistribution,
      difficultyCounts,
      challengeTypeCounts,

      totalPosts: postsSnapshot.size,
      totalMealPosts: mealPosts.length,
      totalReactions,
      totalComments,

      avgCalories:
        adminAnalyticsAverage(mealPosts, "calories"),

      avgProtein:
        adminAnalyticsAverage(mealPosts, "proteinG"),

      avgCarbs:
        adminAnalyticsAverage(mealPosts, "carbsG"),

      avgFat:
        adminAnalyticsAverage(mealPosts, "fatG"),

      recentActivity: recentActivity.slice(0, 8),
    },
  };
});

function normalizeBusinessPartnerAdminStatus(partner) {
  if (partner?.isApproved === true) {
    return "approved";
  }

  return "pending";
}

/**
 * Returns all coach applications for the React admin dashboard.
 */
exports.adminListBusinessPartners = onCall(async (request) => {
  await requireAdmin(request);

  const partnersSnapshot =
    await db.collection("businessPartners").get();

  const partners = partnersSnapshot.docs.map((partnerDocument) => {
    const data = partnerDocument.data() || {};

    return {
      id: partnerDocument.id,
      ...serializeAdminFirestoreValue(data),
      status: normalizeBusinessPartnerAdminStatus(data),
    };
  });

  partners.sort((first, second) => {
    const firstDate = new Date(first.createdAt || 0);
    const secondDate = new Date(second.createdAt || 0);

    return secondDate.getTime() - firstDate.getTime();
  });

  return {
    partners,
  };
});

/**
 * Approves one coach application and makes it visible in the Flutter
 * professional directory.
 */
exports.adminApproveBusinessPartner = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const partnerUid =
    typeof request.data?.partnerUid === "string" ?
      request.data.partnerUid.trim() :
      "";

  const confirmation = request.data?.confirmation;

  if (!partnerUid) {
    throw new HttpsError(
        "invalid-argument",
        "Business partner UID is required.",
    );
  }

  if (confirmation !== "APPROVE PARTNER") {
    throw new HttpsError(
        "failed-precondition",
        "Approval confirmation is incorrect.",
    );
  }

  const partnerRef =
    db.collection("businessPartners").doc(partnerUid);

  const partnerSnapshot = await partnerRef.get();

  if (!partnerSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Business partner application not found.",
    );
  }

  const partner = partnerSnapshot.data() || {};

  const userRef =
    db.collection("users").doc(partnerUid);

  if (partner.isApproved === true && partner.isVisible === true) {
    await userRef.set(
        {
          isPremium: true,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    return {
      success: true,
      partnerUid,
      alreadyApproved: true,
      isPremium: true,
    };
  }

  const batch = db.batch();

  batch.update(partnerRef, {
    isApproved: true,
    isVisible: true,
    approvedAt: FieldValue.serverTimestamp(),
    approvedByAdminUid: adminUid,
    revocationReason: FieldValue.delete(),
    revokedAt: FieldValue.delete(),
    revokedByAdminUid: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  batch.set(
      userRef,
      {
        isPremium: true,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
  );

  await batch.commit();

  console.log(
      `adminApproveBusinessPartner: ${adminUid} approved ${partnerUid}`,
  );

  return {
    success: true,
    partnerUid,
    isApproved: true,
    isVisible: true,
    isPremium: true,
  };
});

/**
 * Revokes an approved coach and returns the application to the existing
 * pending state. Revocation is blocked while client relationships or
 * unresolved coach requests still exist.
 *
 * Current prototype entitlement model uses users/{uid}.isPremium as a
 * single boolean. Revoking BP approval therefore also removes Premium.
 * If paid Premium subscriptions are added later, entitlement source must
 * be tracked separately so BP revocation does not remove paid access.
 */
exports.adminRevokeBusinessPartner = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const partnerUid =
    typeof request.data?.partnerUid === "string" ?
      request.data.partnerUid.trim() :
      "";

  const confirmation = request.data?.confirmation;
  const reason =
  typeof request.data?.reason === "string"
    ? request.data.reason.trim()
    : "";

if (!reason) {
  throw new HttpsError(
      "invalid-argument",
      "A revocation reason is required.",
  );
}

if (reason.length > 500) {
  throw new HttpsError(
      "invalid-argument",
      "Revocation reason cannot exceed 500 characters.",
  );
}

  if (!partnerUid) {
    throw new HttpsError(
        "invalid-argument",
        "Business partner UID is required.",
    );
  }

  if (confirmation !== "REVOKE PARTNER") {
    throw new HttpsError(
        "failed-precondition",
        "Revocation confirmation is incorrect.",
    );
  }

  const partnerRef =
    db.collection("businessPartners").doc(partnerUid);

  const partnerSnapshot = await partnerRef.get();

  if (!partnerSnapshot.exists) {
    throw new HttpsError(
        "not-found",
        "Business partner application not found.",
    );
  }

  const [clientsSnapshot, requestsSnapshot] = await Promise.all([
    db.collection("coachClients")
        .where("coachUid", "==", partnerUid)
        .limit(1)
        .get(),

    db.collection("coachRequests")
        .where("coachUid", "==", partnerUid)
        .limit(1)
        .get(),
  ]);

  if (!clientsSnapshot.empty) {
    throw new HttpsError(
        "failed-precondition",
        "This coach still has active clients and cannot be revoked.",
    );
  }

  if (!requestsSnapshot.empty) {
    throw new HttpsError(
        "failed-precondition",
        "This coach still has pending client requests and cannot be revoked.",
    );
  }

   
  const userRef =
    db.collection("users").doc(partnerUid);

  const batch = db.batch();

  batch.update(partnerRef, {
    isApproved: false,
    isVisible: false,
    revocationReason: reason,
    revokedAt: FieldValue.serverTimestamp(),
    revokedByAdminUid: adminUid,
    updatedAt: FieldValue.serverTimestamp(),
  });

  batch.set(
      userRef,
      {
        isPremium: false,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
  );

  await batch.commit();

  console.log(
    `adminRevokeBusinessPartner: ${adminUid} revoked ${partnerUid}`,
);

return {
  success: true,
  partnerUid,
  isApproved: false,
  isVisible: false,
  isPremium: false,
  revocationReason: reason,
};
});

// Holds the OpenAI key as a Cloud Functions secret (v2 API) rather than a
// plaintext .env value — the previous approach in the Flutter app bundled
// .env as a Flutter asset (pubspec.yaml's flutter:assets:), which ships it
// inside every compiled APK/IPA. Set via `firebase functions:secrets:set
// OPENAI_API_KEY` (see deployment notes); never committed to source.
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

// Same secret-management pattern as OPENAI_API_KEY above, applied to the
// health-data encryption key used by getHealthData()/updateHealthData()
// below (and buildPersonalizationContext()'s decrypt of the same blob).
// A 32-byte key, hex-encoded (64 hex characters — see
// encryptHealthData()'s own length check), set via
// `firebase functions:secrets:set HEALTH_DATA_ENCRYPTION_KEY`. Never
// committed to source, never available to the Flutter client — only
// Cloud Functions holding this secret can decrypt users/{uid}
// .encryptedHealthData; the client can read/write that field's raw
// ciphertext directly via Firestore (harmless, see firestore.rules'
// unchanged users/{uid} rule) but can never make sense of it.
const HEALTH_DATA_ENCRYPTION_KEY = defineSecret("HEALTH_DATA_ENCRYPTION_KEY");

// The exact 11 fields bundled into users/{uid}.encryptedHealthData by
// this session's health-data-encryption migration (formerly plaintext
// fields directly on the user doc) — single source of truth for
// updateHealthData()'s field-name validation and the standalone
// migration script (functions/scripts/migrateHealthData.js), which keeps
// its own copy of this exact list in sync by hand since it runs outside
// this file's module (see that script's own header comment for why).
const HEALTH_DATA_FIELDS = [
  "injuries",
  "injuryFilteringEnabled",
  "dob",
  "biologicalSex",
  "heightCm",
  "weightKg",
  "goalWeight",
  "weightGoalActive",
  "dailyCalorieGoal",
  "weeklyCalorieGoal",
  "monthlyCalorieGoal",
  "calorieGoalActive",
];

/**
 * Encrypts `data` (any JSON-serializable object) into the
 * `iv.authTag.ciphertext` string format (all 3 parts base64, joined by
 * '.' — base64's alphabet never contains '.', so it's a safe, unambiguous
 * delimiter) stored verbatim in users/{uid}.encryptedHealthData.
 * AES-256-GCM via Node's built-in `crypto` module (no new dependency) —
 * an authenticated cipher, so decryptHealthData() below detects any
 * tampering with the stored ciphertext (GCM's auth-tag check throws
 * rather than silently returning garbage), not just keeping it unreadable.
 *
 * A fresh random 12-byte IV is generated per call — GCM requires a
 * never-reused nonce per (key, plaintext) encryption; reusing an IV with
 * the same key is a real cryptographic weakness, so this never accepts
 * or reuses a caller-supplied IV.
 *
 * @param {object} data
 * @return {string}
 */
function encryptHealthData(data) {
  const key = Buffer.from(HEALTH_DATA_ENCRYPTION_KEY.value(), "hex");
  if (key.length !== 32) {
    throw new HttpsError(
        "internal",
        "HEALTH_DATA_ENCRYPTION_KEY is misconfigured (expected a 32-byte " +
        "hex-encoded key — 64 hex characters).",
    );
  }
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(data), "utf8"),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag();
  return [iv, authTag, ciphertext]
      .map((buf) => buf.toString("base64"))
      .join(".");
}

/**
 * Reverses encryptHealthData(). Throws (HttpsError, "internal") if the
 * ciphertext is missing/malformed/tampered-with, rather than returning a
 * partial or garbage object — callers (getHealthData(),
 * updateHealthData(), buildPersonalizationContext()) each decide for
 * themselves whether that should propagate as a real error or be treated
 * as best-effort-empty, matching how every other best-effort category in
 * buildPersonalizationContext() already handles its own failures.
 *
 * @param {string} encrypted
 * @return {object}
 */
function decryptHealthData(encrypted) {
  const key = Buffer.from(HEALTH_DATA_ENCRYPTION_KEY.value(), "hex");
  if (key.length !== 32) {
    throw new HttpsError(
        "internal",
        "HEALTH_DATA_ENCRYPTION_KEY is misconfigured (expected a 32-byte " +
        "hex-encoded key — 64 hex characters).",
    );
  }
  const parts = (encrypted || "").split(".");
  if (parts.length !== 3) {
    throw new HttpsError("internal", "encryptedHealthData is malformed.");
  }
  const [ivB64, authTagB64, ciphertextB64] = parts;
  try {
    const iv = Buffer.from(ivB64, "base64");
    const authTag = Buffer.from(authTagB64, "base64");
    const ciphertext = Buffer.from(ciphertextB64, "base64");
    const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
    decipher.setAuthTag(authTag);
    const plaintext = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]).toString("utf8");
    return JSON.parse(plaintext);
  } catch (err) {
    console.error("decryptHealthData: decrypt/parse failed:", err);
    throw new HttpsError("internal", "Could not decrypt health data.");
  }
}

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

  // Body profile + injuries — both now come from the decrypted
  // encryptedHealthData blob (see decryptHealthData() above) rather than
  // plaintext fields directly on userData: this session's health-data-
  // encryption migration moved dob/biologicalSex/heightCm/weightKg/
  // injuries (and other HEALTH_DATA_FIELDS not used in this particular
  // context) off users/{uid} itself. Best-effort, matching every other
  // category in this function: a missing/malformed blob (brand-new user,
  // or one not yet run through the migration script) just means these
  // two categories are omitted, not a hard failure.
  let healthData = {};
  if (typeof userData.encryptedHealthData === "string" &&
      userData.encryptedHealthData !== "") {
    try {
      healthData = decryptHealthData(userData.encryptedHealthData);
    } catch (err) {
      console.error(
          `buildPersonalizationContext: health-data decrypt failed for ` +
          `uid ${uid}:`, err,
      );
    }
  }

  // Body profile — only fields that are actually present are included;
  // a missing/undefined field is omitted, never sent as a blank value.
  // experienceLevel/primaryGoal are NOT part of the encrypted blob (not
  // in HEALTH_DATA_FIELDS) — still read directly off userData, unchanged.
  const bodyParts = [];
  if (healthData.dob) bodyParts.push(`DOB ${healthData.dob}`);
  if (healthData.biologicalSex) bodyParts.push(healthData.biologicalSex);
  if (typeof healthData.heightCm === "number") {
    bodyParts.push(`${healthData.heightCm}cm`);
  }
  if (typeof healthData.weightKg === "number") {
    bodyParts.push(`${healthData.weightKg}kg`);
  }
  if (userData.experienceLevel) bodyParts.push(userData.experienceLevel);
  if (userData.primaryGoal) bodyParts.push(`goal: ${userData.primaryGoal}`);
  if (bodyParts.length > 0) {
    lines.push(`Body profile: ${bodyParts.join(", ")}.`);
  }

  // Injury profile — same shape/defaults as getUserInjuryData(): an
  // empty/missing injuries array means "omit this category" entirely.
  const injuries = Array.isArray(healthData.injuries) ? healthData.injuries : [];
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

// Free-tier WiseCoach chat message limit. Mirrors
// AppConstants.freeMessageLimit in lib/core/constants.dart — kept in sync
// by hand across the Dart/JS boundary, same convention already used for
// every other Dart-mirroring helper in this file (buildPersonalizationContext,
// computeSessionStats, etc.). If that constant ever changes, update this too.
const FREE_MESSAGE_LIMIT = 25;

/**
 * Counts uid's real (non-quick-reply) user-typed WiseCoach chat messages
 * so far this calendar month, for the free-tier message limit gate below.
 * No stored counter field — this is a pure [monthStart, monthEnd) range
 * query on `timestamp` only (no equality filter alongside it, so no
 * composite index is needed, unlike getSessionsPage()'s type+date shape),
 * same query shape as computeSessionStats()/getMonthlyStats() in
 * firestore_service.dart. The role=='user' && isQuickReply!=true filtering
 * happens in-memory over the fetched page — same "filter the already-
 * fetched set" convention findSimilarSessions() and computeAndNotify()
 * already use elsewhere in this file. Resets naturally every month purely
 * because the range being queried moves forward; no explicit reset logic
 * exists or is needed.
 *
 * @param {string} uid
 * @param {Date} now
 * @return {Promise<number>}
 */
async function countFreeWiseCoachMessagesThisMonth(uid, now) {
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const snapshot = await db
      .collection("users")
      .doc(uid)
      .collection("wiseCoachMessages")
      .where("timestamp", ">=", monthStart)
      .where("timestamp", "<", monthEnd)
      .get();

  let count = 0;
  snapshot.forEach((doc) => {
    const data = doc.data();
    if (data.role === "user" && data.isQuickReply !== true) count++;
  });
  return count;
}

/**
 * Drops any past assistant turn from `messages` that may have been
 * generated with injected personalization — `wasPersonalized !== false`,
 * so a message with the field missing entirely (either an old message
 * saved before this field existed, or the client omitting it) is treated
 * the same as `true`, the safer default per the "unknown means might have
 * been personalized" decision — together with its immediately preceding
 * user turn, since coach_screen.dart's _persistExchange() always writes
 * user-then-assistant as an adjacent pair, so dropping only the assistant
 * half would leave a dangling unanswered question in the replayed
 * history. `systemMessage` is always kept regardless (matched by
 * reference, already had any new context injection skipped by the
 * caller in this branch). Only ever changes what THIS request forwards
 * to OpenAI — never touches Firestore or the client's own display list.
 * @param {Array<{role: string, content: string, wasPersonalized?: boolean}>} messages
 * @param {object} systemMessage
 * @return {Array<{role: string, content: string}>}
 */
function filterUnpersonalizedHistory(messages, systemMessage) {
  const kept = [];
  for (const m of messages) {
    if (m === systemMessage) {
      kept.push(m);
      continue;
    }
    if (m.role === "assistant" && m.wasPersonalized !== false) {
      if (kept.length > 0 && kept[kept.length - 1].role === "user") {
        kept.pop();
      }
      continue;
    }
    kept.push(m);
  }
  return kept;
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
 * Free-tier message limit (later phase): same server-side-only reasoning
 * as the consent gate above — a client-side-only check could be bypassed
 * by calling this function directly, so the real gate lives here, using
 * the verified request.auth.uid, never a client-supplied flag. Applies
 * ONLY to the chat path (systemMessage present) — post-session summary has
 * no limit requirement and is intentionally untouched. Premium users
 * (users/{uid}.isPremium == true) are exempt entirely — no count query is
 * even run for them. For everyone else, countFreeWiseCoachMessagesThisMonth()
 * (see above) counts this calendar month's real (non-quick-reply) typed
 * messages already persisted to wiseCoachMessages by the client, and this
 * function rejects with 'resource-exhausted' at >= FREE_MESSAGE_LIMIT,
 * before ever calling OpenAI. Unlike the personalization/insights work
 * above (best-effort, swallowed on failure), this rejection is a real
 * HttpsError that must reach the client — the outer catch below re-throws
 * HttpsErrors instead of swallowing them, so this limit can't accidentally
 * be bypassed by wrapping it in the same best-effort try/catch.
 *
 * Also now declares HEALTH_DATA_ENCRYPTION_KEY alongside OPENAI_API_KEY:
 * required by Cloud Functions v2 whenever a function transitively uses a
 * secret via a helper it calls (here, buildPersonalizationContext() ->
 * decryptHealthData(), for the consent-gated chat path only) — the
 * secret must be declared on every onCall() that can reach it, not just
 * the module where the secret is defined.
 *
 * @param {{messages: {role: string, content: string, wasPersonalized?: boolean}[], maxTokens?: number, temperature?: number}} request.data
 * @return {Promise<{content: string, wasPersonalized: boolean}>} wasPersonalized
 *   is true only when THIS reply had personalization context injected (see
 *   filterUnpersonalizedHistory() above for how past personalized turns are
 *   kept out of later requests once consent is off).
 */
exports.callWiseCoachOpenAI = onCall(
    {secrets: [OPENAI_API_KEY, HEALTH_DATA_ENCRYPTION_KEY]},
    async (request) => {
      const data = request.data || {};
      let messages = data.messages;
      if (!Array.isArray(messages) || messages.length === 0) {
        throw new HttpsError(
            "invalid-argument",
            "messages must be a non-empty array of {role, content}.",
        );
      }

      const uid = request.auth && request.auth.uid;
      let wasPersonalizedThisTurn = false;
      if (uid) {
        try {
          const now = new Date();
          const systemMessage = messages.find((m) => m.role === "system");
          if (systemMessage) {
            // Chat — the free-tier message limit gate, then
            // personalization (including the 3 shared insights) only
            // when the user has explicitly consented. Both read the same
            // userDoc, fetched once.
            const userDoc = await db.collection("users").doc(uid).get();
            const userData = userDoc.exists ? userDoc.data() : {};

            if (userData.isPremium !== true) {
              const usedCount =
                  await countFreeWiseCoachMessagesThisMonth(uid, now);
              
              if (usedCount >= FREE_MESSAGE_LIMIT) {
                throw new HttpsError(
                    "resource-exhausted",
                    `You've used all ${FREE_MESSAGE_LIMIT} free messages ` +
                    "this month. Upgrade to WiseCoach Premium for " +
                    "unlimited access.",
                );
              }
            }

            if (userData.aiPersonalizationConsent === true) {
              const context = await buildPersonalizationContext(uid, userData, now);
              if (context) {
                systemMessage.content =
                    `${systemMessage.content}\n\nWhat you know about this ` +
                    "user (reference this naturally where relevant, don't " +
                    `recite it verbatim):\n${context}`;
                wasPersonalizedThisTurn = true;
              }
            } else {
              // Consent currently off — the gate above already stops any
              // NEW context from being injected this turn, but earlier
              // turns still sitting in `messages` (client-side chat
              // history, replayed on every request) may have been
              // generated while consent WAS on and can still contain
              // personal data the assistant wrote into its own reply.
              // Strip those out here rather than trusting the client to
              // have done so, for the same reason the consent gate itself
              // is server-side: a client-side-only filter could be
              // bypassed by calling this function directly.
              messages = filterUnpersonalizedHistory(messages, systemMessage);
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
          // Intentional rejections (the message-limit gate above) must
          // reach the client as a real error — only genuinely unexpected
          // failures (a Firestore read error, etc.) are swallowed here,
          // matching the "personalization is best-effort, never blocks
          // the reply" behavior this catch already had before the limit
          // gate was added.
          if (err instanceof HttpsError) {
            throw err;
          }
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

      // OpenAI only ever expects {role, content} — strips the
      // wasPersonalized metadata (used above only to decide what to
      // forward, never meaningful to the model itself) off every message
      // regardless of which branch ran.
      const outgoingMessages = messages.map((m) => ({
        role: m.role,
        content: m.content,
      }));

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
                messages: outgoingMessages,
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

      return {content, wasPersonalized: wasPersonalizedThisTurn};
    },
);

/**
 * analyzeNutrition — server-side relay to OpenAI's chat completions
 * endpoint for AI food recognition (lib/services/nutrition_service.dart's
 * analyzeFoodImage()/analyzeFoodDescription()), migrating this off the
 * client-bundled OPENAI_API_KEY the same way callWiseCoachOpenAI already
 * did for chat/post-session summary — this was the last remaining
 * consumer of that client-side key.
 *
 * A genuinely separate function rather than a variant of
 * callWiseCoachOpenAI: that function's dispatcher classifies every
 * request purely by system-message presence (chat vs post-session
 * summary — see its own doc comment), and nutrition's payload also
 * carries a system-role message (the nutrition-scanner persona/JSON-
 * schema-instructions prompt nutrition_service.dart already builds
 * client-side, unchanged by this migration). Reusing that dispatcher
 * would misclassify every nutrition call as chat, incorrectly subjecting
 * food scans to the WiseCoach free-tier message quota and attempting
 * (meaningless) personalization-context injection — neither applies to
 * this feature. So: no consent gate, no message-limit gate, no
 * personalization here at all — this is a pure, unconditional relay.
 *
 * Shares the same OPENAI_API_KEY secret as callWiseCoachOpenAI (defined
 * once, above) — no new secret to create or grant. Same model/params
 * nutrition_service.dart already hardcoded client-side before this
 * migration (gpt-4o-mini, max_tokens: 300, temperature: 0.3) — kept
 * fixed server-side rather than accepted from the client, since they
 * never varied per-call in the client code this replaces and there's no
 * reason to trust a client-supplied override for them.
 *
 * The client's messages array carries a system-role message (plain
 * string persona/schema prompt) and a user-role message whose content is
 * an array of {type: 'text'|'image_url', ...} blocks — OpenAI's
 * multimodal content-block shape, used for both food-photo scans
 * (text + image_url blocks) and text-only descriptions (text block
 * only). This function does no validation of that internal shape beyond
 * confirming messages is a non-empty array (same minimal validation
 * callWiseCoachOpenAI does) and forwards it to OpenAI unchanged — JSON-
 * schema parsing of the food/calorie/macro response stays entirely
 * client-side in nutrition_service.dart's _parse(), exactly as before
 * this migration; this function only relays the raw {content} string
 * back, same shape callWiseCoachOpenAI already returns.
 *
 * @param {{messages: {role: string, content: string|object[]}[]}} request.data
 * @return {Promise<{content: string}>}
 */
exports.analyzeNutrition = onCall(
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
                max_tokens: 300,
                temperature: 0.3,
              }),
            },
        );
      } catch (err) {
        console.error("analyzeNutrition: fetch to OpenAI failed:", err);
        throw new HttpsError("unavailable", "Could not reach OpenAI.");
      }

      if (!response.ok) {
        const errText = await response.text();
        console.error(
            `analyzeNutrition: OpenAI error ${response.status}: ${errText}`,
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
            "analyzeNutrition: unexpected OpenAI response shape:",
            JSON.stringify(json),
        );
        throw new HttpsError("internal", "Unexpected OpenAI response shape.");
      }

      return {content};
    },
);

/**
 * getHealthData — decrypts and returns the authenticated caller's own
 * bundled health-data blob (users/{uid}.encryptedHealthData — see
 * HEALTH_DATA_FIELDS above for the exact 11 fields: injuries, dob,
 * biologicalSex, heightCm, weightKg, goalWeight, weightGoalActive,
 * dailyCalorieGoal, weeklyCalorieGoal, monthlyCalorieGoal,
 * calorieGoalActive). Mirrors the OPENAI_API_KEY secret pattern already
 * established for callWiseCoachOpenAI/analyzeNutrition: the encryption
 * key lives only in Secret Manager, only Cloud Functions can decrypt, the
 * client never holds it.
 *
 * Strictly self-scoped: request.auth.uid must equal the requested uid —
 * a client can never read another user's health data through this
 * function, even though the encrypted blob field itself is readable by
 * anyone with Firestore access to that document (harmless — it's
 * ciphertext without this function's key; see firestore.rules' unchanged
 * users/{uid} rule and this migration's own investigation notes on why
 * no rules change was needed).
 *
 * Returns {} (not an error) when no encryptedHealthData field exists yet
 * — a brand-new user, or one not yet run through the one-time migration
 * script — same "omit rather than guess" convention
 * getUserInjuryData()'s empty defaults already used client-side before
 * this migration.
 *
 * @param {{uid: string}} request.data
 * @return {Promise<object>}
 */
exports.getHealthData = onCall(
    {secrets: [HEALTH_DATA_ENCRYPTION_KEY]},
    async (request) => {
      const requestedUid = request.data && request.data.uid;
      if (typeof requestedUid !== "string" || requestedUid === "") {
        throw new HttpsError("invalid-argument", "uid is required.");
      }
      if (!request.auth || request.auth.uid !== requestedUid) {
        throw new HttpsError(
            "permission-denied",
            "You can only read your own health data.",
        );
      }

      const userDoc = await db.collection("users").doc(requestedUid).get();
      const encrypted = userDoc.exists ?
        userDoc.data().encryptedHealthData :
        null;
      if (typeof encrypted !== "string" || encrypted === "") {
        return {};
      }
      return decryptHealthData(encrypted);
    },
);

/**
 * updateHealthData — merges `data.updates` (a partial or full subset of
 * HEALTH_DATA_FIELDS) into the caller's existing decrypted health-data
 * object, re-encrypts, and writes users/{uid}.encryptedHealthData in one
 * update. Always self-scoped to request.auth.uid — unlike getHealthData,
 * this doesn't even accept a uid parameter from the client, since there's
 * no legitimate reason for a client to ever write another user's data.
 *
 * Any key in `data.updates` not in HEALTH_DATA_FIELDS is rejected outright
 * (invalid-argument) rather than silently accepted into the blob — keeps
 * its shape exactly the 11 confirmed fields, not a dumping ground for
 * whatever a client happens to send.
 *
 * injuryCount (plaintext, non-sensitive — just an integer, never the
 * injury details themselves) is maintained here as a side effect
 * whenever `injuries` is part of this update, written in the SAME
 * Firestore write as the encrypted blob so the two can never be observed
 * out of sync. Exists purely so coach_screen.dart's Phase 4 referral
 * trigger can keep doing a cheap local injuryCount>=3 check via the
 * ordinary getUserProfile() read, with no Cloud Function round-trip and
 * without exposing any injury detail in plaintext.
 *
 * @param {{updates: object}} request.data
 * @return {Promise<{success: boolean}>}
 */
exports.updateHealthData = onCall(
    {secrets: [HEALTH_DATA_ENCRYPTION_KEY]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign-in required.");
      }
      const uid = request.auth.uid;
      const updates = request.data && request.data.updates;
      if (!updates || typeof updates !== "object" || Array.isArray(updates)) {
        throw new HttpsError("invalid-argument", "updates must be an object.");
      }
      const invalidKeys = Object.keys(updates)
          .filter((k) => !HEALTH_DATA_FIELDS.includes(k));
      if (invalidKeys.length > 0) {
        throw new HttpsError(
            "invalid-argument",
            `Unknown health-data field(s): ${invalidKeys.join(", ")}.`,
        );
      }

      const userRef = db.collection("users").doc(uid);
      const userDoc = await userRef.get();
      const existingEncrypted = userDoc.exists ?
        userDoc.data().encryptedHealthData :
        null;
      const existing = (typeof existingEncrypted === "string" &&
          existingEncrypted !== "") ?
        decryptHealthData(existingEncrypted) :
        {};

      const merged = {...existing, ...updates};
      const firestoreUpdate = {
        encryptedHealthData: encryptHealthData(merged),
      };
      if (Object.prototype.hasOwnProperty.call(updates, "injuries")) {
        const injuries = Array.isArray(merged.injuries) ? merged.injuries : [];
        firestoreUpdate.injuryCount = injuries.length;
      }

      await userRef.set(firestoreUpdate, {merge: true});
      return {success: true};
    },
);

// ---------------------------------------------------------------------------
// Deletes every doc under a collection reference, chunked at Firestore's
// 500-op batch-write limit — same chunking convention already used by
// sendAdminBroadcast's fan-out writes above.
// @param {FirebaseFirestore.DocumentReference[]} docRefs
// @return {Promise<void>}
// ---------------------------------------------------------------------------
async function deleteDocsInChunks(docRefs) {
  for (let i = 0; i < docRefs.length; i += 500) {
    const chunk = docRefs.slice(i, i + 500);
    const batch = db.batch();
    for (const ref of chunk) {
      batch.delete(ref);
    }
    await batch.commit();
  }
}

// @param {FirebaseFirestore.CollectionReference} collectionRef
// @return {Promise<void>}
async function deleteCollectionInChunks(collectionRef) {
  const snap = await collectionRef.get();
  await deleteDocsInChunks(snap.docs.map((d) => d.ref));
}

/**
 * deleteUserAccount — deletes the authenticated caller's own WiseWorkout
 * data across Firestore. Runs under the Admin SDK (bypasses Firestore
 * rules entirely, same as checkChallengeProgressOnSessionCreate above) —
 * that's what lets this reach users/{uid}/notifications, which has no
 * client-facing delete rule at all (see firestore.rules).
 *
 * The client calls this FIRST, then deletes the Firebase Auth account
 * itself immediately after (see auth_service.dart's deleteAccount()) —
 * Auth deletion is intentionally NOT done here, so it stays a client-
 * initiated action requiring the client's own fresh re-authentication,
 * exactly like changeEmail()'s existing requires-recent-login gate.
 * Firestore cleanup must finish before Auth deletion, not after —
 * otherwise request.auth.uid stops resolving to a real account mid-flow.
 *
 * Deletes, in order:
 *   1. Every doc in each of this user's own users/{uid} subcollections —
 *      sessions, planProgress, inProgressSessions, missedSessions,
 *      xpEvents, earnedBadges, weightLogs, customRoutines, nutritionLogs,
 *      dailyActivityLog, wiseCoachMessages, friends, friendRequests,
 *      sentFriendRequests, notifications. All owned by this uid; no
 *      cross-user concerns for any of these.
 *   2. users/{uid} itself.
 *   3. publicProfiles/{uid} — the leaderboard mirror.
 *   4. plans/{planId} docs this user created themselves (createdBy == uid
 *      && isCustom == true) — never touches admin-curated plans, which
 *      have no createdBy field at all.
 *   5. follows/{uid}_{followingUid} — this user's own follow edges, as
 *      the follower. Reverse edges are a known limitation, see below.
 *
 * KNOWN LIMITATIONS — explicitly out of scope for this pass, not
 * oversights. Each of these lives on a DIFFERENT user's own data, so
 * cleaning them up here would mean writing into other users' documents
 * from a deletion request they didn't initiate:
 *   - businessPartners/{uid} is never deleted — not attempted.
 *   - Pending coachRequests/coachClients where this user is the CLIENT
 *     (not the coach) are left in place — only the coach side manages
 *     those relationships today.
 *   - friendRequests this user SENT that the recipient never
 *     accepted/declined (living at
 *     users/{recipientUid}/friendRequests/{uid}) are left in place,
 *     along with their matching sentFriendRequests markers.
 *   - notifications this user generated in OTHER users' inboxes (e.g. a
 *     friend_request notification with fromUid == uid) are left in
 *     place.
 *   - Reverse follows/{otherUid}_{uid} edges (other users following this
 *     one) are left in place.
 * All of the above reference a uid that will no longer resolve to a real
 * user once Auth deletion completes — cosmetic residue, not a security
 * exposure. Revisit if it becomes a real problem.
 *
 * @return {Promise<{success: boolean}>}
 */
exports.deleteUserAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const uid = request.auth.uid;
  const userRef = db.collection("users").doc(uid);

  const ownedSubcollections = [
    "sessions", "planProgress", "inProgressSessions", "missedSessions",
    "xpEvents", "earnedBadges", "weightLogs", "customRoutines",
    "nutritionLogs", "dailyActivityLog", "wiseCoachMessages", "friends",
    "friendRequests", "sentFriendRequests", "notifications",
  ];
  for (const sub of ownedSubcollections) {
    await deleteCollectionInChunks(userRef.collection(sub));
  }

  await userRef.delete();

  await db.collection("publicProfiles").doc(uid).delete();

  const customPlansSnap = await db.collection("plans")
      .where("createdBy", "==", uid)
      .where("isCustom", "==", true)
      .get();
  await deleteDocsInChunks(customPlansSnap.docs.map((d) => d.ref));

  const followsSnap = await db.collection("follows")
      .where("followerUid", "==", uid)
      .get();
  await deleteDocsInChunks(followsSnap.docs.map((d) => d.ref));

  return {success: true};
});
