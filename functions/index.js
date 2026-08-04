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

function normalizeOfficialPlanData(rawData) {
  const data = rawData || {};

  const name = requireNonEmptyAdminString(data.name, "Plan name");
  const level = requireNonEmptyAdminString(data.level, "Level");
  const type = requireNonEmptyAdminString(data.type, "Type");

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

/**
 * Builds a compact, one-line-per-category personalization summary for
 * uid from their body profile, injury profile, active plan, and last 5
 * sessions — omitting any category that's empty/missing entirely rather
 * than sending a placeholder/empty value to the LLM. Mirrors the exact
 * shapes/defaults FirestoreService already uses client-side
 * (getUserInjuryData()'s injuries:[]/injuryFilteringEnabled:false
 * defaults, getSessionsPage()'s orderBy('date', desc).limit(N) shape,
 * planProgress/{planId}'s currentDayIndex/lastCompletedDate/
 * breakModeActive fields) — kept in sync by hand since this runs via
 * firebase-admin instead of the Flutter client. Only ever called when
 * aiPersonalizationConsent is already confirmed true by the caller.
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
 * @return {Promise<string>} non-empty categories joined by newlines, or
 *   "" if nothing was available (brand-new user).
 */
async function buildPersonalizationContext(uid, userData) {
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

  // Recent sessions — last 5 by date, same orderBy/limit shape as
  // getSessionsPage()'s unfiltered case (no composite index needed).
  // Headline stat only per session — never the full exercises array or
  // photoBase64.
  try {
    const sessionsSnap = await db
        .collection("users")
        .doc(uid)
        .collection("sessions")
        .orderBy("date", "desc")
        .limit(5)
        .get();
    if (!sessionsSnap.empty) {
      const summaries = sessionsSnap.docs.map((doc) => {
        const s = doc.data();
        const type = s.type || "session";
        const dateStr = s.date && typeof s.date.toDate === "function" ?
          s.date.toDate().toISOString().substring(0, 10) :
          "unknown date";
        const minutes = typeof s.durationSeconds === "number" ?
          Math.round(s.durationSeconds / 60) :
          null;
        let stat = null;
        if (type === "gym" && typeof s.totalVolume === "number") {
          stat = `${Math.round(s.totalVolume)}kg volume`;
        } else if (type === "cardio" && typeof s.distanceMeters === "number") {
          stat = `${(s.distanceMeters / 1000).toFixed(1)}km`;
        }
        const bits = [dateStr, type];
        if (minutes !== null) bits.push(`${minutes}min`);
        if (stat !== null) bits.push(stat);
        return bits.join(" ");
      });
      lines.push(`Recent sessions: ${summaries.join("; ")}.`);
    }
  } catch (err) {
    console.error(
        `buildPersonalizationContext: sessions read failed for uid ` +
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
      // TEMPORARY DIAGNOSTIC LOGGING — added for the "personalization not
      // reaching the LLM" investigation. Does not change any behavior,
      // only adds visibility into the consent/injection branch, which
      // previously had zero logging on its success path. Remove once the
      // root cause is confirmed via a fresh on-device test + these logs.
      console.log(`callWiseCoachOpenAI DIAGNOSTIC: uid=${uid || "none"}`);
      if (uid) {
        try {
          const userDoc = await db.collection("users").doc(uid).get();
          const userData = userDoc.exists ? userDoc.data() : {};
          console.log(
              "callWiseCoachOpenAI DIAGNOSTIC: userDoc.exists=" +
              `${userDoc.exists}, aiPersonalizationConsent=` +
              `${userData.aiPersonalizationConsent}`,
          );
          if (userData.aiPersonalizationConsent === true) {
            const context = await buildPersonalizationContext(uid, userData);
            console.log(
                "callWiseCoachOpenAI DIAGNOSTIC: context length=" +
                `${context ? context.length : 0}` +
                (context ? ` content=${JSON.stringify(context)}` : ""),
            );
            if (context) {
              const systemMessage = messages.find((m) => m.role === "system");
              console.log(
                  "callWiseCoachOpenAI DIAGNOSTIC: systemMessage found=" +
                  `${!!systemMessage}`,
              );
              if (systemMessage) {
                systemMessage.content =
                    `${systemMessage.content}\n\nWhat you know about this ` +
                    "user (reference this naturally where relevant, don't " +
                    `recite it verbatim):\n${context}`;
              }
            }
          }
        } catch (err) {
          console.error(
              `callWiseCoachOpenAI: personalization context failed for ` +
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
