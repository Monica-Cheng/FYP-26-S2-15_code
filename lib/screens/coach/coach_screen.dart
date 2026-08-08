// lib/screens/coach/coach_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../business/coach_dashboard_screen.dart';

const List<String> _kQuickReplies = [
  'My progress this week',
  'Adjust today\'s plan',
  'What should I eat today?',
];

const String _kGreeting = 'Hi! I am WiseCoach. I can help you with workout '
    'advice, exercise tips, and fitness questions. What would you like to '
    'know?';

// Which PRD Section 5.6 condition fired — lets the referral nudge explain
// WHY it's showing instead of one generic message for both. See
// _checkReferralTriggers() for how this is set and _appendReferralMessage()
// for how it selects copy.
enum _ReferralTrigger { injury, missedWorkouts }

// Fixed, generic professional-referral nudges — one per _ReferralTrigger.
// Per the PRD, deliberately NOT AI-generated and never sent to/derived
// from OpenAI. See _checkReferralTriggers()/_appendReferralMessage() below
// for when/how these are appended.
const String _kInjuryReferralMessage =
    'You\'ve logged a few injuries recently — a professional can help make '
    'sure your training works around them safely. You can find a Trainer, '
    'Running Coach, Physiotherapist, or Nutritionist in the Find a '
    'Professional section.';

const String _kMissedWorkoutsReferralMessage =
    'It looks like you\'ve missed several workouts recently — if '
    'something\'s making it hard to stay consistent, a professional might '
    'be able to help. You can find one in the Find a Professional section.';

// ── Screen ─────────────────────────────────────────────────────────────────────

class CoachScreen extends StatefulWidget {
  // Defaults to true so this compiles/behaves exactly as before for any
  // call site that doesn't pass it — the actual live signal comes from
  // MainShell (home_screen.dart) passing `_selectedIndex == <coach tab
  // index>`, which this screen can't observe on its own since it lives
  // inside an IndexedStack (see didUpdateWidget() below for why that
  // matters).
  const CoachScreen({super.key, this.isVisible = true});

  final bool isVisible;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final List<Map<String, dynamic>> _messages = [];
  // dynamic (not String) so assistant entries can carry a bool
  // wasPersonalized flag alongside role/content — see _sendToOpenAI() and
  // _loadWiseCoachState() for where it's set/read, and
  // filterUnpersonalizedHistory() in functions/index.js for how the
  // server uses it.
  final List<Map<String, dynamic>> _chatHistory = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  final _auth = AuthService();
  final _firestore = FirestoreService();

  // Only ever true for an approved coach account — gates the
  // WiseCoach/My Clients toggle below entirely. A normal user (or a
  // pending, not-yet-approved coach) sees zero visual change to this
  // screen: no toggle, plain WiseCoach exactly as before.
  bool _isApprovedCoach = false;
  bool _showingMyClients = false;

  // Loaded once in _loadWiseCoachState() below. _remainingMessages stays
  // null for premium users (and briefly while loading) — the getter
  // _canSend treats null as "not yet known to be blocked" so the input
  // isn't disabled during the load flicker. The REAL enforcement is
  // server-side in callWiseCoachOpenAI; these three fields only ever
  // drive UI (banner text, remaining-count badge, disabling input at 0).
  bool _isPremium = false;
  bool _aiPersonalizationConsent = false;
  int? _remainingMessages;

  // Per-session only — deliberately NOT persisted to Firestore, so the
  // banner reappears the next time this screen is opened. Distinct from
  // hasSeenAiConsentPrompt (the one-time consent dialog's permanent flag,
  // see _maybeShowConsentPrompt) — dismissing this banner is a transient
  // "hide this for now", not a recorded user decision.
  bool _contextBannerDismissed = false;

  bool get _canSend =>
      _isPremium || (_remainingMessages ?? AppConstants.freeMessageLimit) > 0;

