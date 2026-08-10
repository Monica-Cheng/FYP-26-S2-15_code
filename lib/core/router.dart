// lib/core/router.dart
// All navigation routes defined in one place
// NEVER use Navigator.push anywhere — always use context.go() or context.push()

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Screen imports — add as you build each screen
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/business/coach_dashboard_screen.dart';
import '../screens/business/coach_register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/onboarding/onboarding_step1_screen.dart';
import '../screens/onboarding/onboarding_step2_screen.dart';
import '../screens/plans/gym_session_screen.dart';
import '../screens/onboarding/onboarding_walkthrough_screen.dart';
import '../screens/plans/post_session_summary_screen.dart';
import '../screens/home/manual_activity_log_screen.dart';
import '../screens/home/missed_checkin_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/user_profile_screen.dart';
import '../screens/settings/health_profile_screen.dart';
import '../screens/settings/help_faq_screen.dart';
import '../screens/settings/manage_app_screen.dart';
import '../screens/settings/privacy_policy_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/club/friends_screen.dart';
import '../screens/club/create_challenge_screen.dart';
import '../screens/club/challenge_detail_screen.dart';
import '../screens/club/challenge_leaderboard_screen.dart';
import '../screens/coach/find_professional_screen.dart';
import '../screens/plans/exercise_detail_screen.dart';
import '../screens/plans/plan_detail_screen.dart';
import '../screens/plans/plan_match_screen.dart';
import '../screens/plans/build_routine_screen.dart';
import '../screens/plans/explore_screen.dart';
import '../screens/plans/plan_schedule_screen.dart';
import '../screens/plans/my_plans_library_screen.dart';
import '../screens/plans/mid_plan_cardio_complete_screen.dart';
import '../screens/progress/activity_detail_screen.dart';
import '../screens/progress/nutrition_log_detail_screen.dart';
import '../screens/cardio/cardio_setup_screen.dart';
import '../screens/cardio/cardio_session_screen.dart';
import '../screens/cardio/outdoor_cardio_screen.dart';
import '../screens/nutrition/nutrition_scan_screen.dart';
import '../screens/premium/upgrade_screen.dart';
import '../screens/splash_screen.dart';

// Route path constants — use these instead of hardcoding strings
class Routes {
  Routes._();
  static const String splash = '/splash';
  static const String walkthrough = '/walkthrough';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String register = '/register';
  static const String onboarding = '/onboarding';
  static const String onboardingStep1 = '/onboarding-step1';
  static const String onboardingStep2 = '/onboarding-step2';
  static const String home = '/home';
  static const String plans = '/plans';
  static const String coach = '/coach';
  static const String club = '/club';
  static const String friends = '/friends';
  static const String createChallenge = '/create-challenge';
  static const String challengeDetail = '/challenge-detail';
  static const String challengeLeaderboard = '/challenge-leaderboard';
  static const String progress = '/progress';
  static const String gymSession = '/gym-session';
  static const String postSessionSummary = '/post-session-summary';
  static const String profile = '/profile';
  static const String userProfile = '/user-profile';
  static const String settings = '/settings';
  static const String healthProfile = '/health-profile';
  static const String manageApp = '/manage-app';
  static const String helpFaq = '/help-faq';
  static const String privacyPolicy = '/privacy-policy';
  static const String editProfile = '/edit-profile';
  static const String manualActivityLog = '/manual-activity-log';
  static const String missedCheckin = '/missed-checkin';
  static const String planDetail = '/plan-detail';
  static const String exerciseDetail = '/exercise-detail';
  static const String activityDetail = '/activity-detail';
  static const String nutritionLogDetail = '/nutrition-log-detail';
  static const String findProfessional = '/find-professional';
  static const String planMatch = '/plan-match';
  static const String planSchedule = '/plan-schedule';
  static const String explore = '/explore';
  static const String buildRoutine = '/build-routine';
  static const String editRoutine = '/edit-routine';
  static const String myPlansLibrary = '/my-plans-library';
  static const String cardioSetup = '/cardio-setup';
  static const String cardioSession = '/cardio-session';
  // Temporary/scaffolding route for testing the map-renders-and-permission
  // flow in isolation. Not linked from anywhere in the app yet — a later
  // task wires proper navigation from cardio setup's Outdoor mode and this
  // constant/route can be removed then.
  static const String outdoorCardioTest = '/outdoor-cardio-test';
  static const String nutritionScan = '/nutrition-scan';
  static const String midPlanCardioComplete = '/mid-plan-cardio-complete';
  static const String coachRegister = '/coach-register';
  static const String coachDashboard = '/coach-dashboard';
  static const String upgrade = '/upgrade';
}

