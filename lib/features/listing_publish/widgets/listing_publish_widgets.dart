import 'package:flutter/material.dart';

import '../../../core/app_typography.dart';

const Color _primaryText = Color(0xFF0B0B0B);
const Color _secondaryText = Color(0xFF8F8F94);
const Color _divider = Color(0xFFE7E7EA);
const Color _disabledButton = Color(0xFFC7C7CC);

/// Header shared by the steps of the listing publication flow.
///
/// [currentStep] is one-based. Safe-area padding is intentionally left to the
/// screen so this widget can be used both in a page and inside a dialog.
class ListingStepHeader extends StatelessWidget {
  const ListingStepHeader({
    super.key,
    required this.title,
    required this.currentStep,
    required this.totalSteps,
    this.subtitle,
    this.onBack,
    this.onClose,
    this.padding = const EdgeInsets.fromLTRB(18, 10, 18, 14),
  }) : assert(currentStep > 0),
       assert(totalSteps > 0),
       assert(currentStep <= totalSteps);

  final String title;
  final String? subtitle;
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final progress = currentStep / totalSteps;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                _HeaderAction(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Назад',
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 16,
                      fontWeight: AppTypography.medium,
                      color: _primaryText,
                      height: 1.1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                _HeaderAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Закрыть',
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text(
                'Шаг $currentStep из $totalSteps',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11.5,
                  fontWeight: AppTypography.medium,
                  color: _secondaryText,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11.5,
                      fontWeight: AppTypography.medium,
                      color: _secondaryText,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              color: const Color(0xFF070707),
              backgroundColor: _divider,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox(width: 40, height: 40);

    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 22,
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: _primaryText),
      ),
    );
  }
}

/// Primary action intended for a screen's bottom navigation area.
class ListingPrimaryBottomButton extends StatelessWidget {
  const ListingPrimaryBottomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.padding = const EdgeInsets.fromLTRB(18, 12, 18, 12),
    this.showTopDivider = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final EdgeInsets padding;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isLoading;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: showTopDivider
            ? const Border(top: BorderSide(color: _divider))
            : null,
      ),
      child: SafeArea(
        top: false,
        minimum: padding,
        child: Semantics(
          button: true,
          enabled: isEnabled,
          label: label,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: Material(
              color: isEnabled ? Colors.black : _disabledButton,
              borderRadius: BorderRadius.circular(25),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isEnabled ? onPressed : null,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            fontWeight: AppTypography.semiBold,
                            color: Colors.white,
                            height: 1,
                            letterSpacing: 0,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable row for category, characteristic and delivery selections.
class ListingSelectionRow extends StatelessWidget {
  const ListingSelectionRow({
    super.key,
    required this.label,
    required this.onTap,
    this.value,
    this.valueWidget,
    this.placeholder = 'Выберите',
    this.status,
    this.leading,
    this.enabled = true,
    this.isRequired = false,
    this.showDivider = true,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final String placeholder;
  final Widget? status;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isRequired;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final resolvedValue = value?.trim();
    final hasValue =
        valueWidget != null ||
        (resolvedValue != null && resolvedValue.isNotEmpty);
    final canTap = enabled && onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canTap ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(bottom: BorderSide(color: _divider))
                : null,
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: label,
                        children: [
                          if (isRequired)
                            const TextSpan(
                              text: ' *',
                              style: TextStyle(
                                color: Color(0xFFE11D2E),
                                fontWeight: AppTypography.bold,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        fontWeight: AppTypography.semiBold,
                        color: enabled ? _primaryText : _secondaryText,
                        height: 1.1,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (valueWidget != null)
                      valueWidget!
                    else
                      Text(
                        hasValue ? resolvedValue! : placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12.5,
                          fontWeight: AppTypography.medium,
                          color: hasValue && enabled
                              ? const Color(0xFF111111)
                              : _secondaryText,
                          height: 1.1,
                          letterSpacing: 0,
                        ),
                      ),
                  ],
                ),
              ),
              if (status != null) ...[const SizedBox(width: 10), status!],
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: enabled ? const Color(0xFFC7C7CC) : _divider,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ListingAnalysisBadgeTone { neutral, processing, completed }

/// Compact, non-technical status used for image analysis and low-confidence
/// predictions. It deliberately never displays confidence percentages.
class ListingAnalysisStatusBadge extends StatelessWidget {
  const ListingAnalysisStatusBadge({
    super.key,
    required this.label,
    this.tone = ListingAnalysisBadgeTone.neutral,
  });

  const ListingAnalysisStatusBadge.processing({
    super.key,
    this.label = 'Анализируем фотографии',
  }) : tone = ListingAnalysisBadgeTone.processing;

  const ListingAnalysisStatusBadge.needsReview({
    super.key,
    this.label = 'Нужно проверить',
  }) : tone = ListingAnalysisBadgeTone.neutral;

  const ListingAnalysisStatusBadge.completed({
    super.key,
    this.label = 'Характеристики определены',
  }) : tone = ListingAnalysisBadgeTone.completed;

  final String label;
  final ListingAnalysisBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      ListingAnalysisBadgeTone.neutral => (
        const Color(0xFFF2F2F4),
        const Color(0xFF706E82),
      ),
      ListingAnalysisBadgeTone.processing => (
        const Color(0xFFF2F2F4),
        const Color(0xFF111111),
      ),
      ListingAnalysisBadgeTone.completed => (
        const Color(0xFFEDF4EF),
        const Color(0xFF42624C),
      ),
    };

    return Semantics(
      label: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tone == ListingAnalysisBadgeTone.processing) ...[
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 6),
            ] else if (tone == ListingAnalysisBadgeTone.completed) ...[
              Icon(Icons.check_rounded, size: 13, color: foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 10.5,
                  fontWeight: AppTypography.medium,
                  color: foreground,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
