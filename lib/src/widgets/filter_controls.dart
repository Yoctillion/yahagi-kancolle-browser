import 'package:flutter/material.dart';
import 'app_segmented_style.dart';

class HeaderFilterIconButton extends StatelessWidget {
  const HeaderFilterIconButton({
    super.key,
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: IconButton(
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: active
            ? AppSegmentedStyle.selectedBackground(context)
            : AppSegmentedStyle.background(context),
        side: BorderSide(color: AppSegmentedStyle.border(context)),
      ),
      icon: Icon(
        icon,
        size: 18,
        color: AppSegmentedStyle.foreground(context, active),
      ),
    ),
  );
}

class CompactFilterChip extends StatelessWidget {
  const CompactFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 5, bottom: 3),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? AppSegmentedStyle.selectedBackground(context)
              : AppSegmentedStyle.background(context),
          border: Border.all(color: AppSegmentedStyle.border(context)),
          borderRadius: AppSegmentedStyle.itemRadius(compact: true),
        ),
        child: Text(
          label,
          style: AppSegmentedStyle.textStyle(
            context,
            selected: selected,
            compact: true,
            fontSize: 10.5,
          ),
        ),
      ),
    ),
  );
}