// Cache for gymSession's pageBuilder key — see that GoRoute's own doc
// comment for the full history. Deliberately at LIBRARY scope (not a
// class field, not a variable inside the pageBuilder closure) so it
// survives every pageBuilder invocation, including ones triggered by an
// unrelated route being pushed/popped elsewhere in the stack while
// gymSession itself isn't the navigation target — go_router re-invokes
// EVERY currently-matched route's pageBuilder whenever the match list
// changes at all, not just the newly-pushed route's (confirmed against
// the installed go_router 14.8.1 source: RouteBuilder._updatePages()
// iterates every entry in widget.matches on each rebuild). routerProvider
// itself is a plain, non-family, non-autoDispose Riverpod Provider that's
// never invalidated/refreshed anywhere in this app (confirmed by
// searching the codebase), so in practice this GoRouter — and this cache
// — are created exactly once for the app's lifetime. Even in a
// hypothetical re-creation, a library-level variable outliving any single
// GoRouter instance is the correct behavior anyway, since only one
// GoRouter/Navigator is ever live at a time in this single-isolate mobile
// app — there's no concurrency or multi-instance risk to guard against
// here.
String? _lastGymSessionIdentity;
ValueKey<String>? _lastGymSessionKey;

// Same machinery, same reasoning, as _lastGymSessionIdentity/
// _lastGymSessionKey above — see that pair's own doc comment for the full
// history this mirrors. Added after a crash ('!keyReservation.contains
// (key)': is not true) traced to Routes.cardioSetup previously using a
// plain builder: (go_router's default path-only pageKey, identical on
// every push regardless of `extra`) — two pushes of this route ended up
// trying to reserve the same key simultaneously. Identity here is
// sessionRunId+blockId (falling back to 'standalone' when either is
// absent — plans_screen.dart's own cardio-setup entry point pushes this
// route with no `extra` at all, unlike gym_session_screen.dart's plan-
// linked entry point) rather than gymSession's forceRefresh-style
// always-fresh token: unlike gymSession's mid-plan "Next" button, there's
// no legitimate case here where the SAME block/session needs to be
// treated as a fresh identity on every visit — a genuine repeat visit to
// the same block only happens after the earlier CardioSetupScreen page
// was already popped (removed from the stack entirely), so reusing the
// same key then is safe; it's only TWO SIMULTANEOUS pushes for the same
// block (the double-tap crash this fixes) that this identity caching
// guards against, and gym_session_screen.dart's own onTap now also
// guards against that directly (defense in depth, not relying on this
// alone).
String? _lastCardioSetupIdentity;
ValueKey<String>? _lastCardioSetupKey;

