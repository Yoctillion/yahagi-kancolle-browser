import 'package:flutter/material.dart';

import 'flat_style.dart';

/// 极简档（扁平面板）下的空态 / 同步中提示：11 号摘要灰、靠左，不居中留白。
class FlatEmptyText extends StatelessWidget {
  const FlatEmptyText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: const TextStyle(color: flatMutedColor, fontSize: flatRowFontSize),
    ),
  );
}
