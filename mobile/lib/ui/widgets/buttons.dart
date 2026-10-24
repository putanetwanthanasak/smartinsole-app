import 'package:flutter/material.dart';

import '../theme/dimens.dart';

/// Full-width primary button (DESIGN-SPEC §5): height 56, radius 16,
/// `primary` fill, white 18/700, optional 24 px icon. Styling comes from
/// the theme's `filledButtonTheme`.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      child: _ButtonLabel(label: label, icon: icon),
    );
  }
}

/// Full-width secondary button: white, `outline` 1.5 px, `ink` 18/700.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: _ButtonLabel(label: label, icon: icon),
    );
  }
}

/// Icon + label that wraps instead of clipping at large text.
class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimens.tightGap),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: Dimens.iconButtonIcon),
            const SizedBox(width: Dimens.tightGap),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}
