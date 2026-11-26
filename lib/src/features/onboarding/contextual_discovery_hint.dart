import 'package:flutter/material.dart';

import 'feature_discovery_guide.dart';

class ContextualDiscoveryHint extends StatelessWidget {
  const ContextualDiscoveryHint({
    required this.feature,
    required this.title,
    required this.message,
    super.key,
  });

  final String feature;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) =>
      feature == 'planned-payments' || feature == 'review-inbox'
      ? DiscoveryGuideSample(feature: feature)
      : const SizedBox.shrink();
}