  // Professional-referral nudge (PRD Section 5.6) — which trigger
  // condition (if any) is true, checked ONCE per screen session in
  // initState() below (see _checkReferralTriggers()'s own doc comment for
  // why once-per-session rather than re-checked per reply; null means
  // neither condition was met), and whether the nudge has already been
  // shown this session. _referralShownThisSession is deliberately NOT
  // reset by _startNewChat() — "once per app session" means once per
  // screen lifetime, not once per conversation, so starting a new chat
  // doesn't make the nudge eligible to reappear. Neither field is gated
  // on _aiPersonalizationConsent or _isPremium — this is a generic
  // safety/support nudge, not personalization, and applies to every user
  // regardless of either setting.
  _ReferralTrigger? _referralTrigger;
  bool _referralShownThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowConsentPrompt());
    _checkCoachStatus();
    _loadWiseCoachState();
    _checkReferralTriggers();
  }

  // CoachScreen lives inside MainShell's IndexedStack (home_screen.dart),
  // which keeps every tab's State alive and never re-runs initState() on
  // a tab switch — so _loadWiseCoachState()'s one-time load of
  // aiPersonalizationConsent (see that method's own doc comment) goes
  // stale the moment the user toggles it in Settings and switches back
  // here without a full app restart. MainShell passes `isVisible:
  // _selectedIndex == <coach tab index>`, which changes on every tab
  // switch even though this same State instance persists — didUpdateWidget
  // is what a StatefulWidget uses to notice a new widget config at the
  // same tree position, so the false→true edge here is the earliest
  // reliable "this tab just became visible again" signal available
  // without restructuring the IndexedStack itself.
  @override
  void didUpdateWidget(covariant CoachScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _refreshConsentBanner();
    }
  }

  // Narrow re-fetch of just aiPersonalizationConsent for
  // _buildContextBanner() — deliberately NOT a full
  // _loadWiseCoachState() re-run, which also re-queries wiseCoachMessages
  // for both history and the monthly quota count and would be wasteful
  // to repeat on every tab visit. Uses the same getUserProfile() read
  // _loadWiseCoachState() already uses for this exact field — no new
  // Firestore read shape introduced. Fully independent of the
  // wasPersonalized/wiseCoachChatClearedAt logic elsewhere in this file:
  // this never touches wiseCoachMessages at all.
  Future<void> _refreshConsentBanner() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await _firestore.getUserProfile(uid);
      if (!mounted) return;
      final consent = profile?['aiPersonalizationConsent'] as bool? ?? false;
      if (consent != _aiPersonalizationConsent) {
        setState(() => _aiPersonalizationConsent = consent);
      }
    } catch (e) {
      debugPrint('CoachScreen: _refreshConsentBanner failed — $e');
    }
  }

  // Approved-coach accounts default to the "My Clients" side of the
  // toggle on first load (that's their primary reason for being on this
  // tab), but can still switch to WiseCoach — coaches still need their
  // own personal AI assistant same as any user.
  Future<void> _checkCoachStatus() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await _firestore.getUserProfile(uid);
      final role = (profile?['role'] as String?) ?? 'user';
      if (role != 'coach') return;
      final partnerProfile = await _firestore.getBusinessPartnerProfile(uid);
      if (!mounted || partnerProfile?['isApproved'] != true) return;
      setState(() {
        _isApprovedCoach = true;
        _showingMyClients = true;
      });
    } catch (_) {
      // Fails soft — worst case an approved coach just sees plain
      // WiseCoach with no toggle, same as before this feature existed.
    }
  }

  // Professional-referral trigger check (PRD Section 5.6) — evaluates
  // both conditions once, up front, rather than re-querying Firestore on
  // every single reply: the underlying facts (injury count, missed-
  // workout count) don't meaningfully change within the lifetime of one
  // Coach tab visit, so checking once here and caching the result in
  // _referralTrigger is both simpler and cheaper than a per-reply check,
  // while _referralShownThisSession (see _send()) still controls exactly
  // when the cached result actually gets shown.
  //
  // Condition (a): 3+ distinct injuries currently on users/{uid}.injuries
  // — reuses the already-established getUserInjuryData(), no new
  // tracking. Condition (b): 5+ users/{uid}/missedSessions docs within a
  // rolling 7-day window, queried by the 'date' field (a 'yyyy-MM-dd'
  // string, same value as the doc id) with a lexicographic range — ISO
  // date strings sort identically to chronological order, same trick
  // getMonthActivity() already uses for dailyActivityLog doc-id ranges,
  // and a single-field range needs no composite index.
  //
  // Priority when BOTH conditions are true: injury wins, purely as a
  // side effect of checking (a) first and returning early before ever
  // querying missedSessions for (b) — the same structure as before this
  // change, not new logic. Injury is the more urgent/safety-relevant
  // signal (risk of continuing to train around unaddressed injuries)
  // versus a consistency/motivation signal, so it's the more useful one
  // to surface if only one nudge is shown.
  //
  // Deliberately independent of aiPersonalizationConsent and _isPremium —
  // this is a generic safety/support rule, not personalization, and
  // applies to every user. Deliberately never sent to OpenAI — the result
  // only ever controls whether _send() appends a fixed local string,
  // never anything included in the messages array relayed to
  // callWiseCoachOpenAI.
  //
  // Condition (a) reads the plaintext injuryCount field (an integer,
  // maintained by the updateHealthData Cloud Function alongside the
  // encrypted health-data blob — see that function's doc comment in
  // functions/index.js) via the ordinary getUserProfile() read, rather
  // than injuries.length via getUserInjuryData(). This session's health-
  // data-encryption migration moved the injuries array itself into
  // users/{uid}.encryptedHealthData, decryptable only server-side —
  // injuryCount exists specifically so this check can stay a cheap local
  // read with no Cloud Function round-trip and without ever exposing any
  // injury detail in plaintext, exactly as before this migration.
  Future<void> _checkReferralTriggers() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await _firestore.getUserProfile(uid);
      final injuryCount = profile?['injuryCount'] as int? ?? 0;
      if (injuryCount >= 3) {
        if (mounted) {
          setState(() => _referralTrigger = _ReferralTrigger.injury);
        }
        return;
      }

      final now = DateTime.now();
      final windowStart = now.subtract(const Duration(days: 7));
      final missedCount = await _firestore.getMissedSessionCountInRange(
        uid,
        windowStart,
        now,
      );
      if (missedCount >= 5 && mounted) {
        setState(() => _referralTrigger = _ReferralTrigger.missedWorkouts);
      }
    } catch (e) {
      // Fails soft — worst case the user just doesn't see the nudge this
      // session, same as if neither condition were met.
      debugPrint('CoachScreen: _checkReferralTriggers failed — $e');
    }
  }

  // One-time personalization consent prompt — shown the first time the
  // Coach tab is opened, gated on hasSeenAiConsentPrompt so it never
  // reappears once the user has made a choice either way (including
  // "Not now"). Actual gating of what data the Cloud Function reads
  // happens server-side in callWiseCoachOpenAI based on
  // aiPersonalizationConsent, not on anything decided here — this dialog
  // only ever writes the user's choice to Firestore, it doesn't gate
  // requests itself.
  Future<void> _maybeShowConsentPrompt() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await _firestore.getUserProfile(uid);
      final hasSeenPrompt =
          profile?['hasSeenAiConsentPrompt'] as bool? ?? false;
      if (hasSeenPrompt || !mounted) return;
      await _showConsentDialog(uid);
    } catch (_) {}
  }

  Future<void> _showConsentDialog(String uid) async {
    final turnOn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Personalize WiseCoach?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        content: const Text(
          'With your permission, WiseCoach can use your recent training '
          'history, current plan, injury profile, and body profile (like '
          'height, weight, and goals) to give more tailored answers. '
          'This is only used to answer your questions, and you can turn '
          'it off anytime in Settings.',
          style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Turn on personalization',
              style: TextStyle(color: WW.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    try {
      await _firestore.updateUserProfile(uid, {
        'hasSeenAiConsentPrompt': true,
        if (turnOn == true) 'aiPersonalizationConsent': true,
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  String _nowTime() => _formatTime(DateTime.now());

  // Firestore Timestamps read back from a completed .get() are always
  // already resolved (never the null-during-pending-write state a live
  // serverTimestamp() sentinel can briefly have) — the fallback to "now"
  // only exists for a malformed/missing field, not the normal case.
  String _formatMessageTime(dynamic ts) {
    if (ts is Timestamp) return _formatTime(ts.toDate());
    return _nowTime();
  }

  void _addCoachMessage(String text) {
    setState(() {
      _messages.add({'role': 'coach', 'text': text, 'time': _nowTime()});
    });
    _scrollToBottom();
  }

  // Appends the referral nudge matching _referralTrigger as its own
  // distinct bubble (role: 'referral', routed to _ReferralMessage in
  // _buildMessageList() below) — not merged into the AI reply's own
  // bubble, and not persisted to wiseCoachMessages: this is a live,
  // ephemeral nudge for this session, not part of the saved conversation
  // record (the real AI reply it follows is still persisted as normal via
  // _persistExchange()). Only ever called when _referralTrigger is
  // non-null (see _send()'s call site), so the null case below never
  // actually happens in practice.
  void _appendReferralMessage() {
    final text = _referralTrigger == _ReferralTrigger.injury
        ? _kInjuryReferralMessage
        : _kMissedWorkoutsReferralMessage;
    setState(() {
      _messages.add({
        'role': 'referral',
        'text': text,
        'time': _nowTime(),
      });
    });
    _scrollToBottom();
  }

  // "New Chat" — shows the confirm dialog, same AlertDialog styling
  // convention already used by _showConsentDialog() above and
  // plan_detail_screen.dart's Restart Plan dialog.
  Future<void> _confirmNewChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Start a new conversation?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        content: const Text(
          'Your previous chat history will still be saved, but won\'t be '
          'shown here anymore.',
          style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Start New Chat',
              style: TextStyle(color: WW.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _startNewChat();
  }

  // Clears what's currently displayed/loaded in memory immediately, then
  // best-effort writes wiseCoachChatClearedAt onto users/{uid} so the
  // reset also survives a restart/reload — _loadWiseCoachState() below
  // only ever loads wiseCoachMessages docs timestamped after this value.
  // Still deliberately does NOT touch users/{uid}/wiseCoachMessages
  // itself — old messages stay exactly as they are in Firestore, this is
  // a read-time boundary, not a delete. Deliberately does NOT touch
  // _remainingMessages either — the free-tier monthly quota (see
  // _loadWiseCoachState()'s separate monthSnap query) is a real usage
  // count independent of how many separate conversations the user has
  // started, and must not be resettable by tapping this button.
  Future<void> _startNewChat() async {
    setState(() {
      _messages.clear();
      _chatHistory.clear();
    });
    _addCoachMessage(_kGreeting);

    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await _firestore.updateUserProfile(
          uid, {'wiseCoachChatClearedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      // Best-effort, same reasoning as _persistExchange()'s own catch — a
      // failed write here shouldn't surface as a chat error to the user,
      // who already sees the reset locally. Worst case this boundary
      // doesn't survive a restart, same as before this fix existed.
      debugPrint('CoachScreen: _startNewChat cleared-at write failed — $e');
    }
  }

  // Loads everything needed before the chat is fully usable: isPremium/
  // aiPersonalizationConsent (for the banner + remaining-count UI — the
  // real message-limit gate lives server-side in callWiseCoachOpenAI, see
  // that function's doc comment), prior chat history from
  // users/{uid}/wiseCoachMessages (previously _messages/_chatHistory were
  // plain State fields with zero persistence, lost on every restart), and
  // this calendar month's already-used count for non-premium users.
  //
  // History load is NOT month-scoped (last 50 messages regardless of
  // when they were sent) so a conversation still reads naturally across a
  // month boundary; the used-count query below IS separately month-scoped
  // (mirrors countFreeWiseCoachMessagesThisMonth() in functions/index.js
  // exactly — same [monthStart, monthEnd) range-only query with
  // role/isQuickReply filtered in-memory, so no composite index is
  // needed here either).
  Future<void> _loadWiseCoachState() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      _addCoachMessage(_kGreeting);
      return;
    }
    try {
      final profile = await _firestore.getUserProfile(uid);
      _isPremium = profile?['isPremium'] as bool? ?? false;
      _aiPersonalizationConsent =
          profile?['aiPersonalizationConsent'] as bool? ?? false;

      final messagesRef = FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(uid)
          .collection(Collections.wiseCoachMessages);

      // Scoped to messages after the last "New Chat" tap, if there's
      // ever been one (wiseCoachChatClearedAt absent — the common case,
      // nobody's tapped it yet — means no filter, full history, exactly
      // as before this field existed). Single-field range + orderBy on
      // that same field, so this needs no composite index, same as the
      // monthSnap query below. Deliberately independent of that query —
      // see _startNewChat()'s own comment on why the quota must stay
      // unaffected by this boundary.
      final clearedAt = profile?['wiseCoachChatClearedAt'];
      Query<Map<String, dynamic>> historyQuery = messagesRef;
      if (clearedAt is Timestamp) {
        historyQuery = historyQuery.where('timestamp', isGreaterThan: clearedAt);
      }
      final historySnap = await historyQuery
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      if (!_isPremium) {
        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month, 1);
        final monthEnd = DateTime(now.year, now.month + 1, 1);
        final monthSnap = await messagesRef
            .where('timestamp',
                isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .where('timestamp', isLessThan: Timestamp.fromDate(monthEnd))
            .get();
        final usedCount = monthSnap.docs.where((d) {
          final data = d.data();
          return data['role'] == 'user' && data['isQuickReply'] != true;
        }).length;
        _remainingMessages =
            (AppConstants.freeMessageLimit - usedCount).clamp(0, AppConstants.freeMessageLimit);
      }

      if (!mounted) return;
      if (historySnap.docs.isEmpty) {
        _addCoachMessage(_kGreeting);
      } else {
        final loaded = historySnap.docs.reversed.map((d) => d.data()).toList();
        setState(() {
          for (final data in loaded) {
            final role = data['role'] as String? ?? 'assistant';
            final content = data['content'] as String? ?? '';
            _messages.add({
              'role': role == 'user' ? 'user' : 'coach',
              'text': content,
              'time': _formatMessageTime(data['timestamp']),
            });
            _chatHistory.add({
              'role': role == 'user' ? 'user' : 'assistant',
              'content': content,
              // Deliberately omitted (not set to false) whenever the
              // stored doc predates this field — the server treats a
              // missing wasPersonalized the same as true (the safer
              // "might have been personalized" default) when filtering
              // history for a consent-off request. See
              // filterUnpersonalizedHistory() in functions/index.js.
              if (role != 'user' && data['wasPersonalized'] is bool)
                'wasPersonalized': data['wasPersonalized'] as bool,
            });
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      // Fails soft — worst case the user sees the default greeting and no
      // remaining-count badge, same as before this feature existed. Logged
      // (not silent) since a swallowed permission-denied here is exactly
      // what made the missing wiseCoachMessages Firestore rule invisible
      // for as long as it was.
      debugPrint('CoachScreen: _loadWiseCoachState failed — $e');
      if (mounted && _messages.isEmpty) _addCoachMessage(_kGreeting);
    } finally {
      if (mounted) setState(() {});
    }
  }

  // Persists both sides of a successful exchange — only ever called after
  // a real OpenAI reply comes back (see _send()), so a rejected/failed
  // send (including a resource-exhausted message-limit rejection) is
  // never written here. That's what keeps this consistent with the
  // server-side count, which only ever counts messages that actually
  // triggered a real call and got a reply. Two sequential writes (not a
  // batch) so each gets its own resolved server timestamp — a shared
  // batch timestamp would give the user/assistant docs the exact same
  // value, making their relative order ambiguous on the next reload.
  Future<void> _persistExchange({
    required String userText,
    required bool isQuickReply,
    required String assistantText,
    required bool wasPersonalized,
  }) async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final messagesRef = FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(uid)
          .collection(Collections.wiseCoachMessages);
      await messagesRef.add({
        'role': 'user',
        'content': userText,
        'isQuickReply': isQuickReply,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await messagesRef.add({
        'role': 'assistant',
        'content': assistantText,
        // Set from the server's own account of whether THIS reply had
        // personalization context injected (see _sendToOpenAI()) — never
        // guessed client-side. Read back by filterUnpersonalizedHistory()
        // server-side on future requests to decide whether this turn is
        // safe to replay once consent is off.
        'wasPersonalized': wasPersonalized,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Best-effort — a persistence failure shouldn't surface as a chat
      // error to the user, who already has their reply. Worst case this
      // exchange is missing from history on next restart. Logged (not
      // silent) for the same reason as _loadWiseCoachState()'s catch above.
      debugPrint('CoachScreen: _persistExchange failed — $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Relays through the callWiseCoachOpenAI Cloud Function instead of
  // calling OpenAI directly — the API key now lives server-side as a
  // Cloud Functions secret, never in the app bundle. Same system prompt,
  // same conversation history, same model/max_tokens/temperature as
  // before; only WHERE the OpenAI call happens has changed.
  //
  // Returns (reply, wasPersonalized) — the second element is the server's
  // own account of whether THIS reply had personalization context
  // injected (functions/index.js sets it only when the consent gate
  // fired and buildPersonalizationContext() returned something), not a
  // client-side guess. Callers persist it onto the assistant message so a
  // later request, if consent is off by then, knows this specific turn
  // needs to be excluded when replaying history — see
  // filterUnpersonalizedHistory() server-side.
  Future<(String, bool)> _sendToOpenAI(
      List<Map<String, dynamic>> messages) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('callWiseCoachOpenAI');
    final result = await callable.call<Map<String, dynamic>>({
      'messages': [
        {
          'role': 'system',
          'content':
              '''You are WiseCoach, an AI fitness coach inside the WiseWorkout app. \nYou are supportive, knowledgeable, and concise. \nYou help users with workout advice, exercise form, recovery, and fitness goals.\nKeep responses under 3 sentences unless the user asks for detail.\nNever give medical advice. If the user mentions injury or medical issues, \nrecommend they see a professional.\nDo not use markdown formatting — plain text only.'''
        },
        ...messages,
      ],
      'maxTokens': 300,
      'temperature': 0.7,
    });
    final content = result.data['content'] as String?;
    if (content == null) {
      throw Exception('WiseCoach function returned no content');
    }
    final wasPersonalized = result.data['wasPersonalized'] as bool? ?? false;
    return (content, wasPersonalized);
  }

  // isQuickReply is true only when this send was triggered by a
  // _buildQuickReplies() chip tap (see its onTap below) — it still makes
  // a real OpenAI call exactly like typed input always has, but is
  // excluded from the persisted message's count-eligibility so the
  // free-tier limit only ever counts genuine typed questions, per
  // _persistExchange()'s isQuickReply field.
  Future<void> _send([String? override, bool isQuickReply = false]) async {
    if (!_canSend) return; // Input/quick-replies should already be disabled at 0 — extra guard against a stray call.

    final text = (override ?? _inputController.text).trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': text, 'time': _nowTime()});
      _chatHistory.add({'role': 'user', 'content': text});
      _inputController.clear();
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final (reply, wasPersonalized) =
          await _sendToOpenAI(List.from(_chatHistory));
      _chatHistory.add({
        'role': 'assistant',
        'content': reply,
        'wasPersonalized': wasPersonalized,
      });
      _addCoachMessage(reply);
      await _persistExchange(
        userText: text,
        isQuickReply: isQuickReply,
        assistantText: reply,
        wasPersonalized: wasPersonalized,
      );
      if (_referralTrigger != null && !_referralShownThisSession) {
        _referralShownThisSession = true;
        _appendReferralMessage();
      }
      if (!_isPremium && !isQuickReply && mounted) {
        setState(() {
          _remainingMessages =
              ((_remainingMessages ?? AppConstants.freeMessageLimit) - 1)
                  .clamp(0, AppConstants.freeMessageLimit);
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        _addCoachMessage(
          "You've used all ${AppConstants.freeMessageLimit} free messages "
          'this month. Upgrade to WiseCoach Premium for unlimited access.',
        );
        if (mounted) setState(() => _remainingMessages = 0);
      } else {
        _addCoachMessage(
            'I am having trouble connecting right now. Please try again.');
      }
    } catch (_) {
      _addCoachMessage(
          'I am having trouble connecting right now. Please try again.');
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showingClients = _isApprovedCoach && _showingMyClients;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ColoredBox(
        color: WW.bg,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildTopBar(),
              if (_isApprovedCoach) _buildModeToggle(),
              // !showingClients gates the whole banner area; the
              // per-piece visibility (personalization dismissal vs the
              // free-messages condition) is decided inside
              // _buildBannerArea() so the two stay independent.
              if (!showingClients) _buildBannerArea(),
              Expanded(
                child: showingClients
                    ? const CoachManagementBody()
                    : Column(
                        children: [
                          Expanded(child: _buildMessageList()),
                          _buildInputArea(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section 1 — Top bar ───────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: WW.card,
        border: Border(bottom: BorderSide(color: WW.border, width: 0.5)),
        boxShadow: WW.shadow,
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          // Coach avatar
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: WW.lavender,
              shape: BoxShape.circle,
            ),
            child: const Center(child: _SparkleIcon(size: 16, color: Colors.white)),
          ),
          const Spacer(),
          // Title only — the "● Online" status row that used to sit under
          // this was removed as part of the WiseCoach redesign (it implied
          // a presence/availability state WiseCoach doesn't actually have).
          const Text(
            'WiseCoach',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
              letterSpacing: -0.1,
            ),
          ),
          const Spacer(),
          // "New Chat" — meaningless in "My Clients" mode, so it AND the
          // divider that separates it from Find Professional are hidden
          // there (same gating as _buildContextBanner()'s). The divider is
          // inside this conditional deliberately: leaving it outside would
          // strand a dangling separator with nothing on its left.
          if (!(_isApprovedCoach && _showingMyClients)) ...[
            _buildHeaderAction(
              icon: Icons.add_comment_rounded,
              label: 'New Chat',
              onTap: _confirmNewChat,
            ),
            Container(width: 0.5, height: 26, color: WW.border),
          ],
          _buildHeaderAction(
            icon: Icons.person_search_rounded,
            label: 'Find Professional',
            onTap: () => context.push(Routes.findProfessional),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  // Stacked icon-over-label header action. Both header buttons share this
  // so they can't drift apart visually. add_comment_rounded /
  // person_search_rounded match this app's established "_rounded" Material
  // icon suffix convention (send_rounded, visibility_rounded, star_rounded,
  // etc. elsewhere in this file/app).
  Widget _buildHeaderAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: WW.primary),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: WW.primary,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WiseCoach / My Clients toggle (approved coaches only) ─────────────────

  Widget _buildModeToggle() {
    return Container(
      color: WW.card,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _modeToggleButton(
              label: 'WiseCoach',
              active: !_showingMyClients,
              onTap: () => setState(() => _showingMyClients = false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _modeToggleButton(
              label: 'My Clients',
              active: _showingMyClients,
              onTap: () => setState(() => _showingMyClients = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeToggleButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: active ? WW.primary : WW.elevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : WW.textSec,
            ),
          ),
        ),
      ),
    );
  }

  // ── Banner area ───────────────────────────────────────────────────────────
  //
  // Composes two INDEPENDENTLY-gated pieces that share one padded
  // container (so the spacing between them stays correct whichever of the
  // two is showing):
  //
  //   1. The personalization banner — dismissible for the session via its
  //      own X (_contextBannerDismissed).
  //   2. The free-messages card — shown purely on
  //      !_isPremium && remaining != null, and deliberately NOT affected
  //      by _contextBannerDismissed and NOT given a close button: a free
  //      user should always be able to see their remaining credit.
  //
  // Both are additionally gated on !showingClients at the call site.
  // Whole area collapses to nothing when neither piece qualifies.
  Widget _buildBannerArea() {
    final remaining = _remainingMessages;
    final showPersonalization = !_contextBannerDismissed;
    final showFreeMessages = !_isPremium && remaining != null;
    if (!showPersonalization && !showFreeMessages) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: WW.card,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showPersonalization) _buildPersonalizationBanner(),
          if (showPersonalization && showFreeMessages)
            const SizedBox(height: 6),
          if (showFreeMessages) _buildFreeMessagesCard(remaining),
        ],
      ),
    );
  }

  // Personalization banner — even the consent==false case gets a short
  // actionable line rather than nothing, since it's the cheapest way to
  // remind the user personalization exists and where to turn it on. Text
  // mirrors what Phase 2's buildPersonalizationContext() in
  // functions/index.js actually sends today (body/injury/plan profile +
  // session-trend insights), not the PRD's original generic placeholder
  // copy. The _aiPersonalizationConsent ternary itself is unchanged.
  Widget _buildPersonalizationBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: WW.lavender.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WW.lavender.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.auto_awesome_rounded,
                size: 13, color: WW.lavenderDark),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _aiPersonalizationConsent
                  ? 'Using: your training history, current plan, and injury '
                      'profile to personalize answers.'
                  : 'Turn on personalization in Settings for tailored answers.',
              style: const TextStyle(
                fontSize: 11.5,
                color: WW.textSec,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Per-session dismiss — see _contextBannerDismissed's own doc
          // comment for why this isn't persisted. Hides ONLY this banner;
          // the free-messages card below is deliberately unaffected.
          GestureDetector(
            onTap: () => setState(() => _contextBannerDismissed = true),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 14, color: WW.textSec),
            ),
          ),
        ],
      ),
    );
  }

  // Free-messages card — same data and same condition as before
  // (!_isPremium && remaining != null, evaluated by _buildBannerArea()).
  // No close button by design: this is the user's remaining credit, not a
  // dismissible hint.
  Widget _buildFreeMessagesCard(int remaining) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 14, color: WW.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Free messages this month',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: WW.primaryDark,
              ),
            ),
          ),
          Text(
            '$remaining / ${AppConstants.freeMessageLimit}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: WW.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2 — Message list ──────────────────────────────────────────────

  Widget _buildMessageList() {
    final showQuickReplies = _messages.isNotEmpty &&
        _messages.last['role'] == 'coach' &&
        !_isTyping &&
        _chatHistory.isEmpty;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length +
          (_isTyping ? 1 : 0) +
          (showQuickReplies ? 1 : 0),
      itemBuilder: (context, i) {
        // Typing indicator
        if (_isTyping && i == _messages.length) {
          return const _TypingIndicator();
        }
        // Quick replies row
        if (showQuickReplies && i == _messages.length) {
          return _buildQuickReplies();
        }
        // Message bubble
        final msg = _messages[i];
        if (msg['role'] == 'referral') {
          return _ReferralMessage(
            text: msg['text'] as String,
            time: msg['time'] as String,
          );
        }
        return _MessageBubble(
          role: msg['role'] as String,
          text: msg['text'] as String,
          time: msg['time'] as String,
        );
      },
    );
  }

  Widget _buildQuickReplies() {
    final canSend = _canSend;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _kQuickReplies.map((r) {
          return GestureDetector(
            // isQuickReply: true — still a real OpenAI call (unchanged
            // behavior), just excluded from the persisted message's
            // count-eligibility. Disabled at the free-tier limit same as
            // the input bar below, since a tap would just be rejected
            // server-side anyway.
            onTap: canSend ? () => _send(r, true) : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: canSend ? WW.chipBg : WW.elevated,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                r,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: canSend ? WW.primary : WW.textSec,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Section 4 — Input area ────────────────────────────────────────────────

  // Persistent, always-visible (never scrolls away with the message list)
  // — sits directly above the input bar, only ever rendered in WiseCoach
  // mode since _buildInputArea() itself is never built in "My Clients"
  // mode.
  Widget _buildDisclaimer() {
    return Container(
      width: double.infinity,
      color: WW.card,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Text(
        'General guidance, not medical advice.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9.5,
          color: WW.textSec.withValues(alpha: 0.7),
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final canSend = _canSend;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDisclaimer(),
        Container(
          decoration: BoxDecoration(
            color: WW.card,
            border: Border(top: BorderSide(color: WW.border, width: 0.5)),
          ),
          // The old bottom value was `MediaQuery.padding.bottom + 84` —
          // that 84 is exactly _BottomNav's own height, but MainShell
          // renders it via Scaffold's bottomNavigationBar slot, which
          // already reserves that space above the body. So the +84 was
          // dead padding, showing up as a large empty gap between the
          // input bar and the nav. MediaQuery.padding.bottom is kept
          // (Scaffold zeroes it for the body when a bottomNavigationBar
          // is present, so it's a no-op there, but it keeps this correct
          // if this screen is ever hosted without one).
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            MediaQuery.of(context).padding.bottom + 10,
          ),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inputController,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              return Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: WW.bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: WW.border, width: 1.5),
                      ),
                      child: TextField(
                        controller: _inputController,
                        enabled: canSend,
                        style: const TextStyle(fontSize: 13, color: WW.text),
                        decoration: InputDecoration(
                          hintText: canSend
                              ? 'Ask WiseCoach anything...'
                              : 'Message limit reached — upgrade for '
                                  'unlimited access',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: WW.textSec,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                        onSubmitted: canSend ? (_) => _send() : null,
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: (hasText && canSend) ? _send : null,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (hasText && canSend) ? WW.primary : WW.elevated,
                        shape: BoxShape.circle,
                        boxShadow: (hasText && canSend) ? WW.shadow : null,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.send_rounded,
                          size: 17,
                          color:
                              (hasText && canSend) ? Colors.white : WW.textSec,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final String role;
  final String text;
  final String time;

  const _MessageBubble({
    required this.role,
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final isCoach = role == 'coach';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isCoach ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment:
                isCoach ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              if (isCoach) ...[
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 8, bottom: 2),
                  decoration: const BoxDecoration(
                    color: WW.lavender,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: _SparkleIcon(size: 12, color: Colors.white),
                  ),
                ),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  decoration: BoxDecoration(
                    color: isCoach ? WW.card : WW.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isCoach
                          ? const Radius.circular(4)
                          : const Radius.circular(16),
                      bottomRight: isCoach
                          ? const Radius.circular(16)
                          : const Radius.circular(4),
                    ),
                    border: isCoach
                        ? Border.all(color: WW.border, width: 0.5)
                        : null,
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: isCoach ? WW.text : Colors.white,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: isCoach ? 36 : 0,
            ),
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 10,
                color: WW.textSec,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Referral message ───────────────────────────────────────────────────────────
//
// A distinct bubble for the fixed professional-referral nudge (see
// _appendReferralMessage() above) — mirrors _MessageBubble's "coach" left-
// aligned styling (avatar, card background, timestamp) so it reads as
// part of the same conversation, but adds its own tappable action button
// to Routes.findProfessional, which a plain _MessageBubble has no support
// for (it only ever renders static text).

class _ReferralMessage extends StatelessWidget {
  final String text;
  final String time;

  const _ReferralMessage({required this.text, required this.time});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 8, bottom: 2),
                decoration: const BoxDecoration(
                  color: WW.lavender,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: _SparkleIcon(size: 12, color: Colors.white),
                ),
              ),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  decoration: BoxDecoration(
                    color: WW.card,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(color: WW.border, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: WW.text,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => context.push(Routes.findProfessional),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: WW.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.medical_services_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Find a Professional',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 36),
            child: Text(
              time,
              style: const TextStyle(fontSize: 10, color: WW.textSec),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: const BoxDecoration(
              color: WW.lavender,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: _SparkleIcon(size: 12, color: Colors.white),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: WW.card,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: WW.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final phase = ((_ctrl.value * 1400 - i * 160) % 1400) / 1400;
                    final t = (phase < 0.5
                        ? phase * 2
                        : (1.0 - phase) * 2);
                    final scale = 0.8 + 0.2 * t;
                    final opacity = 0.2 + 0.8 * t;
                    return Container(
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: WW.lavender.withValues(alpha: opacity),
                        shape: BoxShape.circle,
                      ),
                      transform: Matrix4.diagonal3Values(scale, scale, 1),
                      transformAlignment: Alignment.center,
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sparkle icon (custom painter to avoid SVG dependency) ─────────────────────

class _SparkleIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _SparkleIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SparklePainter(color: color),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final Color color;
  const _SparklePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // 4-point star
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = (i * 3.14159265 / 4);
      final radius = i.isEven ? r : r * 0.45;
      final x = cx + radius * _cos(angle);
      final y = cy - radius * _sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  double _cos(double angle) {
    return _sin(angle + 3.14159265 / 2);
  }

  double _sin(double angle) {
    double x = angle % (2 * 3.14159265);
    if (x > 3.14159265) x -= 2 * 3.14159265;
    if (x < -3.14159265) x += 2 * 3.14159265;
    final x3 = x * x * x;
    final x5 = x3 * x * x;
    final x7 = x5 * x * x;
    return x - x3 / 6 + x5 / 120 - x7 / 5040;
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.color != color;
}
