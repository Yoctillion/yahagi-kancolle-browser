import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_query_controls.dart';

Widget _host(
  QuestFilterController filters, {
  QuestCenterMode mode = QuestCenterMode.all,
  Locale locale = const Locale('zh'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark(),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topRight,
      child: QuestHeaderControls(
        mode: mode,
        onModeChanged: (_) {},
        filters: filters,
        translationEnabled: false,
        onTranslationChanged: (_) {},
      ),
    ),
  ),
);

void main() {
  test(
    'query snapshots compare by value and copyWith can clear nullable fields',
    () {
      const value = QuestQuery(
        query: 'A1',
        category: 2,
        period: 1,
        status: QuestStatus.claimable,
      );
      expect(
        value,
        const QuestQuery(
          query: 'A1',
          category: 2,
          period: 1,
          status: QuestStatus.claimable,
        ),
      );
      expect(
        value.hashCode,
        const QuestQuery(
          query: 'A1',
          category: 2,
          period: 1,
          status: QuestStatus.claimable,
        ).hashCode,
      );
      expect(
        value.copyWith(category: null, period: null, status: null),
        const QuestQuery(query: 'A1'),
      );
      expect(value.category, 2);
    },
  );

  test(
    'apply publishes an atomic snapshot once and clear removes exact status',
    () {
      final filters = QuestFilterController();
      addTearDown(filters.dispose);
      var notifications = 0;
      filters.addListener(() => notifications++);
      const query = QuestQuery(
        query: ' A1 ',
        category: 2,
        period: 1,
        status: QuestStatus.claimable,
      );
      filters.apply(query);
      expect(filters.value, query);
      expect(notifications, 1);
      expect(filters.activeCount, 4);
      filters.apply(query);
      expect(notifications, 1);
      filters.clear();
      expect(filters.value, const QuestQuery());
      expect(notifications, 2);
      expect(filters.hasSearch, isFalse);
      expect(filters.hasFilters, isFalse);
    },
  );

  testWidgets('accepted scope exposes a single combined query button', (
    tester,
  ) async {
    final filters = QuestFilterController();
    addTearDown(filters.dispose);
    await tester.pumpWidget(_host(filters, mode: QuestCenterMode.active));

    expect(find.byKey(const Key('quest-search-button')), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-button')), findsNothing);
    await tester.tap(find.byKey(const Key('quest-search-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-query-dialog')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('quest-search-field')))
          .autofocus,
      isFalse,
    );
  });

  testWidgets('typing stays in a draft and cancelling preserves the query', (
    tester,
  ) async {
    final filters = QuestFilterController()..setQuery('old');
    addTearDown(filters.dispose);
    await tester.pumpWidget(_host(filters));
    await tester.tap(find.byKey(const Key('quest-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quest-search-field')), 'new');
    await tester.pump();
    expect(filters.query, 'old');
    await tester.tap(find.byKey(const Key('quest-query-cancel')));
    await tester.pumpAndSettle();
    expect(filters.query, 'old');
    expect(find.byKey(const Key('quest-query-dialog')), findsNothing);
  });

  testWidgets('reset changes only the draft until apply', (tester) async {
    final filters = QuestFilterController()
      ..setQuery('old')
      ..setCategory(2);
    addTearDown(filters.dispose);
    await tester.pumpWidget(_host(filters));
    await tester.tap(find.byKey(const Key('quest-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quest-query-reset')));
    await tester.pump();
    expect(filters.query, 'old');
    expect(filters.category, 2);
    await tester.tap(find.byKey(const Key('quest-query-apply')));
    await tester.pumpAndSettle();
    expect(filters.query, isEmpty);
    expect(filters.category, isNull);
  });

  testWidgets('precise status and live preview apply one atomic query', (
    tester,
  ) async {
    final changes = ChangeNotifier();
    final filters = QuestFilterController();
    addTearDown(filters.dispose);
    addTearDown(changes.dispose);
    var count = 7;
    filters.previewCount = (query) =>
        query.status == QuestStatus.claimable ? count : 100;
    filters.previewChanges = changes;
    var notifications = 0;
    filters.addListener(() => notifications++);
    await tester.pumpWidget(_host(filters));
    await tester.tap(find.byKey(const Key('quest-search-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('quest-filter-status-claimable')),
    );
    await tester.tap(find.byKey(const Key('quest-filter-status-claimable')));
    await tester.pump();
    expect(filters.status, isNull);
    expect(
      find.text(lookupAppLocalizations(const Locale('zh')).questApplyQuery(7)),
      findsOneWidget,
    );
    count = 5;
    changes.notifyListeners();
    await tester.pump();
    expect(
      find.text(lookupAppLocalizations(const Locale('zh')).questApplyQuery(5)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('quest-query-apply')));
    await tester.pumpAndSettle();
    expect(filters.status, QuestStatus.claimable);
    expect(filters.unlockState, isNull);
    expect(notifications, 1);
    expect(find.byKey(const Key('quest-query-dialog')), findsNothing);
  });

  testWidgets(
    'low landscape with keyboard keeps apply visible and content scrollable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(570, 360);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final filters = QuestFilterController();
      addTearDown(filters.dispose);
      await tester.pumpWidget(_host(filters));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('quest-search-button')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 170);
      await tester.pumpAndSettle();
      final apply = find.byKey(const Key('quest-query-apply'));
      expect(tester.getBottomLeft(apply).dy, lessThanOrEqualTo(190));
      expect(
        find.descendant(
          of: find.byKey(const Key('quest-query-dialog')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest-query-dialog')), findsNothing);
    },
  );

  testWidgets(
    'closing removes the original preview subscription after rebinding',
    (tester) async {
      final original = _PreviewChanges();
      final replacement = _PreviewChanges();
      final filters = QuestFilterController()..previewChanges = original;
      addTearDown(filters.dispose);
      addTearDown(original.dispose);
      addTearDown(replacement.dispose);
      await tester.pumpWidget(_host(filters));
      await tester.tap(find.byKey(const Key('quest-search-button')));
      await tester.pumpAndSettle();
      expect(original.listening, isTrue);
      filters.previewChanges = replacement;
      await tester.tap(find.byKey(const Key('quest-query-cancel')));
      await tester.pumpAndSettle();
      expect(original.listening, isFalse);
      expect(replacement.listening, isFalse);
    },
  );

  testWidgets('system back cancels the draft', (tester) async {
    final filters = QuestFilterController()..setCategory(1);
    addTearDown(filters.dispose);
    await tester.pumpWidget(_host(filters));
    await tester.tap(find.byKey(const Key('quest-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quest-search-field')),
      'discard',
    );
    await tester.tap(find.byKey(const Key('quest-filter-category-2')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(filters.value, const QuestQuery(category: 1));
    expect(find.byKey(const Key('quest-query-dialog')), findsNothing);
  });

  testWidgets(
    'translation toggles between translated text and Japanese original',
    (tester) async {
      var enabled = false;
      final l10n = lookupAppLocalizations(const Locale('zh'));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Center(
                child: QuestTranslationToggle(
                  enabled: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(l10n.chineseTranslation), findsOneWidget);
      await tester.tap(find.byKey(const Key('quest-translation-toggle')));
      await tester.pumpAndSettle();
      expect(enabled, isTrue);
      expect(find.text(l10n.japaneseOriginal), findsOneWidget);
      await tester.tap(find.byKey(const Key('quest-translation-toggle')));
      await tester.pumpAndSettle();
      expect(enabled, isFalse);
      expect(find.text(l10n.chineseTranslation), findsOneWidget);
    },
  );

  testWidgets(
    'English controls fit 320 logical pixels without shrinking buttons',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final filters = QuestFilterController();
      addTearDown(filters.dispose);
      await tester.pumpWidget(_host(filters, locale: const Locale('en')));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('quest-search-button'))).height,
        40,
      );
      expect(
        tester.getSize(find.byKey(const Key('quest-mode-tabs'))).height,
        40,
      );
    },
  );
}

class _PreviewChanges extends ChangeNotifier {
  bool get listening => hasListeners;
}
