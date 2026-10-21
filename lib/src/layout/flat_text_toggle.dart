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

/// 极简档（扁平面板）下模块头部的模式切换：纯文字，选中金色，无底色无边框。
class FlatTextToggle extends StatelessWidget {
  const FlatTextToggle({super.key, required this.options});

  final List<FlatTextToggleOption> options;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          InkWell(
            key: option.key,
            onTap: option.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              child: Text(
                option.label,
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
