// عمارتي — form controls + small widgets. Ported from ui2.jsx.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';
import 'primitives.dart';

/// Input formatters for numeric fields (real input filtering — the app had none,
/// so letters silently became a fallback number). [digitsOnly] = non-negative
/// integers; [decimal] = a non-negative decimal (e.g. an exchange rate).
final digitsOnly = [FilteringTextInputFormatter.digitsOnly];
final decimalOnly = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

/// Single-line labelled input.
class Field extends StatefulWidget {
  const Field({
    super.key,
    this.label,
    this.value = '',
    this.onChanged,
    this.placeholder,
    this.icon,
    this.hint,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.obscure = false,
    this.ltr = false,
    this.marginBottom = 14,
    this.maxLength,
  });
  final String? label;
  final String value;
  final ValueChanged<String>? onChanged;
  final String? placeholder;
  final String? icon;
  final String? hint;
  final String? suffix;
  final TextInputType? keyboardType;

  /// Real input filtering (e.g. [digitsOnly] / [decimalOnly]) — rejects letters.
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final bool ltr;
  final double marginBottom;
  final int? maxLength;

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();
  bool _foc = false;

  @override
  void initState() {
    super.initState();
    _f.addListener(() => setState(() => _foc = _f.hasFocus));
  }

  @override
  void didUpdateWidget(Field old) {
    super.didUpdateWidget(old);
    // Keep the controller in sync when the caller changes `value` (e.g. a total
    // recomputed from other inputs) WITHOUT losing focus/caret. Screens no
    // longer need the ValueKey-remount hack that dismissed the keyboard (#24).
    if (widget.value != old.value && widget.value != _c.text && !_f.hasFocus) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: widget.marginBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(widget.label!,
                  style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            ),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                  color: _foc ? AppColors.navy500 : AppColors.line2, width: 1.5),
              boxShadow: _foc
                  ? [BoxShadow(color: AppColors.navy100, blurRadius: 0, spreadRadius: 3)]
                  : AppShadows.xs,
            ),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  AppIcon(widget.icon!,
                      size: 19, color: _foc ? AppColors.navy600 : AppColors.ink400),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: TextField(
                    controller: _c,
                    focusNode: _f,
                    onChanged: widget.onChanged,
                    obscureText: widget.obscure,
                    keyboardType: widget.keyboardType,
                    inputFormatters: widget.inputFormatters,
                    maxLength: widget.maxLength,
                    // Hide the built-in counter; the fixed-height field has no room.
                    buildCounter: widget.maxLength == null
                        ? null
                        : (_, {required currentLength, maxLength, required isFocused}) => null,
                    textDirection: widget.ltr ? TextDirection.ltr : null,
                    style: AppType.base(
                        size: 15, weight: FontWeight.w600, color: AppColors.ink900),
                    cursorColor: AppColors.navy600,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: widget.placeholder,
                      hintStyle: AppType.base(
                          size: 15, weight: FontWeight.w500, color: AppColors.ink400),
                    ),
                  ),
                ),
                if (widget.suffix != null) ...[
                  const SizedBox(width: 9),
                  Text(widget.suffix!,
                      style: AppType.base(
                          size: 13, weight: FontWeight.w700, color: AppColors.ink400)),
                ],
              ],
            ),
          ),
          if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(widget.hint!,
                  style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink400)),
            ),
        ],
      ),
    );
  }
}

class AppTextArea extends StatelessWidget {
  const AppTextArea(
      {super.key, this.label, this.placeholder, this.rows = 3, this.onChanged, this.value});
  final String? label;
  final String? placeholder;
  final int rows;
  final ValueChanged<String>? onChanged;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(label!,
                  style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.line2, width: 1.5),
              boxShadow: AppShadows.xs,
            ),
            child: TextField(
              maxLines: rows,
              onChanged: onChanged,
              controller: value == null ? null : TextEditingController(text: value),
              style: AppType.base(size: 15, weight: FontWeight.w600, color: AppColors.ink900),
              cursorColor: AppColors.navy600,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: AppType.base(size: 15, weight: FontWeight.w500, color: AppColors.ink400),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SelectOption {
  const SelectOption(this.value, this.label);
  final Object value;
  final String label;
}

/// Tap-to-expand select. Options expand inline below the trigger.
class SelectField extends StatefulWidget {
  const SelectField({
    super.key,
    this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
  });
  final String? label;
  final Object? value;
  final List<SelectOption> options;
  final ValueChanged<Object> onChanged;
  final String? icon;

  @override
  State<SelectField> createState() => _SelectFieldState();
}

class _SelectFieldState extends State<SelectField> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cur = widget.options.where((o) => o.value == widget.value).cast<SelectOption?>().firstWhere((_) => true, orElse: () => null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(widget.label!,
                  style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            ),
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: _open ? AppColors.navy500 : AppColors.line2, width: 1.5),
                boxShadow: AppShadows.xs,
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    AppIcon(widget.icon!, size: 19, color: AppColors.ink400),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: Text(cur?.label ?? 'اختر…',
                        style: AppType.base(
                            size: 15,
                            weight: FontWeight.w600,
                            color: cur != null ? AppColors.ink900 : AppColors.ink400)),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: AppIcon('chevronDown', size: 18, color: AppColors.ink400),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: kEaseOut,
            child: _open
                ? Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                      boxShadow: AppShadows.lg,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: widget.options.map((o) {
                        final on = o.value == widget.value;
                        return InkWell(
                          onTap: () {
                            widget.onChanged(o.value);
                            setState(() => _open = false);
                          },
                          child: Container(
                            width: double.infinity,
                            color: on ? AppColors.navy50 : Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(o.label,
                                    style: AppType.base(
                                        size: 14.5,
                                        weight: FontWeight.w600,
                                        color: on ? AppColors.navy700 : AppColors.ink700)),
                                if (on) AppIcon('check', size: 17, color: AppColors.navy700),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class SegOption {
  const SegOption(this.value, this.label, {this.icon});
  final Object value;
  final String label;
  final String? icon;
}

class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.full = true,
    this.small = false,
  });
  final List<SegOption> options;
  final Object value;
  final ValueChanged<Object> onChanged;
  final bool full;
  final bool small;

  @override
  Widget build(BuildContext context) {
    Widget seg(SegOption o) {
      final on = o.value == value;
      final btn = GestureDetector(
        onTap: () => onChanged(o.value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: kEaseOut,
          padding: EdgeInsets.symmetric(vertical: small ? 7 : 9, horizontal: small ? 12 : 14),
          decoration: BoxDecoration(
            color: on ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: on ? AppShadows.sm : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (o.icon != null) ...[
                AppIcon(o.icon!, size: 16, color: on ? AppColors.navy700 : AppColors.ink500),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.base(
                        size: small ? 12.5 : 13.5,
                        weight: FontWeight.w700,
                        color: on ? AppColors.navy700 : AppColors.ink500)),
              ),
            ],
          ),
        ),
      );
      return full ? Expanded(child: btn) : btn;
    }

    final children = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 3));
      children.add(seg(options[i]));
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppColors.navy50, borderRadius: BorderRadius.circular(13)),
      child: Row(
          mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min, children: children),
    );
  }
}

