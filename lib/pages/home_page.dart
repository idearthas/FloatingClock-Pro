import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:floating_clock/pages/about_page.dart';
import 'package:floating_clock/models/time_precision.dart';
import 'package:floating_clock/models/time_source.dart';
import 'package:floating_clock/theme/app_theme.dart';
import 'package:floating_clock/widgets/ui_kit.dart';

// Preset/source identifiers and defaults
const String _presetNtpAliyun = 'ntp.aliyun.com';
const String _presetNtpTencent = 'ntp.tencent.com';
const String _presetHttpMeituan =
    'https://cube.meituan.com/ipromotion/cube/toc/component/base/getServerCurrentTime';

const Map<String, String> _presetAliases = {
  _presetNtpAliyun: '阿里云',
  _presetNtpTencent: '腾讯',
  _presetHttpMeituan: '美团',
};

const Map<String, String> _meituanDefaultHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36'
};
const String _timeSourcesKey = 'time_sources_json';
const String _precisionPrefKey = 'time_precision';
const String _fractionColorPrefKey = 'fraction_color';

const List<ColorChoice> _fractionColorOptions = [
  ColorChoice('deep_red', '暗红', Color(0xFFC62828)),
  ColorChoice('amber', '琥珀', Color(0xFFEF6C00)),
  ColorChoice('teal', '青绿', Color(0xFF00796B)),
  ColorChoice('indigo', '靛蓝', Color(0xFF3949AB)),
  ColorChoice('purple', '紫罗兰', Color(0xFF8E24AA)),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _channel = MethodChannel('floating_clock');

  Timer? _uiTimer;
  Timer? _syncTimer;

  final List<TimeSource> _sources = [];
  int _selectedIndex = 0;
  // Tracks preset hosts that the user chose to hide/delete. Preset restore
  // will clear entries from this set.
  Set<String> _hiddenPresets = <String>{};
  bool _overlayRunning = false;
  bool _pipSupported = false;
  bool _isInPiP = false;
  bool _batteryOptimized = false;
  TimePrecision _timePrecision = TimePrecision.centisecond;
  String _fractionColorKey = _fractionColorOptions.first.key;
  // Overlay entry used to show an inline tooltip above other widgets (doesn't
  // change layout height). Only one sync-tooltip is shown at a time.
  OverlayEntry? _syncOverlayEntry;
  int? _syncOverlayIndex;
  // LayerLinks for each list item so the overlay tooltip can follow the
  // item's position during scrolling.
  final Map<int, LayerLink> _layerLinks = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handlePlatformCall);
    _initializePlatformState();
    _sources.add(TimeSource.system());

    // Load persisted NTP servers and hidden preset list; then ensure presets
    // are present unless the user explicitly hid them.
    _loadSavedServers().then((_) {
      final presets = <TimeSource>[
        TimeSource.ntp(_presetNtpAliyun,
            alias: _presetAliases[_presetNtpAliyun] ?? ''),
        TimeSource.ntp(_presetNtpTencent,
            alias: _presetAliases[_presetNtpTencent] ?? ''),
        TimeSource.http(_presetHttpMeituan,
            alias: _presetAliases[_presetHttpMeituan] ?? '',
            headers: _meituanDefaultHeaders),
      ];

      for (final preset in presets) {
        if (_hiddenPresets.contains(preset.host)) continue;
        final exists =
            _sources.any((s) => s.host == preset.host && s.type == preset.type);
        if (!exists) {
          setState(() => _sources.add(preset));

          // Try an immediate initial sync for the restored preset.
          if (preset.type == TimeSourceType.ntp) {
            _queryNtpOffset(preset.host).then((off) {
              if (off != null) {
                if (!mounted) return;
                setState(() {
                  final s = _sources.firstWhere((x) => x.host == preset.host,
                      orElse: () => _sources.last);
                  s.offsetMillis = off;
                  s.lastSync = DateTime.now();
                });
              }
            });
          } else if (preset.type == TimeSourceType.http) {
            _queryHttpOffset(preset).then((off) {
              if (off != null) {
                if (!mounted) return;
                setState(() {
                  final s = _sources.firstWhere((x) => x.host == preset.host,
                      orElse: () => _sources.last);
                  s.offsetMillis = off;
                  s.lastSync = DateTime.now();
                });
              }
            });
          }
        }
      }

      _restartUiTimer();
      _syncAllServers();
      _syncTimer =
          Timer.periodic(const Duration(seconds: 60), (_) => _syncAllServers());
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _syncTimer?.cancel();
    // Ensure any overlay is removed
    _removeSyncOverlay();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOverlayStatus();
      _checkBatteryOptimization();
    }
  }

  void _restartUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(_uiTickDuration, (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _onPrecisionChanged(TimePrecision precision) {
    if (_timePrecision == precision) return;
    setState(() => _timePrecision = precision);
    _restartUiTimer();
    unawaited(_persistPrecision(precision));
    if (_overlayRunning) {
      _updateOverlayForSelected();
    }
  }

  Future<void> _persistPrecision(TimePrecision precision) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_precisionPrefKey, precision.storageValue);
    } catch (_) {}
  }

  void _onFractionColorChanged(String key) {
    if (_fractionColorKey == key) return;
    setState(() => _fractionColorKey = key);
    unawaited(_persistFractionColor(key));
    if (_overlayRunning) {
      _updateOverlayForSelected();
    }
  }

  Future<void> _persistFractionColor(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fractionColorPrefKey, key);
    } catch (_) {}
  }

  ColorChoice get _fractionColorOption =>
      _fractionColorOptions.firstWhere((opt) => opt.key == _fractionColorKey,
          orElse: () => _fractionColorOptions.first);

  Color get _fractionColor => _fractionColorOption.color;

  TimeSource get _selectedSource {
    if (_sources.isEmpty) return TimeSource.system();
    final idx = _selectedIndex.clamp(0, _sources.length - 1);
    return _sources[idx];
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check,
            color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
      ]),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.danger : const Color(0xFF1B2338),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium)),
      margin: const EdgeInsets.all(AppSpacing.l),
      duration: const Duration(seconds: 3),
    ));
  }

  void _removeSyncOverlay() {
    try {
      _syncOverlayEntry?.remove();
    } catch (_) {}
    _syncOverlayEntry = null;
    _syncOverlayIndex = null;
  }

  void _showSyncOverlay(int index, LayerLink link, [Offset? tapGlobalPos]) {
    // Remove any existing overlay
    _removeSyncOverlay();

    final s = _sources[index];
    final text = _formatLastSync(s.lastSync);

    // Measure text to compute tooltip size
    final tp = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(fontSize: 11.5)),
        textDirection: Directionality.of(context))
      ..layout(maxWidth: 260 - 24);
    final textWidth = tp.width;
    final textHeight = tp.height;

    const horizontalPadding = 12.0;
    const verticalPadding = 9.0;
    final tooltipWidth = textWidth + horizontalPadding * 2;
    final tooltipHeight = textHeight + verticalPadding * 2;

    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;

    // Compute desired left so tooltip is centered on the tap (if provided),
    // and clamp to screen bounds.
    final centerX = tapGlobalPos?.dx ?? (screenWidth / 2);
    double left = centerX - tooltipWidth / 2;
    left = left.clamp(8.0, screenWidth - tooltipWidth - 8.0);
    const topOffset = 8.0;

    final offsetX = left - (centerX - tooltipWidth / 2);

    final top = (tapGlobalPos?.dy ?? 0) + topOffset;
    final tooltipRect = Rect.fromLTWH(left, top, tooltipWidth, tooltipHeight);

    _syncOverlayEntry = OverlayEntry(builder: (ctx) {
      return Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (ev) {
            // If pointer is outside the tooltip rect, remove the overlay but
            // do not prevent the event from reaching underlying widgets.
            if (!tooltipRect.contains(ev.position)) {
              _removeSyncOverlay();
              setState(() {});
            }
          },
          child: Stack(children: [
            CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomCenter,
              followerAnchor: Alignment.topCenter,
              offset: Offset(offsetX, topOffset),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 60, maxWidth: 260),
                    padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2338),
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      border: Border.all(color: const Color(0x22FFFFFF)),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 14,
                            offset: Offset(0, 5)),
                      ],
                    ),
                    child: Text(text,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    });

    Overlay.of(context).insert(_syncOverlayEntry!);
    _syncOverlayIndex = index;
    setState(() {});
  }

  void _toggleSyncOverlay(int index, LayerLink link, [Offset? tapGlobalPos]) {
    if (_syncOverlayIndex == index) {
      _removeSyncOverlay();
      setState(() {});
      return;
    }
    _showSyncOverlay(index, link, tapGlobalPos);
  }

  Future<void> _initializePlatformState() async {
    if (!Platform.isAndroid) return;
    bool overlayRunning = _overlayRunning;
    bool pipSupported = _pipSupported;
    try {
      final running = await _channel.invokeMethod<bool>('isOverlayRunning');
      if (running != null) overlayRunning = running;
    } catch (_) {}
    try {
      final supported = await _channel.invokeMethod<bool>('isPiPSupported');
      if (supported != null) pipSupported = supported;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _overlayRunning = overlayRunning;
      _pipSupported = pipSupported;
    });
    await _checkBatteryOptimization();
  }

  Future<void> _refreshOverlayStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final running = await _channel.invokeMethod<bool>('isOverlayRunning');
      if (!mounted) return;
      if (running != null && running != _overlayRunning) {
        setState(() => _overlayRunning = running);
      }
    } catch (_) {}
  }

  /// 部分 ROM 会在锁屏后查杀后台服务，检查是否已加入电池优化白名单。
  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    try {
      final ignored =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      if (!mounted) return;
      final needGuide = ignored == false;
      if (needGuide != _batteryOptimized) {
        setState(() => _batteryOptimized = needGuide);
      }
    } catch (_) {}
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      _showSnack('无法打开电池优化设置，请在系统设置中手动关闭', error: true);
    }
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onOverlayStopped':
        if (mounted && _overlayRunning) {
          setState(() => _overlayRunning = false);
        }
        break;
      case 'onPiPChanged':
        bool inPiP = false;
        final args = call.arguments;
        if (args is Map) {
          final value = args['isInPiP'];
          if (value is bool) inPiP = value;
        } else if (args is bool) {
          inPiP = args;
        }
        if (!mounted) return;
        setState(() => _isInPiP = inPiP);
        if (!inPiP) {
          // When leaving PiP, refresh overlay status in case service resumed.
          await _refreshOverlayStatus();
        }
        break;
    }
  }

  Future<void> _toggleOverlay() async {
    if (_overlayRunning) {
      final success = await _stopOverlay();
      if (!mounted) return;
      if (success) {
        setState(() => _overlayRunning = false);
      }
    } else {
      final success = await _startOverlayForSelected();
      if (!mounted) return;
      if (success) {
        setState(() => _overlayRunning = true);
      }
    }
  }

  Future<void> _enterPictureInPicture() async {
    if (!_pipSupported) {
      _showSnack('当前设备不支持画中画模式', error: true);
      return;
    }
    if (_overlayRunning) {
      final stopped = await _stopOverlay();
      if (!mounted) return;
      if (stopped) {
        setState(() => _overlayRunning = false);
      }
    }
    try {
      final entered = await _channel.invokeMethod<bool>('enterPiP');
      if (entered != null && !entered) {
        _showSnack('无法进入画中画模式，请检查系统设置', error: true);
      }
    } on PlatformException catch (e) {
      debugPrint('enterPiP failed: $e');
      _showSnack('进入画中画失败', error: true);
    }
  }

  Future<void> _syncAllServers() async {
    for (var i = 0; i < _sources.length; i++) {
      final s = _sources[i];
      if (s.isSystem) continue;

      int? off;
      if (s.type == TimeSourceType.ntp) {
        off = await _queryNtpOffset(s.host);
      } else if (s.type == TimeSourceType.http) {
        off = await _queryHttpOffset(s);
      }

      if (off != null) {
        setState(() {
          s.offsetMillis = off!;
          s.lastSync = DateTime.now();
        });
      } else {
        debugPrint(
            '${s.type == TimeSourceType.ntp ? 'NTP' : 'HTTP'}: sync failed for ${s.host}');
      }
    }
  }

  Future<int?> _queryNtpOffset(String host,
      {int port = 123,
      Duration timeout = const Duration(seconds: 2),
      int attempts = 5}) async {
    List<_NtpSample> samples = [];
    for (var i = 0; i < attempts; i++) {
      debugPrint(
          'NTP: $host - attempt ${i + 1}/$attempts (timeout=${timeout.inMilliseconds}ms)');
      final s = await _queryNtpOnce(host, port: port, timeout: timeout);
      if (s != null) {
        samples.add(s);
        // if we got a low-delay sample, prefer it and stop early
        if (s.delay >= 0 && s.delay < 100) {
          debugPrint(
              'NTP: $host - early stop on low-delay sample (${s.delay} ms)');
          break;
        }
      }
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (samples.isEmpty) {
      debugPrint('NTP: $host - no successful samples after $attempts attempts');
      return null;
    }
    samples.sort((a, b) => a.delay.compareTo(b.delay));
    // Use a small set of the lowest-delay samples and return their median
    // offset to reduce sensitivity to a single lucky/erroneous sample.
    final takeN = samples.length >= 3 ? 3 : samples.length;
    final bestOffsets = samples.take(takeN).map((s) => s.offset).toList()
      ..sort();
    final median = bestOffsets[bestOffsets.length ~/ 2];
    debugPrint(
        'NTP: $host - median offset=$median (used $takeN of ${samples.length} samples, best delay=${samples.first.delay} ms)');
    return median;
  }

  Future<_NtpSample?> _queryNtpOnce(String host,
      {int port = 123, Duration timeout = const Duration(seconds: 2)}) async {
    try {
      // Try IPv4 first, then IPv6, then any. This can help on devices where
      // one address family is preferred or where the lookup behaves differently.
      List<InternetAddress> addrs = [];
      try {
        addrs =
            await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
        if (addrs.isEmpty) {
          addrs = await InternetAddress.lookup(host,
              type: InternetAddressType.IPv6);
        }
        if (addrs.isEmpty) addrs = await InternetAddress.lookup(host);
      } catch (e) {
        debugPrint('NTP: DNS lookup failed for $host: $e');
        return null;
      }
      if (addrs.isEmpty) return null;
      final addr = addrs.firstWhere((a) => a.type == InternetAddressType.IPv4,
          orElse: () => addrs.first);

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final data = Uint8List(48);
      data[0] = 0x1B;

      // Use microsecond precision when creating the transmit timestamp to
      // reduce quantization error on the fractional part.
      final t1us = DateTime.now().microsecondsSinceEpoch;
      final t1Sec = (t1us ~/ 1000000) + 2208988800;
      final t1Frac = ((t1us % 1000000) * 0x100000000) ~/ 1000000;

      final bd =
          ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
      bd.setUint32(40, (t1Sec & 0xffffffff), Endian.big);
      bd.setUint32(44, (t1Frac & 0xffffffff), Endian.big);

      final completer = Completer<_NtpSample?>();

      debugPrint(
          'NTP: sending request to $host -> ${addr.address}:$port t1us=$t1us');
      socket.send(data, addr, port);

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg == null) return;
          final r = dg.data;
          if (r.length < 48) return;
          final t4ms = DateTime.now().millisecondsSinceEpoch;
          // `dg.data` (a `Uint8List`) may be a view into a larger buffer,
          // so create a ByteData that starts at the datagram's offset.
          final rb = ByteData.view(r.buffer, r.offsetInBytes, r.lengthInBytes);

          final secT1 = rb.getUint32(24, Endian.big);
          final fracT1 = rb.getUint32(28, Endian.big);
          final secT2 = rb.getUint32(32, Endian.big);
          final fracT2 = rb.getUint32(36, Endian.big);
          final secT3 = rb.getUint32(40, Endian.big);
          final fracT3 = rb.getUint32(44, Endian.big);

          // Basic response validation: mode should be server (4), and stratum
          // should not be 0 (KOD / Kiss-o'-Death). Also ensure the originate
          // timestamp matches what we sent to avoid accepting replayed/other
          // responses from middleboxes.
          final mode = r[0] & 0x7;
          final stratum = rb.getUint8(1);
          if (mode != 4) {
            debugPrint('NTP: $host - unexpected mode=$mode, ignoring response');
            return;
          }
          if (stratum == 0) {
            debugPrint('NTP: $host - stratum=0 (KOD?), ignoring response');
            return;
          }

          if (secT1 != (t1Sec & 0xffffffff) ||
              fracT1 != (t1Frac & 0xffffffff)) {
            debugPrint(
                'NTP: $host - originate timestamp mismatch, ignoring response (got sec=$secT1 frac=$fracT1, expected sec=${t1Sec & 0xffffffff} frac=${t1Frac & 0xffffffff})');
            return;
          }

          int msFromNtp(int sec, int frac) {
            final unixSec = sec - 2208988800;
            final ms = unixSec * 1000 + ((frac * 1000) ~/ 0x100000000);
            return ms;
          }

          final t1 = msFromNtp(secT1, fracT1);
          final t2 = msFromNtp(secT2, fracT2);
          final t3 = msFromNtp(secT3, fracT3);
          final t4 = t4ms;

          final offset = ((t2 - t1) + (t3 - t4)) ~/ 2;
          final delay = ((t4 - t1) - (t3 - t2));
          debugPrint(
              'NTP: $host recv: t1=$t1 t2=$t2 t3=$t3 t4=$t4 offset=$offset delay=$delay');
          if (!completer.isCompleted) {
            completer.complete(_NtpSample(offset: offset, delay: delay));
          }
          socket.close();
        }
      });

      Future.delayed(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(null);
          socket.close();
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('NTP: $host error: $e');
      return null;
    }
  }

  // Query an HTTP/JSON endpoint that returns a server timestamp (ms since epoch)
  // in a `data` field. Returns the offset (server_ms - local_ms) or null.
  Future<int?> _queryHttpOffset(TimeSource s,
      {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final uri = Uri.parse(s.host);
      final client = HttpClient();

      final req = await client.getUrl(uri).timeout(timeout);
      // Apply optional headers (e.g. custom User-Agent for some endpoints)
      if (s.headers != null) {
        s.headers!.forEach((k, v) {
          try {
            req.headers.set(k, v);
          } catch (_) {}
        });
      }

      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) {
        debugPrint('HTTP: ${s.host} status=${resp.statusCode}');
        client.close(force: true);
        return null;
      }
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      client.close();

      final m = jsonDecode(body);
      if (m == null || m is! Map || !m.containsKey('data')) {
        debugPrint('HTTP: ${s.host} unexpected JSON (no data field)');
        return null;
      }
      final dyn = m['data'];
      int serverMs;
      if (dyn is int) {
        serverMs = dyn;
      } else if (dyn is num) {
        serverMs = dyn.toInt();
      } else {
        serverMs = int.tryParse(dyn.toString()) ?? 0;
      }
      if (serverMs == 0) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final offset = serverMs - now;
      debugPrint('HTTP: ${s.host} serverMs=$serverMs offset=$offset');
      return offset;
    } catch (e) {
      debugPrint('HTTP: ${s.host} error: $e');
      return null;
    }
  }

  Future<bool> _startOverlayForSelected() async {
    try {
      final bool has =
          await _channel.invokeMethod<bool>('hasPermission') ?? false;
      if (!has) {
        await _channel.invokeMethod('requestPermission');
        _showSnack('请在系统设置允许「在其他应用上层显示」后再次点击开始',
            error: true);
        return false;
      }
      // Android 13+ 通知权限：让前台服务通知可见，用户能从通知栏快速停止。
      try {
        await _channel.invokeMethod('requestNotificationPermission');
      } catch (_) {}

      final s = _sources[_selectedIndex];
      final offset = s.isSystem ? 0 : s.offsetMillis;
      final label = s.isSystem ? '' : (s.alias.isNotEmpty ? s.alias : s.host);
      await _channel.invokeMethod('startOverlay', {
        'offset': offset,
        'label': label,
        'precision': _timePrecision.storageValue,
        'fractionColor': _fractionColor.toARGB32(),
      });
      return true;
    } on PlatformException catch (e) {
      debugPrint('PlatformException: $e');
    } catch (e) {
      debugPrint('startOverlay error: $e');
    }
    return false;
  }

  Future<bool> _stopOverlay() async {
    try {
      await _channel.invokeMethod('stopOverlay');
      return true;
    } on PlatformException catch (e) {
      debugPrint('PlatformException: $e');
    } catch (e) {
      debugPrint('stopOverlay error: $e');
    }
    return false;
  }

  // Update running overlay to reflect the currently selected source.
  Future<void> _updateOverlayForSelected() async {
    if (!_overlayRunning) return;
    try {
      final s = _sources[_selectedIndex];
      final offset = s.isSystem ? 0 : s.offsetMillis;
      final label = s.isSystem ? '' : (s.alias.isNotEmpty ? s.alias : s.host);
      await _channel.invokeMethod('startOverlay', {
        'offset': offset,
        'label': label,
        'precision': _timePrecision.storageValue,
        'fractionColor': _fractionColor.toARGB32(),
      });
    } on PlatformException catch (e) {
      debugPrint('PlatformException: $e');
    }
  }

  // ---------------------------------------------------------------------
  // 时间源编辑 / 删除 / 恢复预设
  // ---------------------------------------------------------------------

  InputDecoration _inputDecoration(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 19, color: AppColors.brand),
      filled: true,
      fillColor: AppColors.surfaceAlt,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
      ),
    );
  }

  void _showSourceEditorDialog(int? index) {
    final editing = index != null;
    final s = editing ? _sources[index] : null;
    final controllerHost =
        TextEditingController(text: s?.host ?? 'ntp.aliyun.com');
    final controllerAlias = TextEditingController(text: s?.alias ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: const Icon(Icons.dns, size: 19, color: AppColors.brand),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(
                    editing ? '编辑 NTP 服务器' : '添加 NTP 服务器',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                CircleIconButton(
                  icon: Icons.close,
                  size: 30,
                  color: AppColors.textTertiary,
                  background: AppColors.surfaceAlt,
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
              ),
              const SizedBox(height: 6),
              const Text(
                '保存前会先测试该服务器是否可用',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: controllerHost,
                decoration:
                    _inputDecoration('主机', 'ntp.example.com', Icons.language),
              ),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: controllerAlias,
                decoration:
                    _inputDecoration('别名', '可填写易记名称', Icons.label_outline),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(children: [
                Expanded(
                  child: SoftButton(
                    label: '取消',
                    icon: Icons.close,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: GradientButton(
                    label: editing ? '保存' : '添加',
                    icon: Icons.check,
                    onPressed: () => _confirmSourceEditor(
                      ctx: ctx,
                      index: index,
                      host: controllerHost.text.trim(),
                      alias: controllerAlias.text.trim(),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSourceEditor({
    required BuildContext ctx,
    required int? index,
    required String host,
    required String alias,
  }) async {
    if (host.isEmpty) return;

    // 测试服务器时展示进度
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 26, vertical: 24),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 14),
            Text('正在测试 NTP 服务器…',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );

    final off = await _queryNtpOffset(host,
        attempts: 2, timeout: const Duration(milliseconds: 800));

    if (!mounted) return;
    // 关闭进度弹窗
    Navigator.of(context, rootNavigator: true).pop();

    if (off == null) {
      _showSnack('无法从 $host 获取 NTP 时间，请检查主机或网络', error: true);
      return;
    }

    setState(() {
      final source = TimeSource.ntp(host, alias: alias)
        ..offsetMillis = off
        ..lastSync = DateTime.now();
      if (index != null) {
        _sources[index] = source;
      } else {
        _sources.add(source);
      }
    });
    _layerLinks.clear();
    _removeSyncOverlay();
    await _saveServers();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _removeSource(int index) async {
    final removedHost = _sources[index].host;
    setState(() {
      if (_selectedIndex == index) {
        _selectedIndex = 0;
      } else if (_selectedIndex > index) {
        _selectedIndex -= 1;
      }
      _sources.removeAt(index);
    });
    _removeSyncOverlay();
    _layerLinks.clear();
    await _saveServers();
    if (_isPresetHost(removedHost)) {
      _hiddenPresets.add(removedHost);
      await _saveHiddenPresets();
    }
  }

  void _selectSource(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    if (_overlayRunning) _updateOverlayForSelected();
  }

  void _restorePresetsDialog() {
    final missing = <String>[];
    if (!_sources.any((s) => s.host == _presetNtpAliyun)) {
      missing.add(_presetNtpAliyun);
    }
    if (!_sources.any((s) => s.host == _presetNtpTencent)) {
      missing.add(_presetNtpTencent);
    }
    if (!_sources.any((s) => s.host == _presetHttpMeituan)) {
      missing.add(_presetHttpMeituan);
    }

    if (missing.isEmpty) {
      _showSnack('没有缺失的预设需要恢复');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('恢复预设源',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: AppSpacing.m),
              Text(
                '将恢复：${missing.map((h) => _presetAliases[h] ?? h).join('、')}',
                style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(children: [
                Expanded(
                  child: SoftButton(
                    label: '取消',
                    icon: Icons.close,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: GradientButton(
                    label: '恢复',
                    icon: Icons.restore,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _restorePresets();
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restorePresets() async {
    final toAdd = <TimeSource>[];
    if (!_sources.any((s) => s.host == _presetNtpAliyun)) {
      toAdd.add(TimeSource.ntp(_presetNtpAliyun,
          alias: _presetAliases[_presetNtpAliyun] ?? ''));
    }
    if (!_sources.any((s) => s.host == _presetNtpTencent)) {
      toAdd.add(TimeSource.ntp(_presetNtpTencent,
          alias: _presetAliases[_presetNtpTencent] ?? ''));
    }
    if (!_sources.any((s) => s.host == _presetHttpMeituan)) {
      toAdd.add(TimeSource.http(_presetHttpMeituan,
          alias: _presetAliases[_presetHttpMeituan] ?? '',
          headers: _meituanDefaultHeaders));
    }

    if (toAdd.isEmpty) return;

    setState(() {
      _sources.addAll(toAdd);
    });

    // Clear these hosts from hidden presets (if user previously hid them)
    for (final s in toAdd) {
      _hiddenPresets.remove(s.host);
    }
    await _saveHiddenPresets();

    // Persist NTP additions and run an immediate sync for added presets.
    await _saveServers();
    for (final s in toAdd) {
      if (s.type == TimeSourceType.ntp) {
        final off = await _queryNtpOffset(s.host);
        if (off != null) {
          setState(() {
            final ts = _sources.firstWhere((x) => x.host == s.host);
            ts.offsetMillis = off;
            ts.lastSync = DateTime.now();
          });
        }
      } else if (s.type == TimeSourceType.http) {
        final off = await _queryHttpOffset(s);
        if (off != null) {
          setState(() {
            final ts = _sources.firstWhere((x) => x.host == s.host);
            ts.offsetMillis = off;
            ts.lastSync = DateTime.now();
          });
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // 时间显示 helpers
  // ---------------------------------------------------------------------

  ({String prefix, String fraction}) _timePartsForSource(TimeSource s) {
    final now = DateTime.now().add(Duration(milliseconds: s.offsetMillis));
    final fraction = _timePrecision == TimePrecision.centisecond
        ? (now.millisecond ~/ 10).toString().padLeft(2, '0')
        : (now.millisecond ~/ 100).toString();
    final prefix =
        '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}';
    return (prefix: prefix, fraction: fraction);
  }

  String _precisionLabel(TimePrecision precision) {
    switch (precision) {
      case TimePrecision.centisecond:
        return '0.01 秒';
      case TimePrecision.decisecond:
        return '0.1 秒';
    }
  }

  String _formatLastSync(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.toLocal();
    return '最近同步 ${_twoDigits(d.month)}-${_twoDigits(d.day)} ${_twoDigits(d.hour)}:${_twoDigits(d.minute)}:${_twoDigits(d.second)}';
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatOffset(int ms) {
    if (ms.abs() < 1000) return '${ms >= 0 ? '+' : '-'}${ms.abs()} ms';
    final s = ms / 1000.0;
    return '${ms >= 0 ? '+' : '-'}${s.toStringAsFixed(2)} s';
  }

  Duration get _uiTickDuration => _timePrecision == TimePrecision.centisecond
      ? const Duration(milliseconds: 10)
      : const Duration(milliseconds: 100);

  Widget _buildColoredTimeText(TimeSource s,
      {TextStyle? style, TextAlign? textAlign}) {
    final parts = _timePartsForSource(s);
    final fractionStyle =
        (style ?? const TextStyle()).copyWith(color: _fractionColor);
    return Text.rich(
        TextSpan(children: [
          TextSpan(text: '${parts.prefix}.'),
          TextSpan(text: parts.fraction, style: fractionStyle),
        ]),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign);
  }

  /// 深色时钟卡上的大号时间：把用户选的小数颜色提亮，保证在深底上可读。
  Widget _buildHeroTimeText(TimeSource s, {double fontSize = 44}) {
    final parts = _timePartsForSource(s);
    final bright = HSLColor.fromColor(_fractionColor)
        .withLightness(0.68)
        .toColor();
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '${parts.prefix}.'),
        TextSpan(text: parts.fraction, style: TextStyle(color: bright)),
      ]),
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 1,
    );
  }

  // ---------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------

  Future<void> _loadSavedServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedColor = prefs.getString(_fractionColorPrefKey);
      if (savedColor != null &&
          _fractionColorOptions.any((opt) => opt.key == savedColor)) {
        setState(() => _fractionColorKey = savedColor);
      }
      final loadedPrecision =
          precisionFromStorage(prefs.getString(_precisionPrefKey));
      if (loadedPrecision != _timePrecision) {
        setState(() => _timePrecision = loadedPrecision);
      }
      // First try unified format (all sources)
      final rawAll = prefs.getString(_timeSourcesKey);
      if (rawAll != null && rawAll.isNotEmpty) {
        try {
          final list = jsonDecode(rawAll) as List<dynamic>;
          setState(() {
            for (final it in list) {
              final m = it as Map<String, dynamic>;
              final source = TimeSource.fromJson(m);
              _sources.add(source);
            }
          });
        } catch (_) {
          // fall back to legacy handling below
        }
      } else {
        // legacy format: NTP-only
        final raw = prefs.getString('ntp_servers_json');
        if (raw != null && raw.isNotEmpty) {
          try {
            final list = jsonDecode(raw) as List<dynamic>;
            setState(() {
              for (final it in list) {
                final m = it as Map<String, dynamic>;
                _sources.add(
                    TimeSource.ntp(m['host'] ?? '', alias: m['alias'] ?? ''));
              }
            });
          } catch (_) {}
        }
      }

      // Load hidden preset list (hosts the user explicitly removed).
      final rawHidden = prefs.getString('hidden_presets_json');
      if (rawHidden != null && rawHidden.isNotEmpty) {
        try {
          final arr = jsonDecode(rawHidden) as List<dynamic>;
          _hiddenPresets = arr.map((e) => e.toString()).toSet();
        } catch (_) {
          _hiddenPresets = <String>{};
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _saveServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Persist all non-system sources (NTP + HTTP) under a unified key.
      final listAll = _sources
          .where((s) => !s.isSystem)
          .map((s) => {
                'host': s.host,
                'alias': s.alias,
                'type': s.type == TimeSourceType.http ? 'http' : 'ntp',
                if (s.headers != null) 'headers': s.headers,
              })
          .toList();
      prefs.setString(_timeSourcesKey, jsonEncode(listAll));

      // Also update legacy NTP-only key for backward compatibility.
      final listNtp = listAll
          .where((m) => (m['type'] ?? 'ntp') == 'ntp')
          .map((m) => {'host': m['host'], 'alias': m['alias']})
          .toList();
      prefs.setString('ntp_servers_json', jsonEncode(listNtp));
    } catch (e) {
      // ignore
    }
  }

  Future<void> _saveHiddenPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.setString(
          'hidden_presets_json', jsonEncode(_hiddenPresets.toList()));
    } catch (e) {
      // ignore
    }
  }

  bool _isPresetHost(String host) {
    return host == _presetNtpAliyun ||
        host == _presetNtpTencent ||
        host == _presetHttpMeituan;
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isInPiP) return _buildPipView();

    return Scaffold(
      appBar: AppBar(
        title: const Text('悬浮时间'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.l),
            child: CircleIconButton(
              icon: Icons.info_outline,
              background: AppColors.surface,
              color: AppColors.textSecondary,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, 8, AppSpacing.xl, AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeroCard(),
                  if (_batteryOptimized && Platform.isAndroid) ...[
                    const SizedBox(height: AppSpacing.l),
                    InfoBanner(
                      title: '建议关闭电池优化',
                      message: '系统可能会在锁屏后回收后台服务，导致悬浮时钟中断。将应用加入电池优化白名单可保持长期运行。',
                      actionLabel: '去设置',
                      onAction: _requestIgnoreBatteryOptimizations,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.l),
                  _buildSettingsCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSourcesSection(),
                ],
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final source = _selectedSource;
    final rawLabel = source.isSystem
        ? '系统时间'
        : (source.alias.isNotEmpty ? source.alias : source.host);
    final label =
        rawLabel.length > 12 ? '${rawLabel.substring(0, 12)}…' : rawLabel;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadows.hero,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Stack(
          children: [
            Positioned(
              right: -46,
              top: -58,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06), width: 22),
                ),
              ),
            ),
            Positioned(
              right: 56,
              bottom: -74,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brand.withValues(alpha: 0.12),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.schedule,
                        size: 15, color: Colors.white),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  const Text('实时时钟',
                      style: TextStyle(
                          color: AppColors.onDarkMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  StatusPill(running: _overlayRunning),
                ]),
                const SizedBox(height: AppSpacing.xl),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _buildHeroTimeText(source),
                ),
                const SizedBox(height: AppSpacing.l),
                Row(children: [
                  Tag(
                    label: label,
                    color: Colors.white,
                    background: const Color(0x1FFFFFFF),
                    icon: source.isSystem ? Icons.computer : Icons.language,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  if (!source.isSystem)
                    Flexible(
                      child: Tag(
                        label: '偏差 ${_formatOffset(source.offsetMillis)}',
                        color: AppColors.heroFraction,
                        background: const Color(0x26FFC46B),
                      ),
                    ),
                  const Spacer(),
                  Tag(
                    label: _precisionLabel(_timePrecision),
                    color: AppColors.onDarkMuted,
                    background: const Color(0x14FFFFFF),
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: '显示设置',
            subtitle: '精度与小数位高亮',
            icon: Icons.tune,
          ),
          const SizedBox(height: AppSpacing.xl),
          _fieldLabel('显示精度'),
          const SizedBox(height: AppSpacing.s),
          OptionSegment<TimePrecision>(
            items: TimePrecision.values
                .map((p) =>
                    SegmentItem(value: p, label: _precisionLabel(p)))
                .toList(),
            value: _timePrecision,
            onChanged: _onPrecisionChanged,
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(children: [
            _fieldLabel('小数位颜色'),
            const Spacer(),
            Text(_fractionColorOption.label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand)),
          ]),
          const SizedBox(height: AppSpacing.m),
          ColorPickerRow(
            options: _fractionColorOptions,
            selectedKey: _fractionColorKey,
            onChanged: _onFractionColorChanged,
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildSourcesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SectionHeader(
            title: '时间源',
            subtitle: '共 ${_sources.length} 个 · 选择悬浮窗的时间基准',
            icon: Icons.language,
            actions: [
              CircleIconButton(
                icon: Icons.add,
                tooltip: '添加 NTP 服务器',
                onPressed: () => _showSourceEditorDialog(null),
              ),
              const SizedBox(width: AppSpacing.s),
              CircleIconButton(
                icon: Icons.restore,
                tooltip: '恢复预设源',
                onPressed: _restorePresetsDialog,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        ...List.generate(
          _sources.length,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.m),
            child: _buildSourceCard(index),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceCard(int index) {
    final s = _sources[index];
    final selected = index == _selectedIndex;
    final name = s.isSystem
        ? '系统时间'
        : (s.alias.isNotEmpty ? s.alias : s.host);
    final typeLabel = s.type == TimeSourceType.ntp
        ? 'NTP'
        : (s.type == TimeSourceType.http ? 'HTTP' : 'SYS');
    final typeColor = s.type == TimeSourceType.ntp
        ? AppColors.brand
        : (s.type == TimeSourceType.http ? AppColors.success : AppColors.textTertiary);
    final typeBg = s.type == TimeSourceType.ntp
        ? AppColors.brandSoft
        : (s.type == TimeSourceType.http
            ? AppColors.successSoft
            : AppColors.surfaceAlt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectSource(index),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.brand.withValues(alpha: 0.14),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Colors.white : Colors.transparent,
                    border: Border.all(
                      color: selected ? AppColors.brand : AppColors.borderStrong,
                      width: selected ? 5 : 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      )),
                ),
                Tag(label: typeLabel, color: typeColor, background: typeBg),
              ]),
              if (!s.isSystem && s.host != name)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: Text(s.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textTertiary)),
                ),
              const SizedBox(height: AppSpacing.m),
              Row(children: [
                Expanded(
                  child: _buildColoredTimeText(
                    s,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (!s.isSystem)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.s),
                    child: Tag(
                      label: _formatOffset(s.offsetMillis),
                      color: AppColors.textSecondary,
                      background: selected
                          ? Colors.white
                          : AppColors.surfaceAlt,
                    ),
                  ),
                if (s.type == TimeSourceType.ntp)
                  CircleIconButton(
                    icon: Icons.edit,
                    size: 30,
                    tooltip: '编辑',
                    onPressed: () => _showSourceEditorDialog(index),
                  ),
                if (!s.isSystem) ...[
                  const SizedBox(width: 6),
                  CircleIconButton(
                    icon: Icons.delete_outline,
                    size: 30,
                    tooltip: '删除',
                    color: AppColors.danger,
                    background: AppColors.dangerSoft,
                    onPressed: () => _removeSource(index),
                  ),
                ],
                if (!s.isSystem && s.lastSync != null) ...[
                  const SizedBox(width: 6),
                  _buildSyncInfoButton(index, selected),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// 同步信息 tooltip 需要点击的全局坐标，因此直接用 InkResponse.onTapDown
  /// 转发（比外层 GestureDetector 更可靠，不会被子按钮的点击手势抢走）。
  Widget _buildSyncInfoButton(int index, bool selected) {
    final link = _layerLinks.putIfAbsent(index, () => LayerLink());
    return CompositedTransformTarget(
      link: link,
      child: Tooltip(
        message: '同步时间',
        child: Material(
          color: selected ? Colors.white : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: InkResponse(
            radius: 16,
            onTapDown: (details) =>
                _toggleSyncOverlay(index, link, details.globalPosition),
            child: const SizedBox(
              width: 30,
              height: 30,
              child: Icon(Icons.error_outline,
                  size: 16, color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.m, AppSpacing.xl, AppSpacing.m),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.floating,
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          GradientButton(
            expand: true,
            label: _overlayRunning ? '停止悬浮' : '开始悬浮',
            icon: _overlayRunning ? Icons.stop : Icons.play_arrow,
            danger: _overlayRunning,
            onPressed: _toggleOverlay,
          ),
          const SizedBox(width: AppSpacing.m),
          SoftButton(
            expand: true,
            label: '画中画',
            icon: Icons.picture_in_picture_alt,
            onPressed: _pipSupported ? _enterPictureInPicture : null,
          ),
        ]),
      ),
    );
  }

  Widget _buildPipView() {
    final source = _selectedSource;
    final label = source.isSystem
        ? '系统时间'
        : (source.alias.isNotEmpty ? source.alias : source.host);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.hero),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildHeroTimeText(source, fontSize: 34),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NtpSample {
  final int offset;
  final int delay;
  _NtpSample({required this.offset, required this.delay});
}
