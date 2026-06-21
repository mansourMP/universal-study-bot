import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription_plan.dart';

class SubscriptionStore {
  static const String _tierKey = 'subscription_tier_v1';

  static Future<SubscriptionTier> getTier() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tierKey);
    return _tierFromString(raw);
  }

  static Future<void> setTier(SubscriptionTier tier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tierKey, _tierToString(tier));
  }

  static String labelFor(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.pro:
        return 'Pro';
      case SubscriptionTier.proTutor:
        return 'Pro + Tutor';
      case SubscriptionTier.free:
        return 'Free';
    }
  }

  static bool hasPro(SubscriptionTier tier) {
    return tier == SubscriptionTier.pro || tier == SubscriptionTier.proTutor;
  }

  static bool hasTutorPremium(SubscriptionTier tier) {
    return tier == SubscriptionTier.proTutor;
  }

  static SubscriptionTier _tierFromString(String? raw) {
    switch (raw) {
      case 'pro':
        return SubscriptionTier.pro;
      case 'pro_tutor':
        return SubscriptionTier.proTutor;
      default:
        return SubscriptionTier.free;
    }
  }

  static String _tierToString(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.pro:
        return 'pro';
      case SubscriptionTier.proTutor:
        return 'pro_tutor';
      case SubscriptionTier.free:
        return 'free';
    }
  }
}