class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.checked, required this.onChanged});
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!checked),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: checked ? AppColors.ok : AppColors.ink300,
            borderRadius: BorderRadius.circular(99)),
        alignment: checked ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
              color: Colors.white, shape: BoxShape.circle, boxShadow: AppShadows.sm),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 42, this.tone = 'navy', this.img});
  final String name;
  final double size;
  final String tone;
  final String? img;

  @override
  Widget build(BuildContext context) {
    if (img != null) {
      return ClipOval(
          child: Image.asset(img!, width: size, height: size, fit: BoxFit.cover));
    }
    final pair = {
      'navy': (AppColors.navy100, AppColors.navy700),
      'gold': (AppColors.gold100, AppColors.gold700),
      'ok': (AppColors.okBg, AppColors.ok700),
      'credit': (AppColors.creditBg, AppColors.credit700),
    }[tone] ?? (AppColors.navy100, AppColors.navy700);
    final words = name.trim().split(RegExp(r'\s+'));
    final initials = words.take(2).map((w) => w.isNotEmpty ? w[0] : '').join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: pair.$1, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials.isEmpty ? '؟' : initials,
          style: AppType.base(size: size * 0.38, weight: FontWeight.w800, color: pair.$2)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon = 'list', required this.title, this.sub});
  final String icon;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: AppColors.navy50, borderRadius: BorderRadius.circular(24)),
            alignment: Alignment.center,
            child: AppIcon(icon, size: 34, color: AppColors.navy300),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: AppType.base(size: 16, weight: FontWeight.w800, color: AppColors.ink700)),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(sub!,
                  textAlign: TextAlign.center,
                  style: AppType.base(size: 13, weight: FontWeight.w500, color: AppColors.ink500)),
            ),
        ],
      ),
    );
  }
}

/// Gold floating action button (pill with optional label).
class AppFab extends StatelessWidget {
  const AppFab({super.key, this.icon = 'plus', this.label, this.onTap});
  final String icon;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        height: 52,
        padding: EdgeInsets.symmetric(horizontal: label != null ? 20 : 0),
        width: label != null ? null : 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.gold500, AppColors.gold600]),
          borderRadius: BorderRadius.circular(99),
          boxShadow: AppShadows.gold,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 24, color: const Color(0xFF3A2F0C), stroke: 2.2),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(label!,
                  style: AppType.base(
                      size: 14.5, weight: FontWeight.w800, color: const Color(0xFF3A2F0C))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Why a form's submit button is disabled — spelled out, never left to guess.
///
/// A greyed-out button with no explanation is a dead end: the user sees the app
/// refusing them and has no idea what to fix. Every gated submit in the app pairs
/// its `disabled:` with one of these, listing exactly what is still missing.
class FormBlockedHint extends StatelessWidget {
  const FormBlockedHint({super.key, required this.reasons, this.title});

  /// The outstanding requirements, in the order the fields appear.
  final List<String> reasons;

  /// Overrides the default lead-in ("لإكمال الحفظ:").
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (reasons.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.lateBg,
        border: Border.all(color: AppColors.late.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AppIcon('alert', size: 15, color: AppColors.late700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title ?? (reasons.length == 1 ? 'لإكمال الحفظ:' : 'لإكمال الحفظ، أكمل ما يلي:'),
                    style: AppType.base(
                        size: 12, weight: FontWeight.w800, color: AppColors.late700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 21),
              child: Text('• $r',
                  style: AppType.base(
                      size: 11.5, weight: FontWeight.w600, color: AppColors.late700, height: 1.5)),
            ),
        ],
      ),
    );
  }
}
