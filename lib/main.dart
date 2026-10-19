import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;
import 'core.dart';

@JS('PoseBridge')
external _Bridge get _bridge;

extension type _Bridge._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> start(JSFunction cb, int fps);
  external void stop();
  external web.HTMLVideoElement get video;
}

void main() {
  ui_web.platformViewRegistry.registerViewFactory('cam', (int _) => _bridge.video);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'رکعت‌شمار هوشمند',
        theme: ThemeData(useMaterial3: true, fontFamily: 'Vazirmatn', colorSchemeSeed: const Color(0xFF1F5F54)),
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const Home(),
      );
}

enum Stage { intro, setup, calib, run }

const order = [Pose.qiyam, Pose.ruku, Pose.sujud, Pose.julus];
const faName = {Pose.qiyam: 'قیام', Pose.ruku: 'رکوع', Pose.sujud: 'سجده', Pose.julus: 'جلسه', Pose.unknown: '…'};
const faHow = {
  Pose.qiyam: 'صاف بایستید',
  Pose.ruku: 'به رکوع بروید',
  Pose.sujud: 'به سجده بروید',
  Pose.julus: 'بنشینید (جلسه)',
};

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Stage stage = Stage.intro;
  List<dynamic> prayers = [];
  Map<String, dynamic>? prayer;
  bool hide = false, capturing = false;
  String? hint = 'در حال آماده‌سازی…', error;
  String cmsg = '';
  int ci = 0;
  Pose pose = Pose.unknown;
  double conf = 0;
  final cal = Calibration();
  RakatCounter? counter;
  final audio = AudioPlayer();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/prayers.json').then((s) => setState(() {
          prayers = jsonDecode(s);
          prayer = prayers.first;
        }));
  }

  @override
  void dispose() {
    timer?.cancel();
    _bridge.stop();
    super.dispose();
  }

  void _sfx(String e) => audio.play(AssetSource('audio/$e.mp3')).catchError((_) {});

  Future<void> _start() async {
    setState(() => error = null);
    try {
      await _bridge.start(((JSString s) => _onPose(s.toDart)).toJS, 12).toDart;
      setState(() => stage = Stage.setup);
    } catch (_) {
      setState(() => error = 'دسترسی به دوربین یا بارگذاری مدل ممکن نشد. اجازهٔ دوربین را بررسی کنید.');
    }
  }

  void _onPose(String s) {
    List<List<double>>? l;
    if (s.isNotEmpty) {
      l = [for (final e in jsonDecode(s) as List) [for (final n in e as List) (n as num).toDouble()]];
    }
    final f = l == null ? null : Frame.from(l);
    setState(() {
      hint = l == null ? 'شما در کادر دیده نمی‌شوید' : framingHint(l, standing: stage == Stage.setup);
      if (f == null) { pose = Pose.unknown; return; }
      if (stage == Stage.calib && capturing) cal.add(order[ci], f);
      if (stage == Stage.run && cal.ready) {
        final r = cal.classify(f);
        pose = r.$1;
        conf = r.$2;
        counter!.update(pose);
      }
    });
  }

  void _beginCalib() {
    cal.reset();
    ci = 0;
    setState(() { stage = Stage.calib; error = null; });
    _nextCalib();
  }

  void _nextCalib() {
    if (ci >= order.length) {
      if (cal.finish()) {
        counter = RakatCounter(prayer!['rakats'] as int)..onEvent = _sfx;
        setState(() => stage = Stage.run);
      } else {
        setState(() { stage = Stage.setup; error = 'کالیبراسیون کامل نشد. کادر را بررسی و دوباره تلاش کنید.'; });
      }
      return;
    }
    var t = 5;
    setState(() { cmsg = '$t'; capturing = false; });
    timer = Timer.periodic(const Duration(seconds: 1), (x) {
      t--;
      if (t >= 1) {
        setState(() => cmsg = '$t');
      } else if (t == 0) {
        setState(() { capturing = true; cmsg = 'ثبت…'; });
      } else if (t == -3) {
        x.cancel();
        setState(() => capturing = false);
        ci++;
        _nextCalib();
      }
    });
  }

  void _stop() {
    timer?.cancel();
    _bridge.stop();
    setState(() { stage = Stage.intro; pose = Pose.unknown; });
  }

  Widget _preview([double h = 280]) => SizedBox(
        height: h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: hide
              ? const ColoredBox(color: Color(0x14000000), child: Center(child: Icon(Icons.person_outline, size: 96)))
              : const HtmlElementView(viewType: 'cam'),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (stage) {
              Stage.intro => _intro(),
              Stage.setup => _setup(),
              Stage.calib => _calib(),
              Stage.run => _run(),
            },
          ),
        ),
      );

  Widget _intro() => ListView(children: [
        Text('رکعت‌شمار هوشمند', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('تصویر شما فقط روی همین دستگاه پردازش می‌شود. هیچ تصویری ذخیره یا ارسال نمی‌شود و برنامه بدون اینترنت کار می‌کند.'),
        const SizedBox(height: 24),
        const Text('نماز'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final p in prayers)
            ChoiceChip(
              label: Text('${p['name']} (${p['rakats']} رکعت)'),
              selected: prayer == p,
              onSelected: (_) => setState(() => prayer = p),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('پنهان‌کردن پیش‌نمایش دوربین'),
          subtitle: const Text('دوربین کار می‌کند ولی تصویر شما روی صفحه دیده نمی‌شود'),
          value: hide,
          onChanged: (v) => setState(() => hide = v),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        FilledButton(onPressed: prayer == null ? null : _start, child: const Text('روشن‌کردن دوربین')),
      ]);

  Widget _setup() => ListView(children: [
        _preview(360),
        const SizedBox(height: 16),
        Text(hint ?? 'چیدمان مناسب است', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: hint == null ? Colors.green.shade800 : null)),
        const SizedBox(height: 8),
        const Text('گوشی را از پهلو، حدود ۲ تا ۳ متر دورتر، هم‌سطح کمر یا کمی بالاتر روی جای ثابتی بگذارید. کل بدن از سر تا پا باید دیده شود.'),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(onPressed: hint == null ? _beginCalib : null, child: const Text('ادامه: معرفی حالت‌ها')),
        TextButton(onPressed: _stop, child: const Text('بازگشت')),
      ]);

  Widget _calib() => Column(children: [
        _preview(300),
        const Spacer(),
        Text('${ci + 1} از ${order.length}'),
        Text(faHow[order[ci.clamp(0, 3)]]!, style: Theme.of(context).textTheme.headlineSmall),
        Text(cmsg, style: Theme.of(context).textTheme.displayMedium),
        const Text('تا شمارش تمام نشده در همان حالت بمانید'),
        const Spacer(),
      ]);

  Widget _run() {
    final c = counter!;
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      if (!hide) _preview(140),
      const Spacer(),
      Text(c.done ? 'نماز تمام شد' : 'رکعت', style: Theme.of(context).textTheme.titleLarge),
      Text('${c.rakat}', style: TextStyle(fontSize: 150, fontWeight: FontWeight.bold, height: 1, color: cs.primary)),
      Text('از ${c.total}'),
      const SizedBox(height: 16),
      Chip(label: Text(faName[pose]!)),
      const SizedBox(height: 8),
      SizedBox(width: 200, child: LinearProgressIndicator(value: conf)),
      Text(pose == Pose.unknown ? 'نامطمئن؛ شمارش متوقف است' : 'اطمینان تشخیص', style: Theme.of(context).textTheme.bodySmall),
      const Spacer(),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton.outlined(onPressed: c.rakat > 1 ? () => setState(() { c.rakat--; c.sujud = 0; }) : null, icon: const Icon(Icons.remove)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('تصحیح دستی')),
        IconButton.outlined(onPressed: c.rakat < c.total ? () => setState(() { c.rakat++; c.sujud = 0; }) : null, icon: const Icon(Icons.add)),
      ]),
      TextButton(onPressed: _stop, child: const Text('پایان')),
    ]);
  }
}
