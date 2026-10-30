import 'package:flutter/widgets.dart';

import '../layout/flat_style.dart';
import '../layout/panel_style.dart';
import '../settings/battle_prediction_settings.dart';

/// Keeps each available feature together while honoring the shared display order.
class BattlePredictionSections extends StatelessWidget {
  const BattlePredictionSections({
    super.key,
    this.order,
    this.legacyEnemyPreviewPosition = EnemyPreviewPosition.above,
    this.sortieMap,
    this.enemyPreview,
    required this.predictionResult,
    this.nodeHeader,
  });

  final List<BattlePredictionSection>? order;
  final EnemyPreviewPosition legacyEnemyPreviewPosition;
  final Widget? sortieMap;
  final Widget? enemyPreview;
  final Widget predictionResult;

  /// Leads the content wherever the shared order puts the map.
  final Widget? nodeHeader;

  @override
  Widget build(BuildContext context) {
    final sections = <BattlePredictionSection, Widget?>{
      BattlePredictionSection.sortieMap: sortieMap,
      BattlePredictionSection.enemyPreview: enemyPreview,
      BattlePredictionSection.predictionResult: predictionResult,
    };
    final effectiveOrder = normalizeBattlePredictionSectionOrder(
      order ??
          (legacyEnemyPreviewPosition == EnemyPreviewPosition.above
              ? defaultBattlePredictionSectionOrder
              : const [
                  BattlePredictionSection.sortieMap,
                  BattlePredictionSection.predictionResult,
                  BattlePredictionSection.enemyPreview,
                ]),
    );
    final gap = PanelStyleScope.isFlat(context) ? flatSectionGap : 9.0;
    final children = <Widget>[];
    var pendingHeader = nodeHeader;
    for (final section in effectiveOrder) {
      final content = sections[section];
      if (content == null) continue;
      if (children.isNotEmpty) children.add(SizedBox(height: gap));
      if (pendingHeader != null &&
          section != BattlePredictionSection.sortieMap) {
        children
          ..add(pendingHeader)
          ..add(SizedBox(height: gap));
        pendingHeader = null;
      }
      children.add(
        KeyedSubtree(
          key: ValueKey('battle-prediction-section-${section.name}'),
          child: content,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
