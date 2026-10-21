import 'package:flutter/material.dart';

import 'flat_style.dart';

class FlatTextToggleOption {
  const FlatTextToggleOption({
    required this.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key key;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// 极简档（扁平面板）下的模式切换：纯文字，选中金色，无底色无边框。
/// 放不下时换行；放在标题行的 FittedBox 里则始终一行、整体缩小。
class FlatTextToggle extends StatelessWidget {
  const FlatTextToggle({super.key, required this.options});

  final List<FlatTextToggleOption> options;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final option in options)
          InkWell(
            key: option.key,
            onTap: option.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              child: Text(
                option.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: option.selected ? flatAccentColor : flatMutedColor,
                  fontSize: flatSmallFontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
