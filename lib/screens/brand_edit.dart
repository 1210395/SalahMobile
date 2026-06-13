// عمارتي — brand-editing panel (#10). Admin edits the app name, slogan,
// description, tagline, and logo; saved to the live API and reflected app-wide
// (e.g. the splash screen) via the [Brand] accessor.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../common.dart';
import '../api/repository.dart';

class BrandEditScreen extends StatefulWidget {
  const BrandEditScreen({super.key, required this.ctx});
  final Ctx ctx;

  @override
  State<BrandEditScreen> createState() => _BrandEditScreenState();
}

class _BrandEditScreenState extends State<BrandEditScreen> {
  late final f = {
    'app_name': Brand.appName,
    'slogan': Brand.slogan,
    'description': Brand.description,
    'tagline': Brand.tagline,
  };
  bool _saving = false;
  bool _uploading = false;

  Future<void> _save() async {
    final ctx = widget.ctx;
    setState(() => _saving = true);
    try {
      await Api.I.updateSettings({
        'app_name': f['app_name'],
        'slogan': f['slogan'],
        'description': f['description'],
        'tagline': f['tagline'],
      });
      ctx.toast('تم حفظ هوية التطبيق');
      ctx.go('more');
    } catch (e) {
      ctx.toast(apiErrorText(e), tone: 'late');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickLogo() async {
    final ctx = widget.ctx;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024);
      if (picked == null) return;
      setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      await Api.I.uploadLogo(bytes, picked.name);
      ctx.toast('تم تحديث الشعار');
    } catch (e) {
      ctx.toast(apiErrorText(e), tone: 'late');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final logo = Brand.logoUrl;
    return ScreenScaffold(
      header: AppHeader(
        title: 'هوية التطبيق',
        subtitle: 'الشعار والاسم والنصوص',
        onBack: () => ctx.go('more'),
      ),
      nav: ctx.adminNav,
      children: [
        const SectionTitle(text: 'الشعار'),
        AppCard(
          child: Row(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.navy700,
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: logo.isNotEmpty
                    ? Image.network(logo, fit: BoxFit.contain,
                        errorBuilder: (c, e, s) =>
                            Image.asset('assets/images/logo-light.png', width: 56))
                    : Image.asset('assets/images/logo-light.png', width: 56),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AppButton(
                  label: _uploading ? 'جارٍ الرفع…' : 'تغيير الشعار',
                  variant: BtnVariant.outline,
                  full: true,
                  icon: 'camera',
                  onTap: _uploading ? null : _pickLogo,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(text: 'الاسم والنصوص'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(
                  label: 'اسم التطبيق',
                  icon: 'building2',
                  value: f['app_name']!,
                  onChanged: (v) => f['app_name'] = v),
              Field(
                  label: 'الشعار النصّي (Slogan)',
                  icon: 'megaphone',
                  value: f['slogan']!,
                  onChanged: (v) => f['slogan'] = v),
              AppTextArea(
                label: 'الوصف',
                value: f['description']!,
                onChanged: (v) => f['description'] = v,
                rows: 3,
              ),
              Field(
                  label: 'العبارة السفلية (Tagline)',
                  icon: 'shield',
                  value: f['tagline']!,
                  marginBottom: 0,
                  onChanged: (v) => f['tagline'] = v),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: _saving ? 'جارٍ الحفظ…' : 'حفظ التغييرات',
          size: BtnSize.lg,
          full: true,
          icon: 'check',
          disabled: _saving,
          onTap: _save,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('تنعكس التغييرات على شاشة البداية وكل العملاء بعد الحفظ.',
              textAlign: TextAlign.center,
              style: AppType.base(size: 11.5, weight: FontWeight.w500, color: AppColors.ink400)),
        ),
      ],
    );
  }
}
