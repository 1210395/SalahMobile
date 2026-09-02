// سكن برو — ملف الساكن: everything about one renter in one place.
//
// Tapping a resident's name opens this: their personal record, their login
// (QR + a password the manager can set and read out), and their money kept in
// TWO separate ledgers — ذمم سابقة and اشتراكات شهرية — plus a dated statement
// of both that can be shared or saved.
//
// The figures come from the server's own statement endpoint, so this screen, a
// shared PDF and the units list can never disagree about what someone owes.

import 'package:flutter/material.dart';

import '../common.dart';
import '../api/repository.dart';
import 'report_pdf.dart';

/// Open the full file for the renter of [u].
void openResidentFile(BuildContext context, Ctx ctx, Unit u, bool res) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ResidentFileScreen(ctx: ctx, unit: u, res: res),
  ));
}

class ResidentFileScreen extends StatefulWidget {
  const ResidentFileScreen({super.key, required this.ctx, required this.unit, required this.res});
  final Ctx ctx;
  final Unit unit;
  final bool res;

  @override
  State<ResidentFileScreen> createState() => _ResidentFileScreenState();
}

class _ResidentFileScreenState extends State<ResidentFileScreen> {
  Map<String, dynamic>? data;
  String? error;
  String tab = 'info';

  /// The password the manager has just set, held only for this screen so it can
  /// be read out or sent. It is never stored anywhere — the server keeps a
  /// one-way hash and cannot give it back.
  String? freshPassword;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.I.unitStatement(widget.ctx.btype, widget.unit.dbId);
      if (!mounted) return;
      setState(() {
        data = d;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = apiErrorText(e));
    }
  }

  Map<String, dynamic> get _dues => Map<String, dynamic>.from(data?['dues'] ?? {});
  Map<String, dynamic> get _sub => Map<String, dynamic>.from(data?['sub'] ?? {});
  Map<String, dynamic>? get _resident =>
      data?['resident'] == null ? null : Map<String, dynamic>.from(data!['resident']);
  List<Map<String, dynamic>> get _entries =>
      [for (final e in (data?['entries'] ?? [])) Map<String, dynamic>.from(e)];

  int _i(Object? v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final u = widget.unit;
    final unitWord = widget.res ? 'شقة' : 'وحدة';
    return ScreenScaffold(
      header: AppHeader(
        title: u.resident.trim().isEmpty ? '$unitWord ${u.no}' : u.resident,
        subtitle: '$unitWord ${u.no} · طابق ${u.floor}',
        onBack: () => Navigator.of(context).pop(),
      ),
      children: [
        if (error != null)
          _note(error!, tone: 'late')
        else if (data == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _potsRow(),
          const SizedBox(height: 12),
          Segmented(
            small: true,
            value: tab,
            onChanged: (v) => setState(() => tab = v as String),
            options: const [
              SegOption('info', 'البيانات'),
              SegOption('sub', 'الاشتراكات'),
              SegOption('dues', 'الذمم'),
              SegOption('all', 'كشف شامل'),
            ],
          ),
          const SizedBox(height: 14),
          if (tab == 'info') ..._infoTab(),
          if (tab == 'sub') ..._paymentsTab(isDues: false),
          if (tab == 'dues') ..._paymentsTab(isDues: true),
          if (tab == 'all') ..._statementTab(),
        ],
      ],
    );
  }

  // ─────────────────────── the two pots, side by side ───────────────────────

  Widget _potsRow() {
    final dues = _i(_dues['balance']);
    final sub = _i(_sub['balance']);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _potCard('ذمم سابقة', dues, 'المُدخلة: ${fmtUSD(-_i(_dues['opening']))}')),
        const SizedBox(width: 10),
        Expanded(
          child: _potCard('اشتراكات شهرية', sub,
              '${fmtUSD(_i(_sub['monthly']))} × ${monthsCountLabel(_i(_sub['months']))}'),
        ),
      ],
    );
  }

  Widget _potCard(String title, int value, String hint) {
    final owes = value < 0;
    final tone = value == 0
        ? AppColors.ink600
        : (owes ? AppColors.late700 : AppColors.credit700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: AppType.base(size: 12, weight: FontWeight.w700, color: AppColors.ink600)),
          const SizedBox(height: 6),
          NumText(fmtUSD(value),
              style: AppType.num(size: 18, weight: FontWeight.w800, color: tone)),
          const SizedBox(height: 4),
          Text(value == 0 ? 'مسدَّد' : (owes ? 'متأخر' : 'دائن'),
              style: AppType.base(size: 11, weight: FontWeight.w700, color: tone)),
          const SizedBox(height: 6),
          Text(hint,
              maxLines: 2,
              style: AppType.base(size: 10.5, weight: FontWeight.w500, color: AppColors.ink400)),
        ],
      ),
    );
  }

  // ───────────────────────────── البيانات ─────────────────────────────

  List<Widget> _infoTab() {
    final u = widget.unit;
    final r = _resident;
    final code = '${r?['login_code'] ?? u.loginCode}';
    return [
      DetailGrid(rows: [
        DetailRow('user', 'الاسم', '${r?['name'] ?? u.resident}'),
        DetailRow('phone', 'الجوال (اسم المستخدم)', '${r?['phone'] ?? u.phone}', ltr: true),
        if ('${r?['whatsapp'] ?? ''}'.trim().isNotEmpty)
          DetailRow('whatsapp', 'واتساب', '${r!['whatsapp']}', ltr: true),
        if ('${r?['email'] ?? ''}'.trim().isNotEmpty)
          DetailRow('mail', 'البريد', '${r!['email']}', ltr: true),
        DetailRow('building', widget.res ? 'الشقة' : 'الوحدة', '${u.no} · طابق ${u.floor}'),
        DetailRow('user', 'الصفة', u.kind),
        DetailRow('wallet', 'الدفعة الشهرية', fmtUSD(u.sub)),
        DetailRow('dollar', 'يدفع عنه', u.payer),
        DetailRow('calendar', 'بداية العقد', u.contractStart.isEmpty ? '—' : u.contractStart,
            ltr: u.contractStart.isNotEmpty),
        DetailRow('calendar', 'نهاية العقد', u.ongoing ? 'مستمر' : u.contractEnd,
            ltr: !u.ongoing),
        DetailRow('calendar', 'بداية الاحتساب', '${_sub['billing_start'] ?? '—'}'.split(' ').first,
            ltr: true),
        if (r != null)
          DetailRow('lock', 'حساب الدخول',
              r['disabled'] == true
                  ? 'موقوف'
                  : (r['has_password'] == true ? 'مُفعّل بكلمة مرور' : 'بدون كلمة مرور')),
      ]),
      const SizedBox(height: 14),
      if (freshPassword != null) ...[
        _passwordCard(code),
        const SizedBox(height: 12),
      ],
      // The stored password is a one-way hash — it cannot be read back, by
      // anyone. The manager sets a new one and reads/sends it from here.
      AppButton(
        label: 'تعيين كلمة مرور وعرضها',
        full: true,
        size: BtnSize.lg,
        icon: 'lock',
        onTap: _openSetPassword,
      ),
      const SizedBox(height: 10),
      if (code.trim().isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.sm,
          ),
          child: Column(children: [
            Center(child: QrBox(data: code)),
            const SizedBox(height: 10),
            Text('رمز الدخول',
                style: AppType.base(size: 12, weight: FontWeight.w700, color: AppColors.ink600)),
            const SizedBox(height: 4),
            NumText(code.length > 16 ? '${code.substring(0, 16)}…' : code,
                style: AppType.num(size: 12, weight: FontWeight.w700, color: AppColors.ink700)),
          ]),
        ),
        const SizedBox(height: 10),
        AppButton(
          label: 'إرسال بيانات الدخول عبر واتساب',
          variant: BtnVariant.outline,
          full: true,
          icon: 'whatsapp',
          onTap: () => shareViaWhatsApp(
            phone: '${_resident?['phone'] ?? widget.unit.phone}',
            text: 'بيانات الدخول إلى تطبيق سكن برو:\n'
                'اسم المستخدم: ${_resident?['phone'] ?? widget.unit.phone}'
                '${freshPassword != null ? '\nكلمة المرور: $freshPassword' : ''}'
                '\nأو رمز الدخول: $code',
          ),
        ),
      ],
    ];
  }

  Widget _passwordCard(String code) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('كلمة المرور الجديدة',
                style: AppType.base(size: 12, weight: FontWeight.w700, color: AppColors.ink600)),
            const SizedBox(height: 6),
            NumText(freshPassword!,
                style: AppType.num(size: 20, weight: FontWeight.w800, color: AppColors.brand700)),
            const SizedBox(height: 6),
            Text('اكتبها الآن أو أرسلها للساكن — لا يمكن عرضها لاحقاً، فهي تُحفظ مشفَّرة.',
                style: AppType.base(
                    size: 11, weight: FontWeight.w500, color: AppColors.ink400, height: 1.5)),
          ],
        ),
      );

  void _openSetPassword() {
    final f = {'pass': ''};
    showAppSheet(
      context,
      StatefulBuilder(builder: (sheetCtx, setS) {
        final pass = f['pass']!.trim();
        final blockers = <String>[
          if (pass.length < 6) 'كلمة مرور من 6 أحرف أو أرقام على الأقل',
        ];
        return SheetShell(
          title: 'كلمة مرور الساكن',
          footer: Column(mainAxisSize: MainAxisSize.min, children: [
            if (blockers.isNotEmpty) ...[
              FormBlockedHint(reasons: blockers, title: 'لتعيين كلمة المرور:'),
              const SizedBox(height: 10),
            ],
            AppButton(
              label: 'تعيين وعرض',
              full: true,
              size: BtnSize.lg,
              icon: 'check',
              disabled: blockers.isNotEmpty,
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                try {
                  await Api.I.setUnitPassword(widget.ctx.btype, widget.unit.dbId, pass);
                  await _load();
                  if (!mounted) return;
                  setState(() => freshPassword = pass);
                  widget.ctx.toast('تم تعيين كلمة المرور وإعادة إصدار رمز الدخول');
                } catch (e) {
                  widget.ctx.toast(apiErrorText(e), tone: 'late');
                }
              },
            ),
          ]),
          children: [
            _note('كلمة المرور تُحفظ مشفَّرة ولا يمكن استرجاعها لاحقاً — تظهر هنا مرة واحدة '
                'بعد تعيينها لتسليمها للساكن.'),
            const SizedBox(height: 10),
            Field(
              label: 'كلمة المرور الجديدة',
              icon: 'lock',
              value: f['pass']!,
              ltr: true,
              onChanged: (v) => setS(() => f['pass'] = v),
            ),
          ],
        );
      }),
    );
  }

  // ──────────────────── الاشتراكات / الذمم (each pot alone) ────────────────────

  List<Widget> _paymentsTab({required bool isDues}) {
    final pot = isDues ? _dues : _sub;
    final rows = [for (final p in (pot['payments'] ?? [])) Map<String, dynamic>.from(p)];
    final title = isDues ? 'دفعات الذمم' : 'الدفعات الشهرية';
    return [
      if (isDues)
        _kv('الذمة المُدخلة', fmtUSD(-_i(_dues['opening'])))
      else
        _kv('إجمالي الاشتراكات المستحقة', fmtUSD(_i(_sub['charges']))),
      _kv('المدفوع', fmtUSD(_i(pot['paid']))),
      _kv('المتبقي', fmtUSD(_i(pot['balance'])),
          tone: _i(pot['balance']) < 0 ? AppColors.late700 : AppColors.credit700),
      const SizedBox(height: 12),
      Text('$title (${rows.length})',
          style: AppType.base(size: 13, weight: FontWeight.w800, color: AppColors.ink700)),
      const SizedBox(height: 8),
      if (rows.isEmpty)
        _note(isDues ? 'لا توجد دفعات على الذمم بعد.' : 'لا توجد دفعات اشتراك بعد.')
      else
        ...rows.map((p) => ListRow(
              title: '${p['kind'] ?? ''}',
              sub: '${'${p['date'] ?? ''}'.split('T').first} · ${p['method'] ?? ''}'
                  '${isDues ? '' : ' · ${monthLabelNum(_i(p['month']))} ${_i(p['year'])}'}',
              trailing: NumText('+${fmtUSD(_i(p['amount']))}',
                  style: AppType.num(
                      size: 13.5, weight: FontWeight.w800, color: AppColors.ok700)),
            )),
    ];
  }

  // ───────────────────────── كشف شامل (both pots, dated) ─────────────────────

  List<Widget> _statementTab() {
    final entries = _entries;
    return [
      Row(children: [
        Expanded(
          child: AppButton(
            label: 'مشاركة',
            full: true,
            icon: 'share',
            onTap: () => _export(share: true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppButton(
            label: 'حفظ على الجهاز',
            variant: BtnVariant.outline,
            full: true,
            icon: 'download',
            onTap: () => _export(share: false),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      if (entries.isEmpty)
        _note('لا توجد حركات بعد.')
      else
        ...entries.reversed.map((e) {
          final amount = _i(e['amount']);
          final isPayment = e['type'] == 'payment';
          final pot = e['bucket'] == 'dues' ? 'ذمم' : 'اشتراك';
          return ListRow(
            title: '${e['label'] ?? ''}',
            sub: '${'${e['date'] ?? ''}'.split(' ').first} · $pot'
                ' · الرصيد ${fmtUSD(_i(e['running_total']))}',
            trailing: NumText('${amount >= 0 ? '+' : ''}${fmtUSD(amount)}',
                style: AppType.num(
                    size: 13.5,
                    weight: FontWeight.w800,
                    color: isPayment ? AppColors.ok700 : AppColors.late700)),
          );
        }),
    ];
  }

  /// The statement as a PDF — shared through the system sheet, or saved to the
  /// device. Same rows either way, and the same figures the screen shows.
  Future<void> _export({required bool share}) async {
    final u = widget.unit;
    final rows = <List<String>>[
      ['التاريخ', 'البيان', 'البند', 'المبلغ', 'رصيد الذمم', 'رصيد الاشتراك'],
      for (final e in _entries)
        [
          '${e['date'] ?? ''}'.split(' ').first,
          '${e['label'] ?? ''}',
          e['bucket'] == 'dues' ? 'ذمم سابقة' : 'اشتراك شهري',
          '${_i(e['amount'])}',
          '${_i(e['running_dues'])}',
          '${_i(e['running_sub'])}',
        ],
      ['', 'المتبقي', '', '', '${_i(_dues['balance'])}', '${_i(_sub['balance'])}'],
    ];
    final title = 'كشف حساب — ${u.resident} (${widget.res ? 'شقة' : 'وحدة'} ${u.no})';
    try {
      if (share) {
        await exportReportPdf(title, rows, buildingName: widget.ctx.building.name);
      } else {
        final path = await saveReportPdf(title, rows,
            buildingName: widget.ctx.building.name,
            fileName: 'amarati-statement-${u.no}.pdf');
        widget.ctx.toast('تم حفظ الكشف في: $path');
      }
    } catch (_) {
      widget.ctx.toast('تعذّر تصدير الكشف', tone: 'late');
    }
  }

  // ───────────────────────────── small pieces ─────────────────────────────

  Widget _kv(String label, String value, {Color? tone}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: AppType.base(size: 12.5, weight: FontWeight.w600, color: AppColors.ink600)),
            NumText(value,
                style: AppType.num(
                    size: 13.5, weight: FontWeight.w800, color: tone ?? AppColors.ink900)),
          ],
        ),
      );

  Widget _note(String text, {String tone = 'info'}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: AppType.base(
                size: 12,
                weight: FontWeight.w600,
                color: tone == 'late' ? AppColors.late700 : AppColors.ink600,
                height: 1.6)),
      );
}
