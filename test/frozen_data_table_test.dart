import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/widgets/frozen_data_table.dart';

void main() {
  for (final source in ['frozen', 'body']) {
    testWidgets(
      '$source scroll reaches the next page once and retains offset',
      (tester) async {
        var rows = 40;
        var loads = 0;
        var loading = false;
        Widget table({bool callback = true}) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 260,
              child: FrozenDataTable(
                frozenColumnWidths: const [100],
                frozenHeaders: const [Text('time')],
                frozenCells: (i) => [Text('fixed $i')],
                scrollableColumnWidths: const [400],
                scrollableHeaders: const [Text('value')],
                scrollableCells: (i) => [Text('value $i')],
                rowHeights: List.filled(rows, 44),
                onEndReached: callback
                    ? () {
                        if (!loading) {
                          loading = true;
                          loads++;
                        }
                      }
                    : null,
              ),
            ),
          ),
        );
        await tester.pumpWidget(table());
        ScrollController controller(String side) => tester
            .widget<ListView>(find.byKey(Key('frozen-table-$side-scroll')))
            .controller!;
        final active = controller(source);
        active.jumpTo(active.position.maxScrollExtent);
        await tester.pump();
        expect(loads, 1);
        expect(controller('frozen').offset, controller('body').offset);
        active.jumpTo(active.offset - 10);
        active.jumpTo(active.position.maxScrollExtent);
        expect(loads, 1);
        final offset = active.offset;
        rows = 60;
        await tester.pumpWidget(table());
        await tester.pump();
        expect(active.offset, offset);
        loading = false;
        active.jumpTo(active.position.maxScrollExtent);
        expect(loads, 2);
        await tester.pumpWidget(table(callback: false));
        active.jumpTo(0);
        active.jumpTo(active.position.maxScrollExtent);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('uses the inventory table sizing contract', () {
    expect(FrozenDataTable.headerHeight, 34);
    expect(FrozenDataTable.minimumRowHeight, 44);
  });

  testWidgets(
    'renders multiple frozen columns with synchronized scroll areas',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 260,
              child: FrozenDataTable(
                frozenColumnWidths: const <double>[56, 180],
                frozenHeaders: const <Widget>[Text('收藏'), Text('装备名字')],
                frozenCells: (index) => <Widget>[
                  Text('★$index'),
                  Text('装备 $index'),
                ],
                scrollableColumnWidths: const <double>[160, 160, 160],
                scrollableHeaders: const <Widget>[
                  Text('基础消耗'),
                  Text('0 → +6'),
                  Text('+6 → MAX'),
                ],
                scrollableCells: (index) => <Widget>[
                  Text('资源 $index'),
                  Text('前段 $index'),
                  Text('后段 $index'),
                ],
                rowHeights: List<double>.filled(8, 44),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('frozen-table-horizontal-scroll')), findsOne);
      expect(find.byKey(const Key('frozen-table-frozen-scroll')), findsOne);
      expect(find.byKey(const Key('frozen-table-body-scroll')), findsOne);
      expect(find.text('收藏'), findsOne);
      expect(find.text('装备名字'), findsOne);
    },
  );
}
