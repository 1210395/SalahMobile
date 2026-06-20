// عمارتي — Super-admin (platform owner): global report across all buildings
// with filters, and creating/listing building admins.

import 'package:flutter/material.dart';

import '../common.dart';
import '../api/repository.dart';

// ───────────────────────────── Global report ─────────────────────────────

class SuperReportScreen extends StatefulWidget {
  const SuperReportScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<SuperReportScreen> createState() => _SuperReportScreenState();
}

class _SuperReportScreenState extends State<SuperReportScreen> {
  int? month; // null = all
  String btypeFilter = 'all'; // all | residential | commercial
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Api.I.globalReport(
        month: month,
        btype: btypeFilter == 'all' ? null : btypeFromKey(btypeFilter),
      );
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final buildings = (_data?['buildings'] as List?) ?? [];
    final totals = (_data?['totals'] as Map?) ?? {};

    return ScreenScaffold(
      header: AppHeader(
        accent: true,
        title: 'التقرير الشامل',
        subtitle: 'كل المباني — المدير العام',
        right: RoundBtn(icon: 'refresh', dark: true, onTap: _load),
      ),
      nav: ctx.adminNav,
      children: [
        // Building-type filter
        Segmented(
          value: btypeFilter,
          onChanged: (v) {
            setState(() => btypeFilter = v as String);
            _load();
          },
          options: const [
            SegOption('all', 'كل الأنواع'),
            SegOption('residential', 'سكني'),
            SegOption('commercial', 'تجاري'),
          ],
        ),
        const SizedBox(height: 10),
        // Month filter
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 13,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (_, i) {
              final val = i == 0 ? null : i - 1;
              final on = month == val;
              return GestureDetector(
                onTap: () {
                  setState(() => month = val);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.navy700 : AppColors.surface,
                    border: Border.all(color: on ? AppColors.navy700 : AppColors.line2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(i == 0 ? 'كل الأشهر' : monthLabelNum(i - 1),
                      style: AppType.base(
                          size: 12.5, weight: FontWeight.w700,
                          color: on ? Colors.white : AppColors.ink600)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (_error != null)
          EmptyState(icon: 'alert', title: 'تعذّر التحميل', sub: _error)
        else if (_data == null && _loading)
          const Padding(
            padding: EdgeInsets.only(top: 50),
            child: Center(child: CircularProgressIndicator(color: AppColors.navy700)),
          )
        else ...[
          // Combined totals (across buildings; each shown in its own currency below)
          Row(children: [
            Expanded(child: _totalCard('محصّل', _n(totals['collected']), AppColors.ok700, 'trend')),
            const SizedBox(width: 10),
            Expanded(child: _totalCard('مصروفات', _n(totals['expenses']), AppColors.late700, 'expense')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _totalCard('الرصيد', _n(totals['balance']), AppColors.navy700, 'wallet')),
            const SizedBox(width: 10),
            Expanded(child: _totalCard('متأخرون', '${_i(totals['late'])}', AppColors.gold700, 'alert', plain: true)),
          ]),
          const SizedBox(height: 16),
          const SectionTitle(text: 'حسب المبنى'),
          ...buildings.map((b) => _buildingCard(Map<String, dynamic>.from(b))),
          const SizedBox(height: 8),
          AppButton(
            label: 'إدارة المسؤولين',
            variant: BtnVariant.outline,
            full: true,
            icon: 'users',
            onTap: () => ctx.go('admins'),
          ),
        ],
      ],
    );
  }

  int _i(Object? v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
  String _n(Object? v) => groupNumber(_i(v));

  Widget _totalCard(String label, String value, Color color, String icon, {bool plain = false}) =>
      AppCard(
        pad: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              AppIcon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(label, style: AppType.base(size: 11.5, weight: FontWeight.w600, color: AppColors.ink500)),
            ]),
            const SizedBox(height: 8),
            NumText(value, style: AppType.num(size: 19, weight: FontWeight.w800, color: color)),
          ],
        ),
      );

  Widget _buildingCard(Map<String, dynamic> b) {
    final cur = '${b['currency'] ?? 'USD'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              IconChip(icon: b['type'] == 'تجاري' ? 'store' : 'building2', tone: 'navy', size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${b['name']}', style: AppType.base(size: 15, weight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('${b['type']} · ${b['units']} وحدة · ${b['admins']} مسؤول',
                        style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                  ],
                ),
              ),
              if (_i(b['late']) > 0) AppBadge(label: '${_i(b['late'])} متأخر', tone: 'late', small: true),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              MiniStat(label: 'محصّل', value: fmtMoney(_i(b['collected']), cur), tone: 'ok', num: true),
              const SizedBox(width: 8),
              MiniStat(label: 'مصروفات', value: fmtMoney(_i(b['expenses']), cur), tone: 'late', num: true),
              const SizedBox(width: 8),
              MiniStat(label: 'الرصيد', value: fmtMoney(_i(b['balance']), cur), tone: 'navy', num: true),
            ]),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Admins (list + create) ─────────────────────────────