// Set by coach_register_screen.dart's "sign in first" gate (its Create
// Account / I already have an account buttons) so the redirect below can
// route to coach registration instead of Home once auth genuinely
// completes — for an EXISTING account that's login_screen.dart's own
// context.go(Routes.home); for a BRAND-NEW account that's several steps
// later, after onboarding_step2_screen.dart's own context.go(Routes.home)
// (registering doesn't skip onboarding — a coach account still needs a
// normal body profile like any other account). Intercepting in the
// router's redirect is a single choke point that covers both paths (plus
// both email/password and Google sign-in within each) without threading
// an `extra` param through 5 different screens individually. Deliberately
// a plain in-memory flag, not persisted — it only needs to survive one
// attempt within the current app session, and is cleared the moment it's
// consumed so it can never hijack an unrelated later "go home" navigation.
bool pendingCoachRegistration = false;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.splash,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final location = state.matchedLocation;

      // Public routes — always allow.
      // coachRegister is public because it's linked from the pre-auth
      // login screen ("Register as Professional") — the screen itself
      // gates on FirebaseAuth.instance.currentUser and shows a "sign in
      // first" prompt rather than the actual form when unauthenticated,
      // since the registration write needs a real uid.
      final isPublicRoute = location == Routes.splash ||
          location == Routes.walkthrough ||
          location == Routes.login ||
          location == Routes.register ||
          location == Routes.forgotPassword ||
          location == Routes.coachRegister;
      if (isPublicRoute) return null;

      // Onboarding routes — allow only while logged in.
      // (Splash already sent unauthenticated users to login.)
      if (user == null) return Routes.login;

      // Redirect to coach registration instead of Home, exactly once,
      // if the user got here via coach_register_screen.dart's sign-in
      // gate — see pendingCoachRegistration's own doc comment above.
      if (pendingCoachRegistration && location == Routes.home) {
        pendingCoachRegistration = false;
        return Routes.coachRegister;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.walkthrough,
        builder: (context, state) => const OnboardingWalkthroughScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: Routes.onboardingStep1,
        builder: (context, state) => const OnboardingStep1Screen(),
      ),
      GoRoute(
        path: Routes.onboardingStep2,
        builder: (context, state) => const OnboardingStep2Screen(),
      ),
      GoRoute(
        path: Routes.gymSession,
        // A plain builder: here lets GoRouter fall back to its default
        // pageKey, which is derived only from the matched path string
        // (confirmed against the installed go_router 14.8.1 source —
        // match.dart's ValueKey<String>(newMatchedPath)) — the same key
        // for every navigation to this route regardless of `extra`, which
        // lets Flutter's Page reconciliation reuse whatever GymSessionScreen
        // instance is already buried in the Navigator's route list instead
        // of creating a fresh one — so initState()/_loadPlanSession() never
        // re-runs and the screen keeps showing stale state.
        //
        // An earlier fix generated a unique key only when extra carried a
        // sessionRunId (the resume/mid-plan-cardio-return case), keeping a
        // single static key for every "fresh start" push (no sessionRunId)
        // on the theory that a first-time plan start needed to match
        // exactly one prior stable-key behavior. That was scoped too
        // narrowly: FOUR different entry points all push this route with no
        // sessionRunId — home_screen.dart's Start Workout,
        // plan_schedule_screen.dart's Start Session, plan_detail_screen.dart's
        // Preview (_onStartDay), and plans_screen.dart's tracked-plan-card
        // tap — so all four shared that one static key. Visiting more than
        // one of them in the same app session (without the earlier instance
        // ever being popped) reused the buried instance across genuinely
        // different plans/days, silently carrying over stale
        // planId/dayIndex/_sessionRunId state from whichever entry point
        // was visited first.
        //
        // Fix (v1): always generate a unique key, for every navigation to
        // this route, with no static fallback. This closed the bug above,
        // but too bluntly: go_router re-invokes THIS pageBuilder on every
        // match-list change anywhere in the stack, not only when this
        // route is the actual navigation target (confirmed against the
        // installed go_router 14.8.1 source). So pushing an unrelated
        // route on top of an already-active gym session — e.g. the (i)
        // info icon pushing exercise_detail_screen.dart — re-ran this
        // pageBuilder purely as a side effect, generated a fresh
        // timestamp-based key for a route that hadn't actually changed,
        // and Flutter's Page reconciliation tore down and recreated the
        // live GymSessionScreen instance immediately (before the user
        // even looked at the pushed screen) — losing the running timer
        // and completed sets, then "restarting" the whole session the
        // moment the user popped back.
        //
        // Fix (v2): only generate a NEW key when this route's own session
        // identity — '${sessionRunId ?? planId ?? 'none'}-${dayIndex ??
        // 'none'}' — actually changes from the last time this pageBuilder
        // ran — see _lastGymSessionIdentity/_lastGymSessionKey above.
        // dayIndex is included (not just sessionRunId/planId) so reaching a
        // different day of the SAME plan back-to-back, without the earlier
        // instance ever being popped, still counts as a different identity
        // and gets its own fresh key — sessionRunId/planId alone would
        // otherwise collapse planA-day1 and planA-day2 to the same cached
        // identity. A pageBuilder re-invocation caused by an unrelated
        // push/pop elsewhere in the stack sees the same identity as before
        // and reuses the cached key, so Flutter reconciliation correctly
        // recognizes it as the same page and leaves the live instance
        // alone. A genuine navigation to a DIFFERENT session/plan/day — the
        // original v1 bug this was fixing — still gets a fresh,
        // guaranteed-unique key, exactly as before.
        //
        // Fix (v3, current): v2 broke mid_plan_cardio_complete_screen.dart's
        // "Next" button — sessionRunId/planId/dayIndex are all identical on
        // every "Next" tap within one session (nothing block-specific feeds
        // them), so v2's identity never changed there either, wrongly
        // treating every "Next" after the first as a cache hit and reusing
        // the stale instance instead of the fresh rehydrate "Next" was
        // built to guarantee. That call site now adds an optional
        // 'forceRefresh' field (a fresh value every tap) to extra — folded
        // into the identity string below when present — so its identity
        // genuinely differs on every tap regardless of how the other three
        // fields stay unchanged. No other call site of this route sets
        // 'forceRefresh', so it's always empty for them and this is purely
        // additive — v2's own two fixes above are otherwise untouched.
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final readOnly = extra?['readOnly'] as bool? ?? false;
          final sessionRunId = extra?['sessionRunId'] as String?;
          final planId = extra?['planId'] as String?;
          final dayIndex = extra?['dayIndex'] as int?;
          // dayIndex folded in so planA-day1 and planA-day2 don't collapse
          // to the same cached identity if reached back-to-back without
          // the earlier instance ever being popped — same 'none' fallback
          // already used for sessionRunId/planId above, not dayIndex's raw
          // null (avoids a confusing literal "planA-null" string).
          //
          // forceRefresh — optional, present only on mid_plan_cardio_
          // complete_screen.dart's "Next" button pushes (see that call
          // site's own doc comment). sessionRunId/planId/dayIndex are all
          // identical across every "Next" tap within one session, so
          // without this the identity above would stay unchanged from the
          // second cardio block onward, wrongly reusing the cached key and
          // skipping the rehydrate that call was written to guarantee.
          // Every other existing call site of this route never sets this
          // field, so it's always empty there and never affects their
          // identity string at all — purely additive, existing caching
          // behavior (both the original stale-state fix and the info-icon
          // fix) is unchanged for every other case.
          final forceRefresh = extra?['forceRefresh'] as String? ?? '';
          final identity =
              '${sessionRunId ?? planId ?? 'none'}-${dayIndex ?? 'none'}-$forceRefresh';

          final ValueKey<String> key;
          if (_lastGymSessionIdentity == identity &&
              _lastGymSessionKey != null) {
            key = _lastGymSessionKey!;
          } else {
            key = ValueKey(
                'gym-session-$identity-${DateTime.now().microsecondsSinceEpoch}');
            _lastGymSessionIdentity = identity;
            _lastGymSessionKey = key;
          }

          return MaterialPage(
            key: key,
            child: GymSessionScreen(readOnly: readOnly),
          );
        },
      ),
      GoRoute(
        path: Routes.postSessionSummary,
        builder: (context, state) => const PostSessionSummaryScreen(),
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.userProfile,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return UserProfileScreen(
            uid: extra?['uid'] as String? ?? '',
            initialName: extra?['authorName'] as String?,
          );
        },
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.healthProfile,
        builder: (context, state) => const HealthProfileScreen(),
      ),
      GoRoute(
        path: Routes.manageApp,
        builder: (context, state) => const ManageAppScreen(),
      ),
      GoRoute(
        path: Routes.helpFaq,
        builder: (context, state) => const HelpFaqScreen(),
      ),
      GoRoute(
        path: Routes.privacyPolicy,
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: Routes.manualActivityLog,
        builder: (context, state) => const ManualActivityLogScreen(),
      ),
      GoRoute(
        path: Routes.missedCheckin,
        builder: (context, state) => const MissedCheckinScreen(),
      ),
      GoRoute(
        path: Routes.planDetail,
        builder: (context, state) => const PlanDetailScreen(),
      ),
      GoRoute(
        path: Routes.exerciseDetail,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final name = extra?['name'] as String? ?? '';
          final muscle = extra?['muscle'] as String? ?? '';
          return ExerciseDetailScreen(
            exerciseName: name,
            muscle: muscle,
          );
        },
      ),
      GoRoute(
        path: Routes.activityDetail,
        builder: (context, state) => const ActivityDetailScreen(),
      ),
      GoRoute(
        path: Routes.nutritionLogDetail,
        builder: (context, state) => const NutritionLogDetailScreen(),
      ),
      GoRoute(
        path: Routes.findProfessional,
        builder: (context, state) => const FindProfessionalScreen(),
      ),
      GoRoute(
        path: Routes.planMatch,
        builder: (context, state) => const PlanMatchScreen(),
      ),
      GoRoute(
        path: Routes.planSchedule,
        builder: (context, state) => const PlanScheduleScreen(),
      ),
      GoRoute(
        path: Routes.explore,
        builder: (context, state) => const ExploreScreen(),
      ),
      GoRoute(
        path: Routes.buildRoutine,
        builder: (context, state) => const BuildRoutineScreen(),
      ),
      GoRoute(
        path: Routes.editRoutine,
        builder: (context, state) => const BuildRoutineScreen(),
      ),
      GoRoute(
        path: Routes.myPlansLibrary,
        builder: (context, state) {
          final plans = state.extra as List<Map<String, dynamic>>?;
          return MyPlansLibraryScreen(plans: plans ?? const []);
        },
      ),
      GoRoute(
        path: Routes.cardioSetup,
        // pageBuilder + cached identity-based key — see
        // _lastCardioSetupIdentity/_lastCardioSetupKey's own doc comment
        // above for why (fixes a real '!keyReservation.contains(key)'
        // crash from two rapid pushes of this route colliding on the
        // previous plain builder:'s identical default path-only key).
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final sessionRunId = extra?['sessionRunId'] as String?;
          final blockId = extra?['blockId'] as String?;
          final identity = sessionRunId != null && blockId != null
              ? '$sessionRunId-$blockId'
              : 'standalone';

          final ValueKey<String> key;
          if (_lastCardioSetupIdentity == identity &&
              _lastCardioSetupKey != null) {
            key = _lastCardioSetupKey!;
          } else {
            key = ValueKey(
                'cardio-setup-$identity-${DateTime.now().microsecondsSinceEpoch}');
            _lastCardioSetupIdentity = identity;
            _lastCardioSetupKey = key;
          }

          return MaterialPage(
            key: key,
            child: const CardioSetupScreen(),
          );
        },
      ),
      GoRoute(
        path: Routes.cardioSession,
        builder: (context, state) => const CardioSessionScreen(),
      ),
      GoRoute(
        path: Routes.nutritionScan,
        builder: (context, state) => NutritionScanScreen(
          startInDescribeMode: state.extra == 'describe',
        ),
      ),
      GoRoute(
        path: Routes.upgrade,
        builder: (context, state) => const UpgradeScreen(),
      ),
      // Temporary/scaffolding — see the Routes.outdoorCardioTest comment.
      GoRoute(
        path: Routes.outdoorCardioTest,
        builder: (context, state) => const OutdoorCardioScreen(),
      ),
      GoRoute(
        path: Routes.midPlanCardioComplete,
        builder: (context, state) => const MidPlanCardioCompleteScreen(),
      ),
      GoRoute(
        path: Routes.friends,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final expandRequests = extra?['expandRequests'] as bool? ?? false;
          return FriendsScreen(initialRequestsExpanded: expandRequests);
        },
      ),
      GoRoute(
        path: Routes.createChallenge,
        builder: (context, state) => const CreateChallengeScreen(),
      ),
      GoRoute(
        path: Routes.challengeDetail,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ChallengeDetailScreen(
            challengeId: extra?['challengeId'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: Routes.challengeLeaderboard,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ChallengeLeaderboardScreen(
            challengeId: extra?['challengeId'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: Routes.coachRegister,
        builder: (context, state) => const CoachRegisterScreen(),
      ),
      GoRoute(
        path: Routes.coachDashboard,
        builder: (context, state) => const CoachDashboardScreen(),
      ),
      // Add more routes here as you build each screen
    ],
  );
});
