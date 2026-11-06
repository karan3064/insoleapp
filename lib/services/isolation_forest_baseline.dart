import 'dart:math';

import '../models/insole_record.dart';

enum IsolationAnomalyLevel { normal, mild, significant, insufficientData }

class IsolationForestResult {
  final IsolationAnomalyLevel level;
  final double anomalyScore; // 0..1, standard Isolation Forest convention: higher = more anomalous
  final int baselineSessionCount;
  final String summary;

  const IsolationForestResult({
    required this.level,
    required this.anomalyScore,
    required this.baselineSessionCount,
    required this.summary,
  });
}

/// A second, complementary way of flagging an unusual session for this
/// specific patient -- alongside `PersonalBaselineModel`'s per-metric
/// z-scores, this looks at the *combination* of metrics at once using
/// Isolation Forest, an unsupervised anomaly-detection algorithm.
///
/// Why this is a genuine addition, not a duplicate of PersonalBaselineModel:
/// z-scoring each metric independently can miss a session that's subtly
/// off across several metrics at once even when no single metric crosses
/// its own threshold -- e.g. cadence slightly low AND asymmetry slightly
/// high AND load balance slightly shifted, none individually flagged, but
/// together an unusual combination this patient hasn't shown before.
/// Isolation Forest isolates points by how few random splits it takes to
/// separate them from the rest of the data -- an outlier isolates in few
/// splits (short path), a typical point takes many (long path) -- which
/// naturally captures that kind of joint, multi-metric deviation.
///
/// This is computed fresh from the patient's OWN session history every
/// time, like `PersonalBaselineModel` -- no external dataset, no
/// pre-trained weights shipped in the app. It needs no training data
/// because it's not learning population patterns, it's finding out how
/// isolated today's combination of numbers is from this one patient's own
/// recent sessions.
///
/// Honest limitation: with a typical patient's history (tens of sessions,
/// not thousands), the statistical power here is modest -- same caveat as
/// every other within-patient model in this app. Below
/// [minBaselineSessions] complete sessions (all 4 tracked metrics present),
/// this returns [IsolationAnomalyLevel.insufficientData] rather than a
/// score computed from too little data.
class IsolationForestBaseline {
  IsolationForestBaseline._();

  static const minBaselineSessions = 8;
  static const _nTrees = 50;

  static const List<String> metricKeys = ['cadence', 'rightLoadPercent', 'strideTimeAsymmetryPercent', 'strideTimeCvPercent'];

  static IsolationForestResult evaluate({
    required List<InsoleRecord> history,
    required InsoleRecord current,
    int? seed,
  }) {
    final past = history.where((r) => r.id != current.id).toList();
    final baselineVectors = <List<double>>[];
    for (final r in past) {
      final v = _extractVector(r);
      if (v != null) baselineVectors.add(v);
    }

    if (baselineVectors.length < minBaselineSessions) {
      return IsolationForestResult(
        level: IsolationAnomalyLevel.insufficientData,
        anomalyScore: 0,
        baselineSessionCount: baselineVectors.length,
        summary: 'Still building enough history for multi-metric anomaly detection -- '
            '${baselineVectors.length} of $minBaselineSessions complete sessions so far.',
      );
    }

    final currentVector = _extractVector(current);
    if (currentVector == null) {
      return IsolationForestResult(
        level: IsolationAnomalyLevel.insufficientData,
        anomalyScore: 0,
        baselineSessionCount: baselineVectors.length,
        summary: 'This session is missing one of the metrics needed for multi-metric anomaly detection.',
      );
    }

    // Standardize every dimension against the baseline's own mean/SD so no
    // one metric (e.g. cadence, scaled in the 80s-120s) dominates random
    // split selection just because its raw numbers are bigger than, say,
    // asymmetry% (typically single digits).
    final dims = currentVector.length;
    final means = List<double>.filled(dims, 0);
    final sds = List<double>.filled(dims, 1);
    for (var d = 0; d < dims; d++) {
      final values = baselineVectors.map((v) => v[d]).toList();
      final mean = values.reduce((a, b) => a + b) / values.length;
      final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
      final sd = sqrt(variance);
      means[d] = mean;
      sds[d] = sd == 0 ? 1 : sd;
    }

    List<double> standardize(List<double> v) => [for (var d = 0; d < dims; d++) (v[d] - means[d]) / sds[d]];

    final standardizedBaseline = baselineVectors.map(standardize).toList();
    final standardizedCurrent = standardize(currentVector);

    final forest = _IsolationForest(nTrees: _nTrees, seed: seed ?? 0);
    forest.fit(standardizedBaseline);
    final score = forest.anomalyScore(standardizedCurrent);

    final IsolationAnomalyLevel level;
    if (score >= 0.65) {
      level = IsolationAnomalyLevel.significant;
    } else if (score >= 0.55) {
      level = IsolationAnomalyLevel.mild;
    } else {
      level = IsolationAnomalyLevel.normal;
    }

    return IsolationForestResult(
      level: level,
      anomalyScore: score,
      baselineSessionCount: baselineVectors.length,
      summary: _narrative(level, score),
    );
  }