class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  List<Map<String, dynamic>>? _admins;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await Api.I.listAdmins();
      if (mounted) setState(() => _admins = list);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    return ScreenScaffold(
      header: AppHeader(
        title: 'المسؤولون',
        subtitle: _admins == null ? '...' : '${_admins!.length} مسؤول مبنى',
        onBack: () => ctx.go('superReport'),
      ),
      nav: ctx.adminNav,
      fab: AppFab(icon: 'plus', label: 'مسؤول جديد', onTap: () => _openCreate(ctx)),
      children: [
        if (_error != null)
          EmptyState(icon: 'alert', title: 'تعذّر التحميل', sub: _error)
        else if (_admins == null)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator(color: AppColors.navy700)),
          )
        else if (_admins!.isEmpty)
          const EmptyState(icon: 'users', title: 'لا يوجد مسؤولون', sub: 'أنشئ مسؤول مبنى جديد')
        else
          ..._admins!.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Row(children: [
                    Avatar(name: '${a['name']}', size: 46, tone: 'navy'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${a['name']}', style: AppType.base(size: 15, weight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('${a['email'] ?? ''}',
                              style: AppType.base(size: 12, weight: FontWeight.w600, color: AppColors.ink500)),
                        ],
                      ),
                    ),
                    AppBadge(
                        label: a['building_key'] == 'commercial' ? 'تجاري' : 'سكني',
                        tone: 'gold', small: true),
                  ]),
                ),
              )),
      ],
    );
  }

  void _openCreate(Ctx ctx) {
    final f = {'name': '', 'email': '', 'password': ''};
    Object building = 'residential';
    showAppSheet(
      context,
      StatefulBuilder(
        builder: (sheetCtx, setS) => SheetShell(
          title: 'إنشاء مسؤول مبنى',
          footer: AppButton(
            label: 'إنشاء',
            full: true,
            size: BtnSize.lg,
            icon: 'check',
            disabled: f['name']!.trim().isEmpty ||
                f['email']!.trim().isEmpty ||
                f['password']!.trim().length < 6,
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Api.I.createAdmin({
                  'name': f['name']!.trim(),
                  'email': f['email']!.trim(),
                  'password': f['password']!.trim(),
                  'building_key': building,
                });
                ctx.toast('تم إنشاء المسؤول');
                await _load();
              } catch (e) {
                ctx.toast(apiErrorText(e), tone: 'late');
              }
            },
          ),
          children: [
            Field(label: 'الاسم', icon: 'user', placeholder: 'اسم المسؤول', onChanged: (v) => setS(() => f['name'] = v)),
            Field(
                label: 'البريد الإلكتروني',
                icon: 'mail',
                placeholder: 'admin@example.com',
                ltr: true,
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) => setS(() => f['email'] = v)),
            Field(
                label: 'كلمة المرور',
                icon: 'lock',
                placeholder: '6 أحرف على الأقل',
                ltr: true,
                obscure: true,
                onChanged: (v) => setS(() => f['password'] = v)),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('المبنى',
                  style: AppType.base(size: 13, weight: FontWeight.w700, color: AppColors.ink700)),
            ),
            Segmented(
              value: building,
              onChanged: (v) => setS(() => building = v),
              options: const [
                SegOption('residential', 'سكني (شقق)', icon: 'building'),
                SegOption('commercial', 'تجاري (محلات)', icon: 'store'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
