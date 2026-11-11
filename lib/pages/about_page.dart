import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, MethodChannel;
import 'package:url_launcher/url_launcher.dart';
import 'package:floating_clock/theme/app_theme.dart';
import 'package:floating_clock/widgets/ui_kit.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final String _appName = '悬浮时间';
  String _version = '';
  final String _repoUrl = 'https://github.com/idearthas/FloatingClock-Pro';
  bool _loading = false;
  Uint8List? _iconBytes;
  final ImageProvider _fallbackIcon = const AssetImage('assets/app_icon.webp');

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadIcon();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 预先加载应用图标资产，避免初始闪烁到默认占位
    precacheImage(_fallbackIcon, context);
  }

  Future<void> _loadIcon() async {
    try {
      final channel = MethodChannel('floating_clock');
      final res = await channel.invokeMethod<dynamic>('getAppIcon');
      if (res != null) {
        if (res is Uint8List) {
          setState(() => _iconBytes = res);
        } else if (res is List) {
          setState(() => _iconBytes = Uint8List.fromList(List<int>.from(res)));
        }
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadVersion() async {
    setState(() => _loading = true);
    try {
      final channel = MethodChannel('floating_clock');
      final v = await channel.invokeMethod<String>('getAppVersion');
      if (v != null && v.isNotEmpty) {
        setState(() => _version = v);
      }
    } catch (_) {
      // ignore errors and leave version empty
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1B2338),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium)),
      margin: const EdgeInsets.all(AppSpacing.l),
    ));
  }

  Future<void> _openRepo() async {
    final uri = Uri.parse(_repoUrl);
    try {
      final can = await canLaunchUrl(uri);
      if (!can) {
        _showSnack('无法打开链接');
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showSnack('无法打开链接');
    }
  }

  void _copyRepo() {
    Clipboard.setData(ClipboardData(text: _repoUrl)).then((_) {
      _showSnack('仓库地址已复制到剪贴板');
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayedVersion = _version.isNotEmpty ? _version : '未知';

    final iconWidget = ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: _iconBytes != null
          ? Image.memory(_iconBytes!, width: 76, height: 76, fit: BoxFit.cover)
          : Image(
              image: _fallbackIcon,
              width: 76,
              height: 76,
              fit: BoxFit.cover,
            ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, 8, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 品牌卡（浅色）
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: AppGradients.hero,
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.hero,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: iconWidget,
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Text(
                    _appName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  if (_loading)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.brand),
                    )
                  else
                    Tag(
                      label: 'v$displayedVersion',
                      color: AppColors.textPrimary,
                      background: AppColors.brandSoft,
                    ),
                  const SizedBox(height: AppSpacing.l),
                  const Text(
                    '高精度、可拖动的多源悬浮时钟',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.onLightMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // 功能亮点
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: '功能亮点',
                    subtitle: '为精准计时而设计',
                    icon: Icons.auto_awesome,
                  ),
                  const SizedBox(height: AppSpacing.l),
                  _featureRow(
                    Icons.timer,
                    AppColors.brand,
                    AppColors.brandSoft,
                    '10 毫秒级精度',
                    '支持 0.1 秒 / 0.01 秒切换，小数位高亮显示',
                  ),
                  _featureRow(
                    Icons.public,
                    AppColors.success,
                    AppColors.successSoft,
                    '多时间源同步',
                    '系统 / NTP / HTTP，展示与系统时间的偏差',
                  ),
                  _featureRow(
                    Icons.layers_outlined,
                    AppColors.accent,
                    const Color(0xFFF1EDFF),
                    '悬浮窗与画中画',
                    '可拖动、可锁定位置，随时在其他应用上层查看',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),

            // 开源仓库
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: '开源仓库',
                    subtitle: '基于 Flutter 构建',
                    icon: Icons.code,
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      _repoUrl,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Row(children: [
                    Expanded(
                      child: GradientButton(
                        label: '打开仓库',
                        icon: Icons.open_in_new,
                        onPressed: _openRepo,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: SoftButton(
                        label: '复制地址',
                        icon: Icons.copy,
                        onPressed: _copyRepo,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Center(
              child: Text(
                'FloatingClock · 让每一毫秒都清晰可见',
                style:
                    TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(
    IconData icon,
    Color color,
    Color background,
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
