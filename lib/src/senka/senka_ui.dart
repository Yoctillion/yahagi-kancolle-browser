import 'package:flutter/material.dart';

const senkaBackground = Color(0xff071520);
const senkaPanel = Color(0xff102432);
const senkaPanelAlt = Color(0xff0d202d);
const senkaLine = Color(0xff294657);
const senkaText = Color(0xffe7eef2);
const senkaMuted = Color(0xff8198a7);
const senkaGold = Color(0xffd7a957);
const senkaGreen = Color(0xff5dc9a5);
const senkaYellow = Color(0xffe4b34e);
const senkaRed = Color(0xffec7777);
const senkaWeekdayBackground = Color(0xff071923);

const senkaPlannedCard = Color(0xff0d2b45);
const senkaPlannedBorder = Color(0xff3a8fe0);
const senkaCompletedCard = Color(0xff091a26);
const senkaCompletedBorder = Color(0xff224259);
const senkaDeferredCard = Color(0xff091a26);
const senkaDeferredBorder = Color(0xfff0b83e);

String senkaNumber(num? value) =>
    value == null ? '--' : value.toStringAsFixed(2);
String senkaInteger(int? value) => value?.toString() ?? '--';

String senkaJstTimestamp(DateTime? time) {
  if (time == null) return '--';
  final jst = time.toUtc().add(const Duration(hours: 9));
  final year = jst.year.toString().padLeft(4, '0');
  final month = jst.month.toString().padLeft(2, '0');
  final day = jst.day.toString().padLeft(2, '0');
  final hour = jst.hour.toString().padLeft(2, '0');
  final minute = jst.minute.toString().padLeft(2, '0');
  final second = jst.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

class SenkaPanel extends StatelessWidget {
  const SenkaPanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.compact = false,
    this.headerHeight,
    this.fitContent = false,
  });
  final String title;
  final Widget child;
  final Widget? trailing;
  final bool compact;
  final double? headerHeight;
  final bool fitContent;
  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    final titleText = Text(
      title,
      maxLines: english ? null : 1,
      overflow: english ? null : TextOverflow.ellipsis,
      style: TextStyle(
        color: senkaText,
        fontSize: compact ? 12 : 15,
        fontWeight: FontWeight.w800,
      ),
    );
    return Material(
      color: senkaPanel,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: senkaLine),
        borderRadius: BorderRadius.circular(compact ? 7 : 11),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 6 : 10),
        child: Column(
          mainAxisSize: fitContent ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Container(
              width: english ? double.infinity : null,
              height: english ? null : headerHeight ?? (compact ? 28 : 36),
              constraints: english
                  ? BoxConstraints(
                      minHeight: headerHeight ?? (compact ? 28 : 36),
                    )
                  : null,
              color: senkaPanelAlt,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 7 : 11,
                vertical: english ? 4 : 0,
              ),
              child: english
                  ? Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [titleText, ?trailing],
                    )
                  : Row(
                      children: [
                        Expanded(child: titleText),
                        ?trailing,
                      ],
                    ),
            ),
            if (fitContent) child else Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class SenkaLabelValue extends StatelessWidget {
  const SenkaLabelValue(
    this.label,
    this.value, {
    super.key,
    this.compact = false,
  });
  final String label;
  final String value;
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: senkaMuted,
            fontSize: compact ? 10 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Flexible(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: senkaText,
            fontSize: compact ? 11 : 14,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );
}
