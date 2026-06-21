import 'package:flutter/material.dart';
import 'package:dragon_chinese/core/utils/event_tracker.dart';
import 'package:dragon_chinese/design_system/design_system.dart';

import '../models/subscription_plan.dart';
import '../services/subscription_store.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  SubscriptionTier _currentTier = SubscriptionTier.free;
  SubscriptionTier _selectedTier = SubscriptionTier.pro;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadTier();
    EventTracker.track('paywall_viewed');
  }

  Future<void> _loadTier() async {
    final tier = await SubscriptionStore.getTier();
    if (!mounted) return;
    setState(() {
      _currentTier = tier;
      if (tier == SubscriptionTier.proTutor) {
        _selectedTier = SubscriptionTier.proTutor;
      }
    });
  }

  Future<void> _startUpgrade() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      EventTracker.track(
        'paywall_upgrade_started',
        params: {'target_tier': _selectedTier.name},
      );

      // Placeholder purchase integration.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await SubscriptionStore.setTier(_selectedTier);

      if (!mounted) return;
      EventTracker.track(
        'paywall_upgrade_completed',
        params: {'target_tier': _selectedTier.name},
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _restorePurchases() async {
    EventTracker.track('paywall_restore_tapped');
    // Placeholder behavior until real store integration lands.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No prior purchases found on this account.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLabel = SubscriptionStore.labelFor(_currentTier);
    final selectedPlan = SubscriptionCatalog.plans.firstWhere(
      (p) => p.tier == _selectedTier,
    );

    return AppScaffold(
      title: 'Upgrade',
      subtitle: 'Current plan: $currentLabel',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          AppCard(
            variant: AppCardVariant.hero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Learn faster with Pro', style: DsTypography.title),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Unlimited learning flow, exam readiness, and premium tutor depth.',
                  style: DsTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          ...SubscriptionCatalog.plans.map(_buildPlanTile),
          const SizedBox(height: AppSpacing.sectionGap),
          AppButton(
            label: _isSubmitting
                ? 'Processing...'
                : 'Continue • ${selectedPlan.priceLabel}',
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            fullWidth: true,
            onPressed: _isSubmitting ? null : _startUpgrade,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            label: 'Restore Purchases',
            variant: AppButtonVariant.text,
            fullWidth: true,
            onPressed: _restorePurchases,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Billing integration is scaffolded. Connect App Store/Play Billing next.',
            textAlign: TextAlign.center,
            style: DsTypography.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanTile(SubscriptionPlan plan) {
    final selected = plan.tier == _selectedTier;
    final active = plan.tier == _currentTier;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        variant: selected ? AppCardVariant.hero : AppCardVariant.standard,
        onTap: () {
          setState(() => _selectedTier = plan.tier);
          EventTracker.track(
            'paywall_plan_selected',
            params: {'tier': plan.tier.name},
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                      vertical: AppSpacing.xxxs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                    child: Text(
                      'Current',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxxs),
            Text(plan.priceLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xxxs),
            Text(
              plan.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ...plan.features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(feature, style: theme.textTheme.bodySmall),
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
}
