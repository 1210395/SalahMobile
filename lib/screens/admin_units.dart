// عمارتي — Units (apartments / shops): list, detail sheet, add via WhatsApp/QR.

import 'package:flutter/material.dart';

import '../common.dart';

class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  String filter = 'all';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final res = ctx.res;
    final all = res ? kApartments : kShops;
    final list = all.where((u) {
      final matchFilter = filter == 'all' || u.status == filter;
      final matchQ = q.isEmpty || u.resident.contains(q) || u.no.contains(q);
      return matchFilter && matchQ;
    }).toList();
    final lateCount = all.where((u) => u.status == 'late').length;
    final okCount = all.where((u) => u.status == 'ok').length;

    return ScreenScaffold(
      header: AppHeader(
        title: res ? 'إدارة الشقق' : 'إدارة المحلات',
        subtitle: '${all.length} ${res ? 'شقة' : 'محل'} · $lateCount متأخرة',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'qr', onTap: () => _openAdd(ctx)),
      ),
      nav: ctx.adminNav,
      fab: AppFab(icon: 'plus', label: 'إضافة', onTap: () => _openAdd(ctx)),
      children: [
        Field(
          icon: 'search',
          placeholder: res ? 'ابحث باسم الساكن أو رقم الشقة' : 'ابحث باسم المحل أو رقمه',
          onChanged: (v) => setState(() => q = v),
        ),
        Segmented(
          small: true,
          value: filter,
          onChanged: (v) => setState(() => filter = v as String),
          options: [
            SegOption('all', 'الكل (${all.length})'),
            const SegOption('ok', 'مسدد'),
            const SegOption('late', 'متأخر'),
            const SegOption('vacant', 'شاغر'),
          ],
        ),
        const SizedBox(height: 14),
        if (list.isEmpty)
          const EmptyState(icon: 'building', title: 'لا توجد نتائج', sub: 'جرّب تغيير الفلتر أو البحث')
        else
          ...List.generate(list.length, (i) {
            final u = list[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i < list.length - 1 ? 10 : 0),
              child: _unitCard(ctx, u, res, okCount),
            );
          }),
      ],
    );
  }

  Widget _unitCard(Ctx ctx, Unit u, bool res, int okCount) {
    final s = kStatusMap[u.status]!;
    final vacant = u.status == 'vacant';
    return AppCard(
      pad: 13,
      onTap: () => _openDetail(ctx, u, res),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: vacant ? AppColors.page : AppColors.navy700,
                borderRadius: BorderRadius.circular(14)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NumText(u.no,
                    style: AppType.num(
                        size: 14, weight: FontWeight.w800, color: vacant ? AppColors.ink400 : Colors.white)),
                Text('دور ${u.floor}',
                    style: AppType.base(
                        size: 9,
                        weight: FontWeight.w500,
                        color: vacant ? AppColors.ink400 : Colors.white70)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(u.resident,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.base(
                        size: 14.5,
                        weight: FontWeight.w800,
                        color: vacant ? AppColors.ink400 : AppColors.ink900)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (!vacant) ...[
                      AppBadge(label: u.kind, tone: u.kind == 'مالك' ? 'navy' : 'gold', small: true),
                      const SizedBox(width: 6),
                    ],
                    AppBadge(label: s.label, tone: s.tone, small: true, icon: s.hasDot ? null : 'lock'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (u.balance != 0)
                NumText(fmtUSD(u.balance),
                    style: AppType.num(
                        size: 13.5,
                        weight: FontWeight.w800,
                        color: u.balance < 0 ? AppColors.late700 : AppColors.credit700)),
              const SizedBox(height: 2),
              const AppIcon('chevronL', size: 18, color: AppColors.ink300),
            ],
          ),
        ],
      ),
    );
  }

  void _openDetail(Ctx ctx, Unit u, bool res) {
    final s = kStatusMap[u.status]!;
    showAppSheet(
      context,
      SheetShell(
        title: '${res ? 'شقة' : 'محل'} ${u.no}',
        footer: u.status != 'vacant'
            ? Row(children: [
                Expanded(
                  child: AppButton(
                    label: 'اتصال',
                    variant: BtnVariant.ghost,
                    full: true,
                    icon: 'phone',
                    onTap: () {
                      Navigator.of(context).pop();
                      ctx.toast('جارٍ الاتصال…', tone: 'info');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'تسجيل دفعة',
                    full: true,
                    icon: 'wallet',
                    onTap: () {
                      Navigator.of(context).pop();
                      ctx.go('payments');
                    },
                  ),
                ),
              ])
            : null,
        children: [
          Row(
            children: [
              Avatar(name: u.resident, size: 52, tone: u.kind == 'مالك' ? 'navy' : 'gold'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(u.resident, style: AppType.base(size: 17, weight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Row(children: [
                      AppBadge(label: u.kind, tone: u.kind == 'مالك' ? 'navy' : 'gold', small: true),
                      const SizedBox(width: 6),
                      AppBadge(label: s.label, tone: s.tone, small: true),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DetailGrid(rows: [
            DetailRow('phone', 'الجوال / واتساب', u.phone, ltr: true),
            DetailRow('wallet', 'الاشتراك الشهري', fmtUSD(u.sub)),
            DetailRow('calendar', 'بداية العقد', '2026-01-01'),
            DetailRow('calendar', 'نهاية العقد', '2026-12-31'),
            DetailRow('user', 'مسؤول الدفع', u.payer),
            DetailRow('dollar', 'الرصيد', fmtUSD(u.balance),
                tone: u.balance < 0 ? 'late' : u.balance > 0 ? 'credit' : 'ok'),
          ]),
          const SizedBox(height: 10),
          _notes(u.kind == 'شاغر'
              ? 'الوحدة متاحة للإيجار.'
              : 'يفضل التواصل عبر واتساب بعد الساعة 5 مساءً.'),
        ],
      ),
    );
  }

  void _openAdd(Ctx ctx) {
    final res = ctx.res;
    showAppSheet(
      context,
      SheetShell(
        title: 'إضافة ${res ? 'ساكن' : 'مستأجر'}',
        children: [
          _addOption(
            bg: AppColors.okBg,
            iconColor: AppColors.ok700,
            icon: 'whatsapp',
            title: 'دعوة عبر واتساب',
            sub: 'أرسل رابط انضمام مباشر لرقم الساكن',
            onTap: () {
              Navigator.of(context).pop();
              ctx.toast('تم إرسال دعوة عبر واتساب');
            },
          ),
          const SizedBox(height: 12),
          _addOption(
            bg: AppColors.navy50,
            iconColor: AppColors.navy700,
            icon: 'qr',
            title: 'إنشاء رمز QR',
            sub: 'يمسح الساكن الرمز للانضمام للوحدة',
            onTap: () {
              Navigator.of(context).pop();
              ctx.toast('تم إنشاء رمز QR للوحدة');
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أو أضف يدوياً',
                    style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
                const SizedBox(height: 10),
                AppButton(
                  label: 'إدخال البيانات يدوياً',
                  variant: BtnVariant.outline,
                  full: true,
                  icon: 'plus',
                  onTap: () {
                    Navigator.of(context).pop();
                    ctx.toast('فتح نموذج الإضافة اليدوية', tone: 'info');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addOption({
    required Color bg,
    required Color iconColor,
    required String icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: AppIcon(icon, size: 26, color: iconColor),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppType.base(size: 14.5, weight: FontWeight.w800, color: AppColors.ink900)),
                  const SizedBox(height: 2),
                  Text(sub, style: AppType.base(size: 12, weight: FontWeight.w500, color: AppColors.ink600)),
                ],
              ),
            ),
            const AppIcon('chevronL', size: 18, color: AppColors.ink300),
          ],
        ),
      ),
    );
  }

  Widget _notes(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
        child: RichText(
          text: TextSpan(
            style: AppType.base(size: 13, weight: FontWeight.w500, color: AppColors.ink600),
            children: [
              TextSpan(
                  text: 'ملاحظات: ',
                  style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
              TextSpan(text: text),
            ],
          ),
        ),
      );
}
