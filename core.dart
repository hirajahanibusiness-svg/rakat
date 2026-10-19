import 'dart:math' as m;

enum Pose { qiyam, ruku, sujud, julus, unknown }

double _med(List<double> a) => (a..sort())[a.length ~/ 2];

/// راهنمای چیدمان؛ null یعنی کادر مناسب است.
String? framingHint(List<List<double>> l, {bool standing = false}) {
  bool ok(int i) => l[i][2] > 0.5;
  if (!ok(0)) return 'سر شما دیده نمی‌شود';
  if (!(ok(27) || ok(28))) return 'کمی عقب‌تر بروید تا کل بدن دیده شود';
  final ys = l.map((p) => p[1]);
  if (ys.reduce(m.min) < 0.02 || ys.reduce(m.max) > 0.98) return 'کمی عقب‌تر بروید';
  if (standing) {
    final h = (l[27][1] - l[0][1]).abs();
    if (h > 0 && (l[11][0] - l[12][0]).abs() / h > 0.3) return 'کمی بچرخید تا از پهلو دیده شوید';
  }
  return null;
}

/// ویژگی‌های یک فریم: شکل کلی بدن و سر، نه زاویهٔ مفاصل (مقاوم در برابر چادر).
class Frame {
  Frame(this.h, this.w, this.head, this.trunk, this.vis);
  final double h, w, head, trunk, vis;

  static Frame? from(List<List<double>> l) {
    final p = l.where((e) => e[2] > 0.3).toList();
    if (p.length < 8) return null;
    final xs = p.map((e) => e[0]), ys = p.map((e) => e[1]);
    final minY = ys.reduce(m.min), maxY = ys.reduce(m.max);
    final w = xs.reduce(m.max) - xs.reduce(m.min);
    double mid(int a, int b, int k) => (l[a][k] + l[b][k]) / 2;
    final dx = (mid(11, 12, 0) - mid(23, 24, 0)).abs();
    final dy = (mid(11, 12, 1) - mid(23, 24, 1)).abs();
    final trunk = m.atan2(dx, dy) / (m.pi / 2); // 0 عمودی، 1 افقی
    final vis = [0, 11, 12, 23, 24].map((i) => l[i][2]).reduce((a, b) => a + b) / 5;
    return Frame(maxY - minY, w, maxY - l[0][1], trunk, vis);
  }

  List<double> vec(double hs) => [h / hs, w / hs, head / hs, trunk];
}

const _wt = [1.0, 1.0, 1.5, 0.7];
double _dist(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]) * _wt[i];
    s += d * d;
  }
  return m.sqrt(s);
}

/// کالیبراسیون شخصی + kNN: مرجع همان فرد، همان لباس، همان زاویه.
class Calibration {
  final _raw = <Pose, List<Frame>>{};
  final _s = <(Pose, List<double>)>[];
  double hs = 1;
  bool ready = false;

  void reset() { _raw.clear(); _s.clear(); ready = false; }
  void add(Pose p, Frame f) => (_raw[p] ??= []).add(f);

  bool finish() {
    final q = _raw[Pose.qiyam];
    if (q == null || q.length < 8) return false;
    hs = _med(q.map((f) => f.h).toList());
    _s.clear();
    for (final p in Pose.values.take(4)) {
      final fs = _raw[p] ?? [];
      if (fs.length < 8) return false;
      for (final f in fs) { _s.add((p, f.vec(hs))); }
    }
    return ready = true;
  }

  /// (حالت، اطمینان بین ۰ تا ۱)؛ اگر مطمئن نباشد unknown برمی‌گرداند.
  (Pose, double) classify(Frame f) {
    final v = f.vec(hs);
    final d = _s.map((s) => (s.$1, _dist(v, s.$2))).toList()..sort((a, b) => a.$2.compareTo(b.$2));
    final votes = <Pose, List<double>>{};
    for (final e in d.take(5)) { (votes[e.$1] ??= []).add(e.$2); }
    final best = votes.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);
    final avg = best.value.reduce((a, b) => a + b) / best.value.length;
    final conf = (1 - avg / 0.4).clamp(0.0, 1.0);
    if (conf < 0.2 || f.vis < 0.4 || best.value.length < 3) return (Pose.unknown, conf);
    return (best.key, conf);
  }
}

/// ماشین حالت: شمارش رکعت و زمان تکبیر. حالت نامطمئن هرگز چیزی نمی‌شمارد.
class RakatCounter {
  RakatCounter(this.total);
  final int total;
  int rakat = 1, sujud = 0;
  bool done = false;
  Pose stable = Pose.unknown, _cand = Pose.unknown;
  int _n = 0;
  void Function(String event)? onEvent;

  void update(Pose p) {
    if (p == Pose.unknown || done) return;
    if (p == _cand) { _n++; } else { _cand = p; _n = 1; }
    if (_n >= 6 && p != stable) {
      _go(stable, p);
      stable = p;
    }
  }

  void _go(Pose from, Pose to) {
    switch (to) {
      case Pose.ruku:
        if (from == Pose.qiyam) onEvent?.call('takbir');
      case Pose.sujud:
        sujud++;
        onEvent?.call('takbir');
      case Pose.julus:
        onEvent?.call('takbir');
        if (sujud >= 2 && rakat >= total) { done = true; onEvent?.call('finished'); }
      case Pose.qiyam:
        if (from == Pose.sujud || from == Pose.julus) {
          onEvent?.call('takbir');
          if (sujud >= 2) { sujud = 0; rakat++; onEvent?.call('rakat_$rakat'); }
        }
      case Pose.unknown:
        break;
    }
  }
}
