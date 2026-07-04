// عمارتي — core UI primitives (RTL). Ported from ui.jsx.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';

/// (background, foreground) for a tonal color name.
({Color bg, Color fg}) toneColors(String tone) {
  switch (tone) {
    case 'gold':
      return (bg: AppColors.gold100, fg: AppColors.gold700);
    case 'ok':
      return (bg: AppColors.okBg, fg: AppColors.ok700);
    case 'late':
      return (bg: AppColors.lateBg, fg: AppColors.late700);
    case 'credit':
      return (bg: AppColors.creditBg, fg: AppColors.credit700);
    case 'warn':
      return (bg: AppColors.warnBg, fg: AppColors.gold700);
    case 'neutral':
      return (bg: AppColors.page, fg: AppColors.ink600);
    case 'navy':
    default:
      return (bg: AppColors.navy50, fg: AppColors.navy700);
  }
}

/// Diagonal brand gradient (≈155deg light→dark).
LinearGradient appGradient(List<Color> colors) => LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: colors,
    );

/// Press-to-shrink wrapper used across tappable primitives.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.enabled = true,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    return GestureDetector(
      onTap: active ? widget.onTap : null,
      onTapDown: active ? (_) => setState(() => _down = true) : null,
      onTapUp: active ? (_) => setState(() => _down = false) : null,
      onTapCancel: active ? () => setState(() => _down = false) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: kEaseOut,
        child: widget.child,
      ),
    );
  }
}

/// Lay [children] out in equal-width columns, [n] per row.
Widget gridRows(List<Widget> children, {int n = 3, double gap = 10}) {
  final rows = <Widget>[];
  for (var i = 0; i < children.length; i += n) {
    final slice = children.sublist(i, (i + n).clamp(0, children.length));
    final cells = <Widget>[];
    for (var j = 0; j < n; j++) {
      if (j > 0) cells.add(SizedBox(width: gap));
      cells.add(Expanded(child: j < slice.length ? slice[j] : const SizedBox()));
    }
    if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
    rows.add(IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
    ));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
}

/// Faint olive-branch / building motif behind accent headers.
class BranchMotif extends StatelessWidget {
  const BranchMotif({super.key});
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -18,
      right: -10,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.07,
          child: SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(painter: _BranchPainter()),
          ),
        ),
      ),
    );
  }
}

class _BranchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 120;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(30 * s, 110 * s)
      ..lineTo(30 * s, 40 * s)
      ..lineTo(60 * s, 25 * s)
      ..lineTo(90 * s, 40 * s)
      ..lineTo(90 * s, 110 * s);
    canvas.drawPath(path, stroke);
    final dot = Paint()..color = Colors.white;
    for (final p in [
      Offset(45 * s, 60 * s),
      Offset(75 * s, 60 * s),
      Offset(45 * s, 80 * s),
      Offset(75 * s, 80 * s),
    ]) {
      canvas.drawCircle(p, 3 * s, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Round 40×40 icon button (header chrome).
class RoundBtn extends StatelessWidget {
  const RoundBtn({
    super.key,
    required this.icon,
    this.onTap,
    this.dark = false,
    this.badge = false,
  });
  final String icon;
  final VoidCallback? onTap;
  final bool dark;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: dark ? Colors.white.withValues(alpha: 0.12) : AppColors.navy50,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AppIcon(icon, size: 21, color: dark ? Colors.white : AppColors.navy700),
            if (badge)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.late,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: dark ? AppColors.navy700 : Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Screen header — accent (navy gradient) or plain (white) variant.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    this.title,
    this.subtitle,
    this.onBack,
    this.right,
    this.accent = false,
    this.logo = false,
  });
  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? right;
  final bool accent;
  final bool logo;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final overlay = accent
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent);

    final children = <Widget>[
      if (onBack != null) ...[
        RoundBtn(icon: 'chevronR', dark: accent, onTap: onBack),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: logo
            ? Align(
                alignment: Alignment.centerRight,
                child: Image.asset('assets/images/logo-light.png', height: 42),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title ?? '',
                    style: AppType.base(
                      size: accent ? 21 : 19,
                      weight: FontWeight.w800,
                      color: accent ? Colors.white : AppColors.ink900,
                      height: 1.25,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: AppType.base(
                          size: 12.5,
                          weight: FontWeight.w500,
                          color: accent ? AppColors.gold400 : AppColors.ink500,
                        ),
                      ),
                    ),
                ],
              ),
      ),
      if (right != null) ...[const SizedBox(width: 10), right!],
    ];

    final bar = Padding(
      padding: EdgeInsets.fromLTRB(accent ? 18 : 16, topInset + 14, 16,
          accent ? 18 : 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
      ),
    );

    final decorated = accent
        ? Container(
            decoration: BoxDecoration(
              gradient: appGradient(
                  [AppColors.navy700, AppColors.navy800, AppColors.navy900]),
            ),
            // The building/dots motif is removed from the navy background per
            // client feedback — plain gradient only.
            child: bar,
          )
        : Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: bar,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(value: overlay, child: decorated);
  }
}

/// A navigation tab descriptor.
class NavTab {
  const NavTab({
    required this.id,
    required this.label,
    required this.icon,
    this.fillOnActive = false,
    this.badge = false,
  });
  final String id;
  final String label;
  final String icon;
  final bool fillOnActive;
  final bool badge;
}

