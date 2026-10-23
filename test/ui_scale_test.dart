import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/layout/ui_scale.dart';

const _contentKey = Key('content');
const _labelKey = Key('label');
const _iconKey = Key('icon');
const _trackKey = Key('track');
const _scaleKey = Key('scale');

Widget _content() => Padding(
  key: _contentKey,
  padding: const EdgeInsets.all(2),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('HP 42/53', key: _labelKey, style: TextStyle(fontSize: 11)),
          SizedBox(width: 4),
          Icon(Icons.flight, key: _iconKey, size: 18),
        ],
      ),
      const SizedBox(height: 3),
      const SizedBox(key: _trackKey, width: 120, height: 4),
    ],
  ),
);

Widget _host({required double scale, Widget? child, Size? tightSize}) =>
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: tightSize?.width,
              height: tightSize?.height,
              child: UiScale(
                key: _scaleKey,
                scale: scale,
                child: child ?? _content(),
              ),
            ),
          ),
        ),
      ),
    );

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

void _expectScaled(Size actual, Size original, double factor) {
  expect(actual.width, closeTo(original.width * factor, .001));
  expect(actual.height, closeTo(original.height * factor, .001));
}

void main() {
  testWidgets('loose layout grows text, icon and row height together', (
    tester,
  ) async {
    await tester.pumpWidget(_host(scale: 1));
    final original = {
      for (final key in [_contentKey, _labelKey, _iconKey, _trackKey])
        key: _paintedRect(tester, find.byKey(key)).size,
    };
    final oldHeight = tester.getSize(find.byKey(_scaleKey)).height;

    await tester.pumpWidget(_host(scale: 1.1));

    for (final entry in original.entries) {
      _expectScaled(
        _paintedRect(tester, find.byKey(entry.key)).size,
        entry.value,
        1.1,
      );
    }
    expect(
      tester.getSize(find.byKey(_scaleKey)).height,
      closeTo(oldHeight * 1.1, .001),
    );
    final frame = _paintedRect(tester, find.byKey(_scaleKey));
    final track = _paintedRect(tester, find.byKey(_trackKey));
    expect(track.right, lessThanOrEqualTo(frame.right));
    expect(track.bottom, lessThanOrEqualTo(frame.bottom));
    expect(tester.widget<Text>(find.byKey(_labelKey)).style!.fontSize, 11);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byKey(_labelKey))).scale(11),
      14.3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tight layout reserves the frame and scales inside its bounds', (
    tester,
  ) async {
    const frameSize = Size(220, 110);
    await tester.pumpWidget(_host(scale: 1, tightSize: frameSize));
    final originalLabel = _paintedRect(tester, find.byKey(_labelKey)).size;
    final originalIcon = _paintedRect(tester, find.byKey(_iconKey)).size;

    await tester.pumpWidget(_host(scale: 1.1, tightSize: frameSize));

    expect(tester.getSize(find.byKey(_scaleKey)), frameSize);
    final content = tester.getSize(find.byKey(_contentKey));
    expect(content.width, closeTo(200, .001));
    expect(content.height, closeTo(100, .001));
    _expectScaled(
      _paintedRect(tester, find.byKey(_labelKey)).size,
      originalLabel,
      1.1,
    );
    _expectScaled(
      _paintedRect(tester, find.byKey(_iconKey)).size,
      originalIcon,
      1.1,
    );
    final frame = _paintedRect(tester, find.byKey(_scaleKey));
    final track = _paintedRect(tester, find.byKey(_trackKey));
    expect(track.right, lessThanOrEqualTo(frame.right));
    expect(track.bottom, lessThanOrEqualTo(frame.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing scale retains the same stateful child and its value', (
    tester,
  ) async {
    var mounts = 0;
    var disposals = 0;
    Widget probe() =>
        _Probe(onMount: () => mounts++, onDispose: () => disposals++);
    await tester.pumpWidget(_host(scale: 1, child: probe()));
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    await tester.tap(find.text('count 0'));
    await tester.pump();

    for (final factor in [1.1, 1.0, 1.1]) {
      await tester.pumpWidget(_host(scale: factor, child: probe()));
      expect(tester.state<_ProbeState>(find.byType(_Probe)), same(state));
      expect(find.text('count 1'), findsOneWidget);
    }
    expect(mounts, 1);
    expect(disposals, 0);
  });

  testWidgets('tap in the enlarged edge maps back to the child', (
    tester,
  ) async {
    var taps = 0;
    const target = Key('target');
    await tester.pumpWidget(
      _host(
        scale: 1.1,
        child: GestureDetector(
          key: target,
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox(width: 100, height: 24),
        ),
      ),
    );
    final rect = _paintedRect(tester, find.byKey(target));
    expect(rect.width, closeTo(110, .001));
    await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('absolute nested scales do not multiply and can opt out', (
    tester,
  ) async {
    double? inherited;
    Widget nested(double factor) => UiScale(
      scale: factor,
      child: Builder(
        builder: (context) {
          inherited = UiScale.of(context);
          return const SizedBox(key: _contentKey, width: 100, height: 20);
        },
      ),
    );
    await tester.pumpWidget(_host(scale: 1.1, child: nested(1.1)));
    expect(inherited, 1.1);
    _expectScaled(
      _paintedRect(tester, find.byKey(_contentKey)).size,
      const Size(100, 20),
      1.1,
    );

    await tester.pumpWidget(_host(scale: 1.1, child: nested(1)));
    expect(inherited, 1);
    _expectScaled(
      _paintedRect(tester, find.byKey(_contentKey)).size,
      const Size(100, 20),
      1,
    );
  });

  testWidgets('intrinsic and dry sizes include the scale', (tester) async {
    await tester.pumpWidget(
      _host(scale: 1.1, child: const SizedBox(width: 100, height: 30)),
    );
    final box = tester.renderObject<RenderBox>(find.byKey(_scaleKey));
    expect(box.getMinIntrinsicWidth(double.infinity), closeTo(110, .001));
    expect(box.getMaxIntrinsicWidth(double.infinity), closeTo(110, .001));
    expect(box.getMinIntrinsicHeight(double.infinity), closeTo(33, .001));
    expect(box.getMaxIntrinsicHeight(double.infinity), closeTo(33, .001));
    _expectScaled(
      box.getDryLayout(const BoxConstraints()),
      const Size(100, 30),
      1.1,
    );
  });

  testWidgets('scaled text stays aligned to a sibling baseline', (
    tester,
  ) async {
    const referenceKey = Key('reference');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: const [
              UiScale(
                scale: 1.1,
                child: Text(
                  'Scaled',
                  key: _labelKey,
                  style: TextStyle(fontSize: 11),
                ),
              ),
              Text(
                'Reference',
                key: referenceKey,
                style: TextStyle(fontSize: 20),
              ),
            ],
          ),
        ),
      ),
    );
    double paintedBaseline(Key key) {
      final box = tester.renderObject<RenderBox>(find.byKey(key));
      final baseline = box.getDryBaseline(
        box.constraints,
        TextBaseline.alphabetic,
      )!;
      return box.localToGlobal(Offset(0, baseline)).dy;
    }

    expect(
      paintedBaseline(_labelKey),
      closeTo(paintedBaseline(referenceKey), .001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('factor one is transparent to layout and inherited scale', (
    tester,
  ) async {
    double? inherited;
    await tester.pumpWidget(
      _host(
        scale: 1,
        child: Builder(
          builder: (context) {
            inherited = UiScale.of(context);
            return const SizedBox(key: _contentKey, width: 100, height: 30);
          },
        ),
      ),
    );
    expect(inherited, 1);
    expect(tester.getSize(find.byKey(_scaleKey)), const Size(100, 30));
    expect(
      _paintedRect(tester, find.byKey(_contentKey)).size,
      const Size(100, 30),
    );
  });

  test('scale rejects zero, negative and non-finite values', () {
    for (final factor in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => UiScale(scale: factor, child: const SizedBox()),
        throwsAssertionError,
      );
    }
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onMount, required this.onDispose});
  final VoidCallback onMount;
  final VoidCallback onDispose;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  var count = 0;

  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => count++),
    child: Text('count $count'),
  );
}
