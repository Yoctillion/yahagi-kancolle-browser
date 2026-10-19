import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/composition_image_page.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/composition_record_store.dart';

void main() {
  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('English composition tabs fit $width px at scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 700);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: CompositionImagePage(
                state: const GameState(memberId: 7),
                recordStore: _EmptyStore(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Saved'), findsOneWidget);
        expect(find.text('Current composition'), findsOneWidget);
        for (final label in ['Saved', 'Current composition']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          expect(
            paragraph.getMinIntrinsicHeight(paragraph.size.width),
            lessThanOrEqualTo(paragraph.size.height + .01),
            reason: '$label must fit vertically within its tab',
          );
          final labelRect = tester.getRect(find.text(label));
          final tabRect = tester.getRect(
            find.byKey(
              Key(
                label == 'Saved'
                    ? 'composition-saved-tab'
                    : 'composition-current-tab',
              ),
            ),
          );
          expect(labelRect.top, greaterThanOrEqualTo(tabRect.top));
          expect(labelRect.bottom, lessThanOrEqualTo(tabRect.bottom));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('composition-current-tab')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _EmptyStore implements CompositionRecordStore {
  @override
  Future<List<CompositionRecord>> load(int memberId) async => [];

  @override
  Future<Uint8List> readPng(int memberId, String id) async => Uint8List(0);

  @override
  Future<void> updateNote(int memberId, String id, String note) async {}

  @override
  Future<void> delete(int memberId, String id) async {}

  @override
  Future<CompositionRecord> create({
    required int memberId,
    required Uint8List png,
    required String note,
    required String name,
    required String fleetForm,
    required String targetMap,
    required List<int> fleetIds,
    required int landBaseCount,
    required DateTime createdAt,
    String? snapshotJson,
    int? landBaseAreaId,
    List<int> landBaseIds = const [],
    String planeCountMode = 'maximum',
    String mapTag = '',
  }) async => throw StateError('Not used by layout tests');
}
