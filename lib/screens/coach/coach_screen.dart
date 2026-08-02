// lib/screens/coach/coach_screen.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

const List<String> _kQuickReplies = [
  'My progress this week',
  'Adjust today\'s plan',
  'What should I eat today?',
];

// ── Screen ─────────────────────────────────────────────────────────────────────

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, String>> _chatHistory = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  final _auth = AuthService();
  final _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _addCoachMessage(
      'Hi! I am WiseCoach. I can help you with workout advice, exercise tips, and fitness questions. What would you like to know?',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowConsentPrompt());
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

  String _nowTime() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  void _addCoachMessage(String text) {
    setState(() {
      _messages.add({'role': 'coach', 'text': text, 'time': _nowTime()});
    });
    _scrollToBottom();
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
  Future<String> _sendToOpenAI(List<Map<String, String>> messages) async {
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
    return content;
  }

  Future<void> _send([String? override]) async {
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
      final reply = await _sendToOpenAI(List.from(_chatHistory));
      _chatHistory.add({'role': 'assistant', 'content': reply});
      _addCoachMessage(reply);
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ColoredBox(
        color: WW.bg,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildMessageList()),
              _buildInputArea(),
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
          // Title + online status
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'WiseCoach',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Online',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // Find Professional button
          GestureDetector(
            onTap: () => context.push(Routes.findProfessional),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Find Professional',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WW.primary,
                ),
              ),
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
        return _MessageBubble(
          role: msg['role'] as String,
          text: msg['text'] as String,
          time: msg['time'] as String,
        );
      },
    );
  }

  Widget _buildQuickReplies() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _kQuickReplies.map((r) {
          return GestureDetector(
            onTap: () => _send(r),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: WW.chipBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                r,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: WW.primary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Section 4 — Input area ────────────────────────────────────────────────

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: WW.border, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).padding.bottom + 84,
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
                    style: const TextStyle(fontSize: 13, color: WW.text),
                    decoration: const InputDecoration(
                      hintText: 'Ask WiseCoach anything...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: WW.textSec,
                      ),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: hasText ? _send : null,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: hasText ? WW.primary : WW.elevated,
                    shape: BoxShape.circle,
                    boxShadow: hasText ? WW.shadow : null,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.send_rounded,
                      size: 17,
                      color: hasText ? Colors.white : WW.textSec,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