  static String _narrative(IsolationAnomalyLevel level, double score) {
    switch (level) {
      case IsolationAnomalyLevel.significant:
        return 'This session\'s combination of metrics is unusual compared to your own recent '
            'history, even though no single metric alone stood out -- worth a closer look.';
      case IsolationAnomalyLevel.mild:
        return 'This session\'s combination of metrics is somewhat atypical for you -- could be '
            'normal variation, worth watching over the next few sessions.';
      case IsolationAnomalyLevel.normal:
        return 'This session\'s combination of metrics is consistent with your recent history.';
      case IsolationAnomalyLevel.insufficientData:
        return '';
    }
  }

  static List<double>? _extractVector(InsoleRecord r) {
    final s = r.summary;
    final cv = [s.clinical.left.strideTimeCvPercent, s.clinical.right.strideTimeCvPercent]
        .whereType<double>()
        .toList();
    final asym = s.clinical.strideTimeAsymmetryPercent;
    if (cv.isEmpty || asym == null) return null;
    return [
      s.cadenceSpm.toDouble(),
      s.rightLoadPercent,
      asym,
      cv.reduce((a, b) => a + b) / cv.length,
    ];
  }
}

/// Standard Isolation Forest (Liu, Ting & Zhou, 2008): isolates points via
/// random recursive splits; an outlier isolates in fewer splits (shorter
/// average path length across trees) than a typical point.
class _IsolationForest {
  final int nTrees;
  final int seed;
  final List<_ITreeNode> _trees = [];
  late final int _subsampleSize;

  _IsolationForest({required this.nTrees, required this.seed});

  void fit(List<List<double>> data) {
    final rng = Random(seed);
    _subsampleSize = min(256, data.length);
    final maxDepth = (log(_subsampleSize) / log(2)).ceil();
    _trees.clear();
    for (var t = 0; t < nTrees; t++) {
      final sample = _sampleWithoutReplacement(data, _subsampleSize, rng);
      _trees.add(_buildTree(sample, 0, maxDepth, rng));
    }
  }

  List<List<double>> _sampleWithoutReplacement(List<List<double>> data, int n, Random rng) {
    final indices = List<int>.generate(data.length, (i) => i)..shuffle(rng);
    return indices.take(n).map((i) => data[i]).toList();
  }

  _ITreeNode _buildTree(List<List<double>> data, int depth, int maxDepth, Random rng) {
    if (depth >= maxDepth || data.length <= 1) {
      return _ITreeNode.leaf(data.length);
    }
    final dims = data[0].length;
    final feature = rng.nextInt(dims);
    final values = data.map((v) => v[feature]);
    final minV = values.reduce(min);
    final maxV = values.reduce(max);
    if (minV == maxV) {
      return _ITreeNode.leaf(data.length);
    }
    final splitValue = minV + rng.nextDouble() * (maxV - minV);
    final left = data.where((v) => v[feature] < splitValue).toList();
    final right = data.where((v) => v[feature] >= splitValue).toList();
    if (left.isEmpty || right.isEmpty) {
      return _ITreeNode.leaf(data.length);
    }
    return _ITreeNode.split(
      feature: feature,
      threshold: splitValue,
      left: _buildTree(left, depth + 1, maxDepth, rng),
      right: _buildTree(right, depth + 1, maxDepth, rng),
    );
  }

  /// Average adjustment for unbuilt subtrees -- harmonic-number
  /// approximation of the average path length of an unsuccessful BST
  /// search, same formula the original Isolation Forest paper uses.
  static double _c(int n) {
    if (n <= 1) return 0;
    final h = log(n - 1) + 0.5772156649015329; // Euler-Mascheroni constant
    return 2 * h - (2 * (n - 1) / n);
  }

  double _pathLength(_ITreeNode node, List<double> x, int depth) {
    if (node.isLeaf) {
      return depth + _c(node.leafSize);
    }
    if (x[node.feature!] < node.threshold!) {
      return _pathLength(node.left!, x, depth + 1);
    }
    return _pathLength(node.right!, x, depth + 1);
  }

  double anomalyScore(List<double> x) {
    final avgPathLength = _trees.map((t) => _pathLength(t, x, 0)).reduce((a, b) => a + b) / _trees.length;
    final c = _c(_subsampleSize);
    if (c == 0) return 0.5;
    return pow(2, -avgPathLength / c).toDouble();
  }
}

class _ITreeNode {
  final bool isLeaf;
  final int leafSize;
  final int? feature;
  final double? threshold;
  final _ITreeNode? left;
  final _ITreeNode? right;

  _ITreeNode.leaf(this.leafSize)
      : isLeaf = true,
        feature = null,
        threshold = null,
        left = null,
        right = null;

  _ITreeNode.split({required this.feature, required this.threshold, required this.left, required this.right})
      : isLeaf = false,
        leafSize = 0;
}
