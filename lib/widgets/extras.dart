// سكن برو — shared extras added in the redesign pass: a calendar date field, a
// branded QR box, a full-screen QR scanner, and WhatsApp sharing. Centralised
// here so every screen uses one consistent implementation (and one set of
// dependencies). Exported via `common.dart`.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/tokens.dart';
import 'app_icon.dart';

/// Open a Material date picker (RTL, brand-tinted) and return the chosen date
/// as an ISO "yyyy-MM-dd" string, or null if dismissed.
Future<String?> pickDate(BuildContext context, {String? initialIso}) async {
  var initial = DateTime.now();
  if (initialIso != null && initialIso.trim().isNotEmpty) {
    initial = DateTime.tryParse(initialIso) ?? initial;
  }
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(initial.year - 8),
    lastDate: DateTime(initial.year + 8),
    builder: (ctx, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
              primary: AppColors.brand700, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    ),
  );
  if (picked == null) return null;
  final m = picked.month.toString().padLeft(2, '0');
  final d = picked.day.toString().padLeft(2, '0');
  return '${picked.year}-$m-$d';
}

/// Today's date as an ISO "yyyy-MM-dd" string (default for new payment dates).
String todayIso() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Tappable, labelled date field that opens [pickDate]. Mirrors [Field]'s look.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    this.label,
    required this.value,
    required this.onChanged,
    this.placeholder = 'اختر التاريخ',
    this.enabled = true,
    this.marginBottom = 14,
  });
  final String? label;
  final String value; // ISO date or ''
  final ValueChanged<String> onChanged;
  final String placeholder;
  final bool enabled;
  final double marginBottom;

  @override
  Widget build(BuildContext context) {
    final has = value.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: marginBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(label!,
                  style: AppType.base(
                      size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            ),
          GestureDetector(
            onTap: !enabled
                ? null
                : () async {
                    final r = await pickDate(context, initialIso: has ? value : null);
                    if (r != null) onChanged(r);
                  },
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: enabled ? AppColors.surface : AppColors.brand50,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.line2, width: 1.5),
                boxShadow: AppShadows.xs,
              ),
              child: Row(
                children: [
                  AppIcon('calendar', size: 19, color: AppColors.ink400),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(has ? value : placeholder,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                        style: AppType.base(
                            size: 15,
                            weight: FontWeight.w600,
                            color: has ? AppColors.ink900 : AppColors.ink400)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders [data] as a QR code inside a white brand frame.
class QrBox extends StatelessWidget {
  const QrBox({super.key, required this.data, this.size = 200});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.line2),
        boxShadow: AppShadows.sm,
      ),
      child: QrImageView(
        data: data,
        size: size,
        version: QrVersions.auto,
        backgroundColor: Colors.white,
        eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square, color: AppColors.brand700),
        dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square, color: AppColors.brand800),
      ),
    );
  }
}

/// Open a full-screen QR scanner and return the first decoded string, or null.
/// The scanner widget is only ever built inside this pushed route, so it never
/// touches the camera method-channel during widget tests.
Future<String?> scanQr(BuildContext context) {
  return Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const _ScanScreen(),
  ));
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();
  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: AppColors.brand900,
          foregroundColor: Colors.white,
          title: Text('مسح رمز QR',
              style: AppType.base(
                  size: 16, weight: FontWeight.w800, color: Colors.white)),
        ),
        body: MobileScanner(controller: _controller, onDetect: _onDetect),
      ),
    );
  }
}

/// Share [text] to WhatsApp. With [phone], opens a direct chat
/// (`wa.me/<digits>`); otherwise opens the WhatsApp share sheet. Falls back to
/// the system share sheet when WhatsApp can't be launched.
Future<void> shareViaWhatsApp({String? phone, required String text}) async {
  final digits = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  final enc = Uri.encodeComponent(text);
  final uri = Uri.parse(
      digits.isNotEmpty ? 'https://wa.me/$digits?text=$enc' : 'https://wa.me/?text=$enc');
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {/* fall through to the system share sheet */}
  await Share.share(text);
}
