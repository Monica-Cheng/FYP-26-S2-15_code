// lib/screens/premium/upgrade_screen.dart
// Full-page premium upsell — replaces the old small-dialog
// showPremiumUpgradeDialog() (premium_upgrade_dialog.dart, removed once
// this landed). All 5 former dialog call sites now context.push(
// Routes.upgrade) instead. No real purchase flow exists yet — the
// "Upgrade" button is a placeholder, same as the dialog it replaces.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/firestore_service.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  // Fallback prices, shown immediately (no spinner) — same "render with
  // fallback, swap in the real value once loaded" pattern as
  // xp_levels.dart's loadThresholds()/profile_screen.dart's
  // _loadXpThresholds() use for level thresholds.
  static const double _kFallbackMonthly = 9.99;
  static const double _kFallbackAnnual = 79.99;

  double _monthlyPrice = _kFallbackMonthly;
  double _annualPrice = _kFallbackAnnual;
  bool _annualSelected = true;

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  // getSubscriptionConfig() itself never throws (see its own doc comment
  // in firestore_service.dart) — a missing/malformed field here just
  // means the `is num` check below fails and the fallback set at field-
  // declaration time is left in place, same fail-soft convention as every
  // other _config* read in that file.
  Future<void> _loadPrices() async {
    final config = await FirestoreService().getSubscriptionConfig();
    if (!mounted) return;
    final monthly = config['premiumPrice'];
    final annual = config['premiumPriceAnnual'];
    setState(() {
      if (monthly is num) _monthlyPrice = monthly.toDouble();
      if (annual is num) _annualPrice = annual.toDouble();
    });
  }

  void _handleUpgradeTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Unlock Premium',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: WW.primaryDark,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Get full access to WiseWorkout's AI coaching, "
                      'unlimited training tools, and more.',
                      style: TextStyle(
                        fontSize: 14,
                        color: WW.textSec,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildPriceCards(),
                    const SizedBox(height: 28),
                    _buildFeatureList(),
                    const SizedBox(height: 32),
                    _buildUpgradeButton(),
                    const SizedBox(height: 12),
                    Center(
                      child: GestureDetector(
                        onTap: () => context.pop(),
                        child: const Text(
                          'Not now',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: WW.textSec,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar — close (X), top-left ───────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.close_rounded, size: 20, color: WW.textSec),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Price cards — visual selection only, no real billing logic ─────────

  Widget _buildPriceCards() {
    return Row(
      children: [
        Expanded(
          child: _PriceCard(
            label: 'Monthly',
            price: '\$${_monthlyPrice.toStringAsFixed(2)}',
            period: '/month',
            selected: !_annualSelected,
            onTap: () => setState(() => _annualSelected = false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PriceCard(
            label: 'Annual',
            price: '\$${_annualPrice.toStringAsFixed(2)}',
            period: '/year',
            selected: _annualSelected,
            onTap: () => setState(() => _annualSelected = true),
            badge: 'Best Value',
          ),
        ),
      ],
    );
  }

  // ── Feature list ─────────────────────────────────────────────────────────

  Widget _buildFeatureList() {
    const features = [
      'Unlimited WiseCoach chat (vs. 25 messages/month)',
      'Unlimited custom routines (vs. 1)',
      'Unlimited challenge creation (vs. 3)',
      'Full nutrition scanning access (locked on Free)',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: features
          .map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: WW.gold, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(
                          fontSize: 15,
                          color: WW.text,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ── Upgrade button — placeholder, no real purchase flow ─────────────────

  Widget _buildUpgradeButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _handleUpgradeTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: WW.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: const Text(
          'Upgrade — Coming Soon',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ── Price card ─────────────────────────────────────────────────────────────

class _PriceCard extends StatelessWidget {
  final String label;
  final String price;
  final String period;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  const _PriceCard({
    required this.label,
    required this.price,
    required this.period,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // Same shape/shadow as WW.cardDecoration — border color/width
          // vary with selection state, which that fixed getter can't
          // express, so it's reconstructed here rather than reused as-is.
          color: WW.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? WW.primary : WW.border,
            width: selected ? 2 : 0.5,
          ),
          boxShadow: WW.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WW.textSec,
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: WW.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: WW.gold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              price,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: WW.text,
              ),
            ),
            Text(
              period,
              style: const TextStyle(fontSize: 12, color: WW.textSec),
            ),
          ],
        ),
      ),
    );
  }
}