class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.tabs,
    required this.active,
    required this.onChange,
  });
  final List<NavTab> tabs;
  final String? active;
  final void Function(String) onChange;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(color: Color(0x0D14163A), offset: Offset(0, -4), blurRadius: 18),
        ],
      ),
      padding: EdgeInsets.fromLTRB(6, 8, 6, 10 + bottomInset),
      child: Row(
        children: tabs.map((t) {
          final on = t.id == active;
          final color = on ? AppColors.navy700 : AppColors.ink400;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChange(t.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: kEaseOut,
                      width: 50,
                      height: 30,
                      decoration: BoxDecoration(
                        color: on ? AppColors.navy50 : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AppIcon(t.icon,
                              size: 22,
                              color: color,
                              stroke: on ? 2 : 1.75,
                              fill: on && t.fillOnActive),
                          if (t.badge)
                            Positioned(
                              top: 2,
                              right: 10,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                    color: AppColors.late, shape: BoxShape.circle),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.label,
                      style: AppType.base(
                          size: 10.5,
                          weight: on ? FontWeight.w700 : FontWeight.w600,
                          color: color),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Standard white card.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.pad = 16,
    this.raised = false,
    this.color,
    this.borderColor,
    this.radius = AppRadii.md,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double pad;
  final bool raised;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        border: Border.all(color: borderColor ?? AppColors.line),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: raised ? AppShadows.md : AppShadows.sm,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, scale: 0.985, child: card);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.text,
    this.action,
    this.onAction,
    this.margin = const EdgeInsets.fromLTRB(2, 4, 2, 10),
  });
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text,
              style: AppType.base(size: 15, weight: FontWeight.w800, color: AppColors.ink900)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!,
                      style: AppType.base(
                          size: 12.5, weight: FontWeight.w700, color: AppColors.navy600)),
                  const AppIcon('chevronL', size: 15, color: AppColors.navy600),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum BtnVariant { primary, gold, outline, ghost, danger, white }

enum BtnSize { sm, md, lg }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = BtnVariant.primary,
    this.size = BtnSize.md,
    this.icon,
    this.iconRight,
    this.full = false,
    this.disabled = false,
  });
  final String label;
  final VoidCallback? onTap;
  final BtnVariant variant;
  final BtnSize size;
  final String? icon;
  final String? iconRight;
  final bool full;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final (height, fs, padX, radius) = switch (size) {
      BtnSize.sm => (38.0, 13.5, 14.0, 11.0),
      BtnSize.md => (50.0, 15.5, 20.0, 15.0),
      BtnSize.lg => (56.0, 16.5, 22.0, 16.0),
    };

    Color fg;
    BoxDecoration deco;
    switch (variant) {
      case BtnVariant.primary:
        fg = Colors.white;
        deco = BoxDecoration(
            color: AppColors.navy700,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: AppShadows.navy);
      case BtnVariant.gold:
        fg = const Color(0xFF3A2F0C);
        deco = BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.gold500, AppColors.gold600]),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: AppShadows.gold);
      case BtnVariant.outline:
        fg = AppColors.navy700;
        deco = BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.navy100, width: 1.5),
            borderRadius: BorderRadius.circular(radius));
      case BtnVariant.ghost:
        fg = AppColors.navy700;
        deco = BoxDecoration(
            color: AppColors.navy50, borderRadius: BorderRadius.circular(radius));
      case BtnVariant.danger:
        fg = AppColors.late700;
        deco = BoxDecoration(
            color: AppColors.lateBg, borderRadius: BorderRadius.circular(radius));
      case BtnVariant.white:
        fg = AppColors.navy700;
        deco = BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: AppShadows.sm);
    }

    final iconSize = size == BtnSize.sm ? 17.0 : 19.0;
    final content = Row(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[AppIcon(icon!, size: iconSize, color: fg), const SizedBox(width: 8)],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.base(size: fs, weight: FontWeight.w700, color: fg)),
        ),
        if (iconRight != null) ...[const SizedBox(width: 8), AppIcon(iconRight!, size: iconSize, color: fg)],
      ],
    );

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Pressable(
        enabled: !disabled,
        onTap: onTap,
        child: Container(
          height: height,
          width: full ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: padX),
          decoration: deco,
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = 'navy',
    this.icon,
    this.small = false,
  });
  final String label;
  final String tone;
  final String? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Container(
      padding: small
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[AppIcon(icon!, size: 13, color: c.fg), const SizedBox(width: 4)],
          Text(label,
              style: AppType.base(
                  size: small ? 11 : 12, weight: FontWeight.w700, color: c.fg)),
        ],
      ),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.tone});
  final String tone;
  @override
  Widget build(BuildContext context) {
    final c = {
      'ok': AppColors.ok,
      'late': AppColors.late,
      'credit': AppColors.credit,
      'warn': AppColors.warn,
    }[tone] ?? AppColors.ink400;
    return Container(
        width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }
}

class IconChip extends StatelessWidget {
  const IconChip({
    super.key,
    required this.icon,
    this.tone = 'navy',
    this.size = 44,
    this.iconSize,
  });
  final String icon;
  final String tone;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(size * 0.32)),
      alignment: Alignment.center,
      child: AppIcon(icon, size: iconSize ?? size * 0.5, color: c.fg),
    );
  }
}

class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.sub,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.dividerBelow = false,
  });
  final Widget? leading;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool dividerBelow;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.base(
                        size: 14.5, weight: FontWeight.w700, color: AppColors.ink900)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub!,
                        style: AppType.base(
                            size: 12, weight: FontWeight.w500, color: AppColors.ink500)),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (chevron) ...[
            const SizedBox(width: 6),
            const AppIcon('chevronL', size: 18, color: AppColors.ink300),
          ],
        ],
      ),
    );

    final body = dividerBelow
        ? DecoratedBox(
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line))),
            child: row,
          )
        : row;

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: body,
      ),
    );
  }
}
