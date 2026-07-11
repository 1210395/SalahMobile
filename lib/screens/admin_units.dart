// عمارتي — Units (apartments / shops): list, detail sheet, add via WhatsApp/QR.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import '../api/repository.dart';

class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  String filter = 'all';
  String q = '';

  /// Persist a unit write, then refresh the bundle so the list updates.
  Future<void> _save(Future<void> Function() call, String okMsg) async {
    final ctx = widget.ctx;
    try {
      await call();
      await ctx.reload();
      ctx.toast(okMsg);
    } catch (e) {
      ctx.toast(apiErrorText(e), tone: 'late');
    }
  }

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
        title: ctx.building.name.trim().isNotEmpty
            ? ctx.building.name
            : (res ? 'إدارة الشقق' : 'إدارة الوحدات'),
        subtitle: '${all.length} ${res ? 'شقة' : 'وحدة'} · $lateCount متأخرة',
        onBack: () => ctx.go('home'),
        right: RoundBtn(icon: 'qr', onTap: () => _openAdd(ctx)),
      ),
      nav: ctx.adminNav,
      fab: AppFab(icon: 'plus', label: 'إضافة', onTap: () => _openAdd(ctx)),
      children: [
        Field(
          icon: 'search',
          placeholder: res ? 'ابحث باسم الساكن أو رقم الشقة' : 'ابحث باسم الوحدة أو رقمه',
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
            width: 52,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
                color: vacant ? AppColors.page : AppColors.navy700,
                borderRadius: BorderRadius.circular(14)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NumText(u.no,
                    style: AppType.num(
                        size: 14, weight: FontWeight.w800, color: vacant ? AppColors.ink400 : Colors.white)),
                Text('طابق ${u.floor}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    semanticsLabel: floorUnitLabel(u, res),
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
        title: '${res ? 'شقة' : 'وحدة'} ${u.no}',
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
            DetailRow('user', 'نوع العقار', u.kind),
            DetailRow('wallet', 'الدفعة الشهرية', fmtUSD(u.sub)),
            DetailRow('dollar', 'الرصيد', fmtUSD(u.balance),
                tone: u.balance < 0 ? 'late' : u.balance > 0 ? 'credit' : 'ok'),
            DetailRow('calendar', 'بداية العقد',
                u.contractStart.isEmpty ? '—' : u.contractStart, ltr: u.contractStart.isNotEmpty),
            DetailRow('calendar', 'نهاية العقد',
                u.ongoing ? 'مستمر' : u.contractEnd, ltr: !u.ongoing),
          ]),
          if (u.kind == 'شاغر') ...[
            const SizedBox(height: 10),
            _notes('${res ? 'الشقة' : 'الوحدة'} ${res ? 'متاحة' : 'متاحة'} للإيجار.'),
          ],
          if (u.loginCode.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            AppButton(
              label: 'رمز الدخول / QR',
              variant: BtnVariant.outline,
              full: true,
              icon: 'qr',
              onTap: () {
                Navigator.of(context).pop();
                _openLoginCode(ctx, u);
              },
            ),
          ],
          const SizedBox(height: 10),
          AppButton(
            label: 'تعديل بيانات ${res ? 'الشقة' : 'الوحدة'}',
            variant: BtnVariant.outline,
            full: true,
            icon: 'edit',
            onTap: () {
              Navigator.of(context).pop();
              _openEdit(ctx, u, res);
            },
          ),
        ],
      ),
    );
  }

  /// QR + short login code the resident scans/enters to sign in. Shareable to
  /// the resident over WhatsApp.
  void _openLoginCode(Ctx ctx, Unit u) {
    showAppSheet(
      context,
      SheetShell(
        title: 'رمز الدخول',
        footer: AppButton(
          label: 'إرسال للساكن عبر واتساب',
          full: true,
          size: BtnSize.lg,
          icon: 'whatsapp',
          onTap: () {
            shareViaWhatsApp(
              phone: u.phone,
              text: 'كود الدخول إلى تطبيق عمارتي: ${u.loginCode}',
            );
          },
        ),
        children: [
          Center(child: QrBox(data: u.loginCode)),
          const SizedBox(height: 16),
          Text('يمسح الساكن الرمز أو يُدخل الكود التالي لتسجيل الدخول:',
              textAlign: TextAlign.center,
              style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink700, height: 1.6)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Center(
              child: NumText(u.loginCode,
                  style: AppType.num(size: 20, weight: FontWeight.w800, color: AppColors.navy700)),
            ),
          ),
        ],
      ),
    );
  }

  /// Manual new-resident form: identity, property kind, location, the monthly
  /// dues + any prior receivables, the contract window, and an optional login
  /// account (mobile = username).
  void _openManualAdd(Ctx ctx, bool res) {
    // sub defaults to the building's subscription but stays editable.
    final f = {
      'name': '',
      'phone': '',
      'floor': '',
      'no': '',
      'sub': '${ctx.building.subscription}',
      'prev': '',
      'password': '',
    };
    String kind = 'مالك';
    String start = todayIso();
    String end = '';
    bool ongoing = true; // start open-ended; the switch toggles an end date.
    bool makeAccount = false;
    // When on, the opening debt is auto-computed server-side as
    // (sub × whole months since the contract start) instead of starting fresh
    // this month — "احتساب الإيجار من بداية العقد".
    bool backDebt = false;
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'إضافة ${res ? 'ساكن' : 'مستأجر'} يدوياً',
          footer: AppButton(
            label: 'حفظ',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: f['name']!.trim().isEmpty ||
                f['no']!.trim().isEmpty ||
                (makeAccount && f['phone']!.trim().isEmpty) ||
                // A resident account now requires a real password (phone+password
                // is their durable login; the QR code is single-use).
                (makeAccount && f['password']!.trim().length < 6),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              final prev = int.tryParse(f['prev']!.trim()) ?? 0;
              _save(
                () async {
                  await Api.I.createUnit(ctx.btype, {
                    'no': f['no']!.trim(),
                    'floor': int.tryParse(f['floor']!.trim()) ?? 0,
                    'resident': f['name']!.trim(),
                    'kind': kind,
                    'phone': f['phone']!.trim().isEmpty ? '—' : f['phone']!.trim(),
                    'sub': int.tryParse(f['sub']!.trim()) ?? ctx.building.subscription,
                    'balance': -prev, // ذمم سابقة → opening debit (ignored if back_debt)
                    'back_debt': backDebt,
                    'contract_start': start,
                    'contract_end': ongoing ? '' : end,
                    'status': 'ok',
                  });
                  if (makeAccount) {
                    await Api.I.createResident(ctx.btype, {
                      'name': f['name']!.trim(),
                      'phone': f['phone']!.trim(),
                      if (f['password']!.trim().isNotEmpty) 'password': f['password']!.trim(),
                      'unit_no': f['no']!.trim(),
                    });
                  }
                },
                makeAccount
                    ? 'تمت إضافة ${f['name']!.trim()} وإنشاء حساب دخول'
                    : 'تمت إضافة ${f['name']!.trim()} — ${res ? 'شقة' : 'وحدة'} ${f['no']}',
              );
            },
          ),
          children: [
            Field(
                label: 'الاسم',
                icon: 'user',
                placeholder: 'الاسم الكامل',
                onChanged: (v) => setS(() => f['name'] = v)),
            Field(
                label: 'رقم الموبايل',
                icon: 'phone',
                placeholder: '5X XXX XXXX',
                ltr: true,
                keyboardType: TextInputType.phone,
                onChanged: (v) => setS(() => f['phone'] = v)),
            SelectField(
              label: 'نوع العقار',
              icon: 'user',
              options: const [
                SelectOption('مالك', 'ملك'),
                SelectOption('مستأجر', 'مستأجر'),
              ],
              value: kind,
              onChanged: (v) => setS(() => kind = v as String),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Field(
                      label: 'الطابق',
                      icon: 'building',
                      placeholder: '0',
                      ltr: true,
                      keyboardType: const TextInputType.numberWithOptions(signed: true),
                      onChanged: (v) => setS(() => f['floor'] = v)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Field(
                      label: res ? 'رقم الشقة' : 'رقم الوحدة',
                      icon: 'grid',
                      placeholder: res ? '101' : 'M-01',
                      ltr: true,
                      onChanged: (v) => setS(() => f['no'] = v)),
                ),
              ],
            ),
            Field(
                label: 'الدفعة الشهرية',
                icon: 'wallet',
                value: f['sub']!,
                ltr: true,
                suffix: currencySymbol(activeCurrency),
                keyboardType: TextInputType.number,
                onChanged: (v) => f['sub'] = v),
            Field(
                label: 'ذمم سابقة (اختياري)',
                icon: 'dollar',
                placeholder: '0',
                ltr: true,
                suffix: currencySymbol(activeCurrency),
                keyboardType: TextInputType.number,
                onChanged: (v) => f['prev'] = v),
            DateField(
                label: 'تاريخ بداية العقد',
                value: start,
                onChanged: (v) => setS(() => start = v)),
            _switchRow(
              label: 'احتساب الإيجار من بداية العقد',
              checked: backDebt,
              onChanged: (v) => setS(() => backDebt = v),
            ),
            if (backDebt)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                    'سيُحتسب الدين الافتتاحي = الدفعة الشهرية × عدد الأشهر منذ بداية العقد، '
                    'بالإضافة إلى الذمم السابقة إن وُجدت. بدون التفعيل يبدأ الحساب من الشهر الحالي '
                    '(مع احتساب الذمم السابقة).',
                    style: AppType.base(
                        size: 11.5, weight: FontWeight.w500, color: AppColors.ink400, height: 1.5)),
              ),
            DateField(
                label: 'تاريخ نهاية العقد',
                value: ongoing ? '' : end,
                enabled: !ongoing,
                onChanged: (v) => setS(() => end = v)),
            _switchRow(
              label: 'مستمر (بدون تاريخ نهاية)',
              checked: ongoing,
              onChanged: (v) => setS(() {
                ongoing = v;
                if (v) end = ''; // clear the end date when going open-ended
              }),
            ),
            const SizedBox(height: 12),
            _switchRow(
              label: 'إنشاء حساب دخول للساكن',
              checked: makeAccount,
              onChanged: (v) => setS(() => makeAccount = v),
            ),
            if (makeAccount) ...[
              const SizedBox(height: 8),
              Text('اسم المستخدم هو رقم الموبايل. يسجّل الساكن الدخول برقم الموبايل وكلمة المرور. '
                  'رمز الـ QR للدخول لمرة واحدة فقط.',
                  style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink400, height: 1.5)),
              const SizedBox(height: 8),
              Field(
                  label: 'كلمة المرور',
                  icon: 'lock',
                  placeholder: '6 أحرف على الأقل',
                  ltr: true,
                  onChanged: (v) => setS(() => f['password'] = v)),
            ],
          ],
        ),
      ),
    );
  }

  /// Edit an existing unit — all fields, plus a "vacant" status that excludes it
  /// from accounts and payments.
  void _openEdit(Ctx ctx, Unit u, bool res) {
    final f = {
      'name': u.resident,
      'phone': u.phone,
      'floor': '${u.floor}',
      'no': u.no,
      'sub': '${u.sub}',
      'balance': '${u.balance}',
    };
    String kind = u.kind == 'مالك' || u.kind == 'مستأجر' ? u.kind : 'مالك';
    String status = u.status;
    String start = u.contractStart;
    String end = u.contractEnd;
    bool ongoing = u.ongoing;
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'تعديل ${res ? 'شقة' : 'وحدة'} ${u.no}',
          footer: AppButton(
            label: 'حفظ التعديلات',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _save(
                () => Api.I.updateUnit(ctx.btype, u.dbId, {
                  'no': f['no']!.trim().isEmpty ? u.no : f['no']!.trim(),
                  'floor': int.tryParse(f['floor']!.trim()) ?? u.floor,
                  'resident': f['name'],
                  'phone': f['phone'],
                  'kind': kind,
                  'sub': int.tryParse(f['sub']!.trim()) ?? u.sub,
                  'balance': int.tryParse(f['balance']!.trim()) ?? u.balance,
                  'contract_start': start,
                  'contract_end': ongoing ? '' : end,
                  'status': status,
                }),
                status == 'vacant'
                    ? 'تم تعيين ${res ? 'الشقة' : 'الوحدة'} كشاغر — مستبعَد من الحسابات والدفعات'
                    : 'تم حفظ التعديلات',
              );
            },
          ),
          children: [
            Field(label: 'الاسم', icon: 'user', value: f['name']!, onChanged: (v) => f['name'] = v),
            Field(
                label: 'رقم الموبايل',
                icon: 'phone',
                value: f['phone']!,
                ltr: true,
                keyboardType: TextInputType.phone,
                onChanged: (v) => f['phone'] = v),
            SelectField(
              label: 'نوع العقار',
              icon: 'user',
              options: const [
                SelectOption('مالك', 'ملك'),
                SelectOption('مستأجر', 'مستأجر'),
              ],
              value: kind,
              onChanged: (v) => setS(() => kind = v as String),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Field(
                      label: 'الطابق',
                      icon: 'building',
                      value: f['floor']!,
                      ltr: true,
                      keyboardType: const TextInputType.numberWithOptions(signed: true),
                      onChanged: (v) => f['floor'] = v),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Field(
                      label: res ? 'رقم الشقة' : 'رقم الوحدة',
                      icon: 'grid',
                      value: f['no']!,
                      ltr: true,
                      onChanged: (v) => f['no'] = v),
                ),
              ],
            ),
            Field(
                label: 'الدفعة الشهرية',
                icon: 'wallet',
                value: f['sub']!,
                ltr: true,
                suffix: currencySymbol(activeCurrency),
                keyboardType: TextInputType.number,
                onChanged: (v) => f['sub'] = v),
            Field(
                label: 'الرصيد / الذمم',
                hint: 'سالب = على الساكن · موجب = رصيد دائن',
                icon: 'dollar',
                value: f['balance']!,
                ltr: true,
                suffix: currencySymbol(activeCurrency),
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                onChanged: (v) => f['balance'] = v),
            DateField(
                label: 'تاريخ بداية العقد',
                value: start,
                onChanged: (v) => setS(() => start = v)),
            DateField(
                label: 'تاريخ نهاية العقد',
                value: ongoing ? '' : end,
                enabled: !ongoing,
                onChanged: (v) => setS(() => end = v)),
            _switchRow(
              label: 'مستمر (بدون تاريخ نهاية)',
              checked: ongoing,
              onChanged: (v) => setS(() {
                ongoing = v;
                if (v) end = '';
              }),
            ),
            const SizedBox(height: 12),
            SelectField(
              label: 'الحالة',
              icon: 'filter',
              options: const [
                SelectOption('ok', 'مسدّد'),
                SelectOption('late', 'متأخر'),
                SelectOption('credit', 'رصيد دائن'),
                SelectOption('vacant', 'شاغر'),
              ],
              value: status,
              onChanged: (v) => setS(() => status = v as String),
            ),
            if (status == 'vacant')
              _notes('عند جعل ${res ? 'الشقة' : 'الوحدة'} شاغراً يُستبعَد تلقائياً من الحسابات والدفعات والتقارير.'),
            const SizedBox(height: 12),
            AppButton(
              label: 'حذف ${res ? 'الشقة' : 'الوحدة'} نهائياً',
              variant: BtnVariant.danger,
              full: true,
              icon: 'trash',
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _save(() => Api.I.deleteUnit(ctx.btype, u.dbId),
                    'تم حذف ${res ? 'الشقة' : 'الوحدة'} ${u.no}');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAdd(Ctx ctx) {
    final res = ctx.res;
    showAppSheet(
      context,
      SheetShell(
        title: 'إضافة ${res ? 'ساكن' : 'مستأجر'}',
        // Manual-add lives in the footer so SheetShell pads it above the
        // Android nav bar (footer padding includes viewPadding.bottom).
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
                _openManualAdd(ctx, res);
              },
            ),
          ],
        ),
        children: [
          _addOption(
            bg: AppColors.okBg,
            iconColor: AppColors.ok700,
            icon: 'whatsapp',
            title: 'دعوة عبر واتساب',
            sub: 'أرسل رابط انضمام مباشر لرقم الساكن',
            onTap: () {
              Navigator.of(context).pop();
              _openInvite(ctx, res, qr: false);
            },
          ),
          const SizedBox(height: 12),
          _addOption(
            bg: AppColors.navy50,
            iconColor: AppColors.navy700,
            icon: 'qr',
            title: 'إنشاء رمز QR',
            sub: 'يمسح الساكن الرمز للانضمام ${res ? 'للشقة' : 'للوحدة'}',
            onTap: () {
              Navigator.of(context).pop();
              _openInvite(ctx, res, qr: true);
            },
          ),
        ],
      ),
    );
  }

  /// Invite preview (WhatsApp link / QR) — the resident opens the join page.
  void _openInvite(Ctx ctx, bool res, {required bool qr}) {
    final code = 'AMR-${ctx.building.units}${ctx.building.floors}';
    final link = 'https://imarty.olive-dev.com/join/$code';
    showAppSheet(
      context,
      SheetShell(
        title: qr ? 'رمز QR للانضمام' : 'دعوة عبر واتساب',
        footer: AppButton(
          label: 'محاكاة فتح صفحة الانضمام',
          full: true,
          size: BtnSize.lg,
          iconRight: 'arrowL',
          onTap: () {
            Navigator.of(context).pop();
            ctx.go('joinUnit');
          },
        ),
        children: [
          if (qr)
            Center(
              child: Container(
                width: 180,
                height: 180,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.line2, width: 1.5),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const AppIcon('qr', size: 96, color: AppColors.navy700),
                  const SizedBox(height: 8),
                  NumText(code,
                      style: AppType.num(size: 12, weight: FontWeight.w700, color: AppColors.ink500)),
                ]),
              ),
            ),
          Text(
              qr
                  ? 'يمسح الساكن هذا الرمز ليفتح صفحة تعبئة بياناته مرتبطة بـ «${ctx.building.name}».'
                  : 'يصل الساكن رابط الانضمام التالي عبر واتساب، ويفتح صفحة تعبئة بياناته مرتبطة بـ «${ctx.building.name}»:',
              style: AppType.base(size: 13, weight: FontWeight.w600, color: AppColors.ink700, height: 1.6)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(children: [
              Expanded(
                child: NumText(link,
                    style: AppType.num(size: 12.5, weight: FontWeight.w700, color: AppColors.navy700)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: link));
                  ctx.toast('تم نسخ رابط الدعوة');
                },
                child: const AppIcon('file', size: 18, color: AppColors.navy600),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('ملاحظة: توليد QR/الرابط الفعلي والربط العميق (deep-link) يتم في الخطوة التالية مع الخلفية.',
              style: AppType.base(size: 11, weight: FontWeight.w500, color: AppColors.ink400, height: 1.5)),
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

  /// Labelled switch row inside a tinted card (used in the add/edit forms).
  Widget _switchRow({
    required String label,
    required bool checked,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label, style: AppType.base(size: 14, weight: FontWeight.w700)),
          ),
          AppSwitch(checked: checked, onChanged: onChanged),
        ]),
      );

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
