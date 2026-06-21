enum SubscriptionTier { free, pro, proTutor }

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.tier,
    required this.title,
    required this.priceLabel,
    required this.monthlyPriceUsd,
    required this.description,
    required this.features,
  });

  final SubscriptionTier tier;
  final String title;
  final String priceLabel;
  final double monthlyPriceUsd;
  final String description;
  final List<String> features;
}

class SubscriptionCatalog {
  static const List<SubscriptionPlan> plans = [
    SubscriptionPlan(
      tier: SubscriptionTier.pro,
      title: 'Pro',
      priceLabel: '\$9.99 / month',
      monthlyPriceUsd: 9.99,
      description: 'Core learning without limits.',
      features: [
        'Unlimited Path + Skills',
        'Advanced review sessions',
        'Exam prep packs',
      ],
    ),
    SubscriptionPlan(
      tier: SubscriptionTier.proTutor,
      title: 'Pro + Tutor',
      priceLabel: '\$14.99 / month',
      monthlyPriceUsd: 14.99,
      description: 'Everything in Pro plus AI tutor depth.',
      features: [
        'All Pro features',
        'Extended tutor sessions',
        'Priority model routing',
      ],
    ),
  ];
}
