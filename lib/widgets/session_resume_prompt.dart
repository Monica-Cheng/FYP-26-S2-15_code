// lib/widgets/session_resume_prompt.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_theme.dart';
import '../core/router.dart';
import '../services/firestore_service.dart';

// Shared discovery-and-prompt step for every entry point that can start a
// tracked-plan session (home_screen.dart's Today's Plan card,
// plan_detail_screen.dart's _onStartDay, plan_schedule_screen.dart's Start
// Session button) — added because none of them previously checked whether
// an inProgressSessions doc already existed for the same planId+dayIndex
// before unconditionally creating a brand-new one, silently orphaning the
// old doc every time.
//
// Sequence:
//  1. Query for an existing in-progress session via
//     FirestoreService().findInProgressSessionRunId() — a doc only exists
//     in that subcollection while genuinely unfinished
//     (finalizeInProgressSession() deletes it once finalized), so any doc
//     found here is, by construction, still a real resumable/abandoned
//     session.
//  2. None found → call `startFresh()` directly, exactly as every entry
//     point already did before this feature. No prompt shown.
//  3. Found → show a Resume/Start Over choice, styled after
//     gym_session_screen.dart's own _showFinishDialog() (rounded Dialog,
//     drag-handle look, title/body, two-button Row) — the closest existing
//     "confirm a choice about this same in-progress session" precedent in
//     this app, reused rather than inventing a new confirmation style.
//     - Resume navigates straight to gym_session_screen.dart with
//       sessionRunId in `extra`, mirroring the one existing working
//       precedent (mid_plan_cardio_complete_screen.dart's "Next" button)
//       so it hits the already-correct _hydrateFromInProgressSession()
//       path, unchanged.
//     - Start Over deletes the orphaned doc first
//       (FirestoreService().deleteInProgressSession()) then calls the same
//       `startFresh()` the "nothing found" case uses — each entry point's
//       own existing fresh-start navigation is reused as-is rather than
//       duplicated here, since it differs slightly per entry point (Plan
//       Detail's setOverrideDayIndex step vs. Home/Plan Schedule's plain
//       push) and none of that is this function's concern.
//  4. Dismissed without choosing → does nothing, same as cancelling any
//     other confirmation in this app.
Future<void> startOrResumeTrackedSession({
  required BuildContext context,
  required String uid,
  required String planId,
  required int dayIndex,
  required Future<void> Function() startFresh,
}) async {
  final existingSessionRunId =
      await FirestoreService().findInProgressSessionRunId(uid, planId, dayIndex);

  if (existingSessionRunId == null) {
    await startFresh();
    return;
  }

  if (!context.mounted) return;
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: WW.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: WW.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Resume your workout?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "You already started this session and didn't finish it. "
              'Pick up where you left off, or start over from scratch?',
              style: TextStyle(
                fontSize: 13,
                color: WW.textSec,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogCtx, 'startOver'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: WW.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'Start Over',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogCtx, 'resume'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WW.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Resume',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (choice == 'resume') {
    if (!context.mounted) return;
    context.go(Routes.gymSession, extra: {
      'planId': planId,
      'dayIndex': dayIndex,
      'sessionRunId': existingSessionRunId,
    });
  } else if (choice == 'startOver') {
    await FirestoreService().deleteInProgressSession(uid, existingSessionRunId);
    await startFresh();
  }
}
