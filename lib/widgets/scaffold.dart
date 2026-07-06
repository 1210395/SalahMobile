// عمارتي — screen scaffold, bottom-sheet shell, LTR number text.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'primitives.dart';

/// Numbers stay LTR + tabular even inside RTL flow (the prototype's `.num`).
class NumText extends StatelessWidget {
  const NumText(this.text, {super.key, required this.style, this.textAlign});
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(text, style: style, textAlign: textAlign),
    );
  }
}

/// Screen scaffold: header, scrollable body, optional bottom nav + FAB.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.header,
    required this.children,
    this.nav,
    this.fab,
    this.bg = AppColors.page,
    this.pad = true,
  });
  final Widget header;
  final List<Widget> children;
  final Widget? nav;
  final Widget? fab;
  final Color bg;
  final bool pad;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: SingleChildScrollView(
            padding: pad
                ? const EdgeInsets.fromLTRB(16, 16, 16, 26)
                : EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        ?nav,
      ],
    );

    if (fab == null) {
      return Container(color: bg, child: column);
    }
    return Container(
      color: bg,
      child: Stack(
        children: [
          Positioned.fill(child: column),
          Positioned(left: 18, bottom: 90 + bottomInset, child: fab!),
        ],
      ),
    );
  }
}

/// Bottom-sheet chrome: drag handle, optional titled header, scroll body,
/// optional sticky footer. Pass as the child of [showAppSheet].
class SheetShell extends StatelessWidget {
  const SheetShell({
    super.key,
    this.title,
    this.onClose,
    required this.children,
    this.footer,
  });
  final String? title;
  final VoidCallback? onClose;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Center(
                child: Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                      color: AppColors.line2, borderRadius: BorderRadius.circular(99)),
                ),
              ),
            ),
            if (title != null)
              Container(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title!,
                        style: AppType.base(size: 17, weight: FontWeight.w800)),
                    RoundBtn(icon: 'x', onTap: onClose ?? () => Navigator.of(context).pop()),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            if (footer != null)
              Container(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 16 + bottomInset),
                decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.line))),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Slide-up modal sheet matching the prototype's overlay styling.
Future<T?> showAppSheet<T>(BuildContext context, Widget child) {
  final h = MediaQuery.of(context).size.height;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x730F1028),
    constraints: BoxConstraints(maxHeight: h * 0.9),
    builder: (_) => child,
  );
}

/// A confirm bottom sheet for destructive/irreversible actions (e.g. sign out).
/// Shows a message with a cancel + confirm pair; [onConfirm] runs on confirm.
void showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required VoidCallback onConfirm,
  String cancelLabel = 'إلغاء',
  String confirmIcon = 'logout',
  bool danger = true,
}) {
  showAppSheet(
    context,
    Builder(
      builder: (sheetCtx) => SheetShell(
        title: title,
        footer: Row(
          children: [
            Expanded(
              child: AppButton(
                label: cancelLabel,
                variant: BtnVariant.outline,
                size: BtnSize.lg,
                full: true,
                onTap: () => Navigator.of(sheetCtx).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: confirmLabel,
                variant: danger ? BtnVariant.danger : BtnVariant.primary,
                size: BtnSize.lg,
                icon: confirmIcon,
                full: true,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onConfirm();
                },
              ),
            ),
          ],
        ),
        children: [
          Text(message,
              style: AppType.base(
                  size: 14, weight: FontWeight.w600, color: AppColors.ink600, height: 1.6)),
          const SizedBox(height: 4),
        ],
      ),
    ),
  );
}
