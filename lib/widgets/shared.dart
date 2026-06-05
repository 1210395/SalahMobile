// عمارتي — shared screen building blocks used across multiple screens.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';
import 'primitives.dart';
import 'scaffold.dart';

/// Status pill metadata for a unit status.
class StatusMeta {
  const StatusMeta(this.tone, this.label, this.hasDot);
  final String tone;
  final String label;
  final bool hasDot;
}

const Map<String, StatusMeta> kStatusMap = {
  'ok': StatusMeta('ok', 'مسدد', true),
  'late': StatusMeta('late', 'متأخر', true),
  'credit': StatusMeta('credit', 'رصيد دائن', true),
  'vacant': StatusMeta('neutral', 'شاغر', false),
};

/// Compact KPI card.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.trend,
  });
  final String label;
  final String value;
  final String icon;
  final String tone;
  final int? trend;

  @override
  Widget build(BuildContext context) {
    final pair = _statTones[tone] ?? _statTones['navy']!;
    return AppCard(
      pad: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: pair.$1, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: AppIcon(icon, size: 18, color: pair.$2),
              ),
              if (trend != null)
                NumText('${trend! > 0 ? '+' : ''}$trend%',
                    style: AppType.num(
                        size: 11,
                        weight: FontWeight.w700,
                        color: trend! > 0 ? AppColors.ok700 : AppColors.late700)),
            ],
          ),
          const SizedBox(height: 10),
          NumText(value, style: AppType.num(size: 19, weight: FontWeight.w800, color: AppColors.ink900)),
          const SizedBox(height: 1),
          Text(label,
              style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.ink500)),
        ],
      ),
    );
  }
}

const Map<String, (Color, Color)> _statTones = {
  'navy': (AppColors.navy50, AppColors.navy700),
  'gold': (AppColors.gold100, AppColors.gold700),
  'late': (AppColors.lateBg, AppColors.late700),
  'ok': (AppColors.okBg, AppColors.ok700),
  'credit': (AppColors.creditBg, AppColors.credit700),
};

/// Tile for quick-action grids.
class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.label,
    required this.sub,
    required this.icon,
    required this.tone,
    this.badge,
    this.onTap,
  });
  final String label;
  final String sub;
  final String icon;
  final String tone;
  final int? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pair = _statTones[tone] ?? _statTones['navy']!;
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: AppShadows.sm,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: pair.$1, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: AppIcon(icon, size: 23, color: pair.$2),
                ),
                const SizedBox(height: 9),
                Text(label,
                    textAlign: TextAlign.center,
                    style: AppType.base(size: 13, weight: FontWeight.w800, color: AppColors.ink900)),
                const SizedBox(height: 2),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: AppType.base(size: 10.5, weight: FontWeight.w500, color: AppColors.ink500)),
              ],
            ),
            if (badge != null)
              Positioned(
                top: -4,
                left: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                      color: AppColors.late, borderRadius: BorderRadius.circular(99)),
                  alignment: Alignment.center,
                  child: NumText('$badge',
                      style: AppType.num(size: 10.5, weight: FontWeight.w800, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small framed stat used inside worker/parking cards.
class MiniStat extends StatelessWidget {
  const MiniStat({
    super.key,
    required this.label,
    required this.value,
    this.tone = 'navy',
    this.num = false,
  });
  final String label;
  final String value;
  final String tone;
  final bool num;

  @override
  Widget build(BuildContext context) {
    final c = {
      'navy': AppColors.navy700,
      'ok': AppColors.ok700,
      'late': AppColors.late700,
      'gold': AppColors.gold700,
    }[tone]!;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          children: [
            num
                ? NumText(value, style: AppType.num(size: 13, weight: FontWeight.w800, color: c))
                : Text(value,
                    style: AppType.base(size: 13, weight: FontWeight.w800, color: c)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: AppType.base(size: 10, weight: FontWeight.w600, color: AppColors.ink500)),
          ],
        ),
      ),
    );
  }
}

/// A 2-column grid of labelled detail fields (used in sheets/reports).
class DetailRow {
  const DetailRow(this.icon, this.label, this.value, {this.tone, this.ltr = false});
  final String icon;
  final String label;
  final String value;
  final String? tone; // late | credit | ok
  final bool ltr;
}

class DetailGrid extends StatelessWidget {
  const DetailGrid({super.key, required this.rows});
  final List<DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    Color valueColor(String? tone) => {
          'late': AppColors.late700,
          'credit': AppColors.credit700,
          'ok': AppColors.ok700,
        }[tone] ?? AppColors.ink900;

    Widget cell(DetailRow r) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppIcon(r.icon, size: 15, color: AppColors.ink500),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(r.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.base(
                            size: 11.5, weight: FontWeight.w600, color: AppColors.ink500)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              r.ltr
                  ? NumText(r.value,
                      style: AppType.num(size: 14, weight: FontWeight.w800, color: valueColor(r.tone)))
                  : Text(r.value,
                      style: AppType.base(size: 14, weight: FontWeight.w800, color: valueColor(r.tone))),
            ],
          ),
        );

    final widgets = rows.map(cell).toList();
    return gridRows(widgets, n: 2, gap: 10);
  }
}

/// Full-width dark/gradient stat banner used atop several screens.
class HeroBanner extends StatelessWidget {
  const HeroBanner({
    super.key,
    required this.child,
    this.gradient,
    this.color,
    this.borderColor,
    this.shadow = AppShadows.navy,
    this.radius = AppRadii.lg,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final List<Color>? gradient;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow> shadow;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient != null ? appGradient(gradient!) : null,
        color: color,
        border: borderColor != null ? Border.all(color: borderColor!) : null,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}
