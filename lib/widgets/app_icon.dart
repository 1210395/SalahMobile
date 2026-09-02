// عمارتي — icon set. Exact SVG path data from the prototype's icons.jsx,
// rendered through flutter_svg. 1.75 stroke, rounded caps, currentColor.

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

/// Inner SVG markup for each named icon (viewBox 0 0 24 24).
const Map<String, String> kIconPaths = {
  'home':
      '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V20a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9.5"/><path d="M9.5 21v-6h5v6"/>',
  'building':
      '<rect x="4" y="3" width="16" height="18" rx="1.5"/><path d="M9 7h0M15 7h0M9 11h0M15 11h0M9 15h0M15 15h0"/><path d="M10.5 21v-3h3v3"/>',
  'building2':
      '<path d="M5 21V6l7-3 7 3v15"/><path d="M3 21h18"/><path d="M9 9h0M15 9h0M9 13h0M15 13h0M11 21v-4h2v4"/>',
  'store':
      '<path d="M4 9.5 5 4h14l1 5.5"/><path d="M4 9.5a2.5 2.5 0 0 0 5 0 2.5 2.5 0 0 0 5 0 2.5 2.5 0 0 0 5 0"/><path d="M5 11v9h14v-9"/><path d="M9 20v-5h4v5"/>',
  'wallet':
      '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H18a1 1 0 0 1 1 1v1.5"/><rect x="3" y="7.5" width="18" height="12" rx="2.5"/><path d="M16 13h0.01"/><path d="M21 11h-4a2 2 0 0 0 0 4h4"/>',
  'receipt':
      '<path d="M5 21V4a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v17l-2.5-1.5L14 21l-2-1.5L10 21l-2.5-1.5L5 21Z"/><path d="M9 8h6M9 12h6"/>',
  'expense':
      '<path d="M12 3v18"/><path d="M17 6H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',
  'chart':
      '<path d="M4 4v16h16"/><rect x="7" y="11" width="3" height="6" rx="0.6"/><rect x="12.5" y="8" width="3" height="9" rx="0.6"/><rect x="18" y="13" width="3" height="4" rx="0.6" transform="translate(-2 0)"/>',
  'pie':
      '<path d="M12 3a9 9 0 1 0 9 9h-9Z"/><path d="M12 3v9h9A9 9 0 0 0 12 3Z"/>',
  'grid':
      '<rect x="3.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.5"/>',
  'bell':
      '<path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6Z"/><path d="M10 19a2 2 0 0 0 4 0"/>',
  'megaphone':
      '<path d="M3 11v2a1 1 0 0 0 1 1h2l9 5V5L6 10H4a1 1 0 0 0-1 1Z"/><path d="M18 8a4 4 0 0 1 0 8"/>',
  'user': '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  'users':
      '<circle cx="9" cy="8" r="3.4"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 5.2a3.4 3.4 0 0 1 0 6.6"/><path d="M17.5 14.2A6.5 6.5 0 0 1 21.5 20"/>',
  'settings':
      '<circle cx="12" cy="12" r="3"/><path d="M19.4 13.5a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H10a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V10a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1Z"/>',
  'elevator':
      '<rect x="5" y="3" width="14" height="18" rx="1.5"/><path d="M12 3v18"/><path d="M9 9 7.5 11h3L9 9ZM15 15l1.5-2h-3l1.5 2Z"/>',
  'parking':
      '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M9.5 16V8h3a2.5 2.5 0 0 1 0 5h-3"/>',
  'wrench':
      '<path d="M14.5 6.5a3.5 3.5 0 0 0-4.6 4.3l-5.7 5.7a1.6 1.6 0 0 0 2.3 2.3l5.7-5.7a3.5 3.5 0 0 0 4.3-4.6l-2 2-1.7-.3-.3-1.7 2-2Z"/>',
  'broom':
      '<path d="M14 3 9 10"/><path d="M19 8 9 16"/><path d="M9 16s-3 .5-4.5 2.5C3 20.5 4 21 4 21s3-1 5-1 4 1 4 1 1-1 .5-2.5C12.5 16.5 9 16 9 16Z"/>',
  'shield':
      '<path d="M12 3 5 6v5c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6l-7-3Z"/><path d="M9.5 12l1.8 1.8L15 10"/>',
  'key':
      '<circle cx="7.5" cy="15.5" r="3.5"/><path d="M10 13 20 3"/><path d="M16.5 6.5 19 9M14 9l2 2"/>',
  'phone':
      '<path d="M5 4h3l1.5 4-2 1.5a11 11 0 0 0 5 5l1.5-2 4 1.5v3a2 2 0 0 1-2 2A15 15 0 0 1 3 6a2 2 0 0 1 2-2Z"/>',
  'whatsapp':
      '<path d="M12 3a9 9 0 0 0-7.7 13.6L3 21l4.5-1.2A9 9 0 1 0 12 3Z"/><path d="M8.5 8.5c0 4 3 6.5 6.5 6.5l-1.5-1.5-1.5.6a5 5 0 0 1-3.2-3.2l.6-1.5L8.5 8.5Z" fill="currentColor" stroke="none"/>',
  'qr':
      '<rect x="3.5" y="3.5" width="7" height="7" rx="1"/><rect x="13.5" y="3.5" width="7" height="7" rx="1"/><rect x="3.5" y="13.5" width="7" height="7" rx="1"/><path d="M14 14h2v2M20 14v.01M14 20h.01M18 18h.01M20 20v-2M17 17v0"/>',
  'search': '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/>',
  'filter': '<path d="M3 5h18l-7 8v6l-4-2v-4L3 5Z"/>',
  'calendar':
      '<rect x="3.5" y="5" width="17" height="16" rx="2.5"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/>',
  'download': '<path d="M12 4v11"/><path d="m8 11 4 4 4-4"/><path d="M5 20h14"/>',
  'check': '<path d="m5 12.5 4.5 4.5L19 7"/>',
  'checkCircle':
      '<circle cx="12" cy="12" r="9"/><path d="m8.5 12 2.3 2.3L15.5 9.5"/>',
  'xCircle': '<circle cx="12" cy="12" r="9"/><path d="m9 9 6 6M15 9l-6 6"/>',
  'x': '<path d="M6 6l12 12M18 6 6 18"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'chevronL': '<path d="M15 5 8 12l7 7"/>',
  'chevronR': '<path d="M9 5l7 7-7 7"/>',
  'chevronDown': '<path d="m6 9 6 6 6-6"/>',
  'arrowL': '<path d="M19 12H5"/><path d="m11 6-6 6 6 6"/>',
  'logout':
      '<path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/><path d="M10 12h10"/><path d="m7 8-4 4 4 4"/>',
  'eye':
      '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
  'edit':
      '<path d="M4 20h4L18.5 9.5a2 2 0 0 0-2.8-2.8L5 17.2V20Z"/><path d="m14 8 2.8 2.8"/>',
  'trash':
      '<path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13"/>',
  'dollar':
      '<path d="M12 2v20"/><path d="M17 6.5C17 4.6 14.8 3.5 12 3.5S7 4.8 7 6.8c0 4.7 10 2.4 10 7.2 0 2-2.2 3.5-5 3.5s-5-1.3-5-3.2"/>',
  'lock':
      '<rect x="4.5" y="10" width="15" height="11" rx="2.5"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  'mail':
      '<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m4 7 8 5.5L20 7"/>',
  'camera':
      '<path d="M4 8.5A1.5 1.5 0 0 1 5.5 7H8l1.5-2h5L16 7h2.5A1.5 1.5 0 0 1 20 8.5V18a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18V8.5Z"/><circle cx="12" cy="12.5" r="3.2"/>',
  'pin':
      '<path d="M12 21s7-6.3 7-12a7 7 0 1 0-14 0c0 5.7 7 12 7 12Z"/><circle cx="12" cy="9" r="2.5"/>',
  'clock': '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  // The dark/light switch in the header shows the skin you would GET.
  'sun':
      '<circle cx="12" cy="12" r="4.2"/><path d="M12 2.5v2.2M12 19.3v2.2M4.2 4.2l1.6 1.6"/>'
      '<path d="M18.2 18.2l1.6 1.6M2.5 12h2.2M19.3 12h2.2M4.2 19.8l1.6-1.6M18.2 5.8l1.6-1.6"/>',
  'moon': '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"/>',
  'alert': '<path d="M12 4 2.5 20h19L12 4Z"/><path d="M12 10v4M12 17h.01"/>',
  'file':
      '<path d="M6 3h8l5 5v12a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z"/><path d="M14 3v5h5M8 13h8M8 17h5"/>',
  'excel':
      '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="m9 9 6 6M15 9l-6 6"/>',
  'refresh': '<path d="M20 8a8 8 0 1 0 1 6"/><path d="M21 4v5h-5"/>',
  'layers':
      '<path d="m12 3 9 5-9 5-9-5 9-5Z"/><path d="m3 13 9 5 9-5M3 17l9 5 9-5"/>',
  'trend': '<path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/>',
  'menu': '<path d="M4 7h16M4 12h16M4 17h16"/>',
  'send': '<path d="M21 3 3 10.5l7 2.5 2.5 7L21 3Z"/><path d="M10 13.5 21 3"/>',
  'list': '<path d="M8 6h12M8 12h12M8 18h12"/><path d="M4 6h.01M4 12h.01M4 18h.01"/>',
  'switch':
      '<path d="M16 3l4 4-4 4"/><path d="M20 7H8a4 4 0 0 0-4 4"/><path d="m8 21-4-4 4-4"/><path d="M4 17h12a4 4 0 0 0 4-4"/>',
};

String _hex(Color c) {
  int ch(double v) => (v * 255).round() & 0xff;
  final r = ch(c.r).toRadixString(16).padLeft(2, '0');
  final g = ch(c.g).toRadixString(16).padLeft(2, '0');
  final b = ch(c.b).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

/// Renders a named icon at [size] in [color]. [fill] fills the whole shape
/// (used for selected nav indicators); [stroke] sets the line weight.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.name, {
    super.key,
    this.size = 22,
    this.color,
    this.stroke = 1.75,
    this.fill = false,
  });

  final String name;
  final double size;
  final Color? color;
  final double stroke;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final inner = kIconPaths[name];
    if (inner == null) return SizedBox(width: size, height: size);
    final hex = _hex(color ?? AppColors.ink900);
    final body = inner.replaceAll('currentColor', hex);
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" '
        'viewBox="0 0 24 24" fill="${fill ? hex : 'none'}" stroke="$hex" '
        'stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">'
        '$body</svg>';
    return SvgPicture.string(svg, width: size, height: size);
  }
}
