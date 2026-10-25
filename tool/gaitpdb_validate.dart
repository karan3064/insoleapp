// Validates this app's stride/swing-time/CV%/asymmetry algorithm (the
// same stance-interval detection ClinicalGaitAnalysis uses) against the
// PhysioNet "Gait in Parkinson's Disease" database (Frenkel-Toledo,
// Hausdorff et al. -- https://physionet.org/content/gaitpdb/1.0.0/).
//
// That database can't validate anything about this app's footprint/arch
// classification -- it comes from 8 force-plate sensors per foot, not a
// 16-point pressure grid -- but it DOES give real patient-vs-control
// ground-reaction-force recordings with the exact same shape this app's
// algorithm already operates on: a per-foot loading signal over time, from
// which stance intervals (heel-strike -> toe-off) are detected by
// threshold-crossing, and stride time / swing time / CV% / asymmetry are
// derived from those. Running the same method on real labeled PD vs.
// control recordings is a real, independent accuracy check -- if it
// doesn't roughly reproduce the published numbers (Frenkel-Toledo/Yogev
// et al. report ~2.7% stride-time CV in PD patients vs. ~1.3% in controls,
// under usual walking), something is wrong with the detection logic, not
// just mistuned for this app's own hardware.
//
// This CANNOT run inside the cloud sandbox this was written in -- outbound
// access to physionet.org is blocked there. Run it yourself:
//
//   1. Download https://physionet.org/content/gaitpdb/1.0.0/ (free, no
//      special credentialing needed for this database) -- you want the
//      *.txt per-trial recordings (e.g. GaCo01_01.txt, GaPt03_02.txt, ...).
//   2. Put them all in one folder.
//   3. dart run tool/gaitpdb_validate.dart <folder>
//
// Each file is tab/whitespace-separated, no header, 19 columns, 100
// samples/sec:
//   col 1:     time (seconds)
//   cols 2-9:  8 force sensors under the left foot (Newtons)
//   cols 10-17: 8 force sensors under the right foot (Newtons)
//   col 18:    total force, left foot (sum of cols 2-9)
//   col 19:    total force, right foot (sum of cols 10-17)
// Columns 18/19 are what this script actually analyzes. If your downloaded
// files don't match this (check with `head -1 GaCo01_01.txt` and count
// fields), the dataset's own documentation page is the source of truth,
// not this comment -- adjust `_totalLeftCol`/`_totalRightCol` below.
//
// Filenames encode the group directly (no need to cross-reference the
// demographics spreadsheet): the two letters after the 2-letter study
// prefix (Ga/Ju/Si) are "Co" (control) or "Pt" (patient/PD).

import 'dart:io';

/// Pressure/force value above which a foot is considered "in contact" --
/// Newtons here, unlike the raw sensor units `ClinicalGaitAnalysis` uses
/// for this app's own hardware. 20N is a commonly used literature default
/// for a ~kg-scale adult partial-foot load; pass a different value as the
/// second CLI argument if your downloaded recordings look noisier/cleaner
/// than that.
const _defaultContactThresholdN = 20.0;
const _totalLeftCol = 17; // 0-indexed: column 18
const _totalRightCol = 18; // 0-indexed: column 19

class _Trial {
  final String path;
  final bool isPd;
  final double? leftCv;
  final double? rightCv;
  final double? asymmetryPercent;

  _Trial(this.path, this.isPd, this.leftCv, this.rightCv, this.asymmetryPercent);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/gaitpdb_validate.dart <folder-of-gaitpdb-txt-files> [contactThresholdN]');
    exit(1);
  }

  final dir = Directory(args[0]);
  if (!dir.existsSync()) {
    stderr.writeln('No such directory: ${args[0]}');
    exit(1);
  }
  final threshold = args.length > 1 ? double.parse(args[1]) : _defaultContactThresholdN;

  final groupPattern = RegExp(r'^(Ga|Ju|Si)(Co|Pt)\d+_\d+\.txt$');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => groupPattern.hasMatch(f.uri.pathSegments.last))
      .toList();

  if (files.isEmpty) {
    stderr.writeln('No GaXxNN_NN.txt / JuXxNN_NN.txt / SiXxNN_NN.txt files found in ${args[0]}');
    exit(1);
  }

  print('Found ${files.length} trial files. Contact threshold: ${threshold}N\n');

  final trials = <_Trial>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final isPd = groupPattern.firstMatch(name)!.group(2) == 'Pt';
    final trial = _analyzeTrial(file, isPd, threshold);
    trials.add(trial);
    final lCv = trial.leftCv?.toStringAsFixed(2) ?? 'n/a';
    final rCv = trial.rightCv?.toStringAsFixed(2) ?? 'n/a';
    final asym = trial.asymmetryPercent?.toStringAsFixed(2) ?? 'n/a';
    print('${name.padRight(20)} ${isPd ? 'PD ' : 'Ctl'}  '
        'strideCV% L=$lCv R=$rCv  asymmetry%=$asym');
  }

  print('\n--- Aggregate (mean stride-time CV%, both feet averaged per trial) ---');
  _reportGroup('PD patients', trials.where((t) => t.isPd));
  _reportGroup('Controls', trials.where((t) => !t.isPd));
  print('\nReference (Frenkel-Toledo/Yogev et al., usual walking): '
      'PD ~2.7% CV, Control ~1.3% CV.');
  print('If your PD mean is clearly higher than your Control mean and both '
      'are in the right ballpark of those reference numbers, the stance-'
      'interval/stride-time/CV% algorithm is doing its job correctly on '
      'real labeled data -- independent of this app\'s own hardware.');
}

void _reportGroup(String label, Iterable<_Trial> group) {
  final values = <double>[];
  for (final t in group) {
    final perTrial = [t.leftCv, t.rightCv].whereType<double>();
    if (perTrial.isNotEmpty) {
      values.add(perTrial.reduce((a, b) => a + b) / perTrial.length);
    }
  }
  if (values.isEmpty) {
    print('$label: no usable trials');
    return;
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.length > 1
      ? values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / (values.length - 1)
      : 0.0;
  print('$label: n=${values.length}  mean CV%=${mean.toStringAsFixed(2)}  '
      'sd=${_sqrt(variance).toStringAsFixed(2)}');
}

double _sqrt(double v) {
  if (v <= 0) return 0;
  var x = v;
  for (var i = 0; i < 40; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

_Trial _analyzeTrial(File file, bool isPd, double threshold) {
  final lines = file.readAsLinesSync();
  final timesMs = <int>[];
  final left = <double>[];
  final right = <double>[];

  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length <= _totalRightCol) continue;
    final timeSec = double.tryParse(parts[0]);
    final l = double.tryParse(parts[_totalLeftCol]);
    final r = double.tryParse(parts[_totalRightCol]);
    if (timeSec == null || l == null || r == null) continue;
    timesMs.add((timeSec * 1000).round());
    left.add(l);
    right.add(r);
  }

  if (timesMs.isEmpty) {
    return _Trial(file.path, isPd, null, null, null);
  }

  final leftStrides = _strideTimesMs(timesMs, left, threshold);
  final rightStrides = _strideTimesMs(timesMs, right, threshold);

  final leftCv = _cvPercent(leftStrides);
  final rightCv = _cvPercent(rightStrides);
  final leftMean = _mean(leftStrides);
  final rightMean = _mean(rightStrides);
  final asymmetry = (leftMean != null && rightMean != null && (leftMean + rightMean) > 0)
      ? (leftMean - rightMean).abs() / (0.5 * (leftMean + rightMean)) * 100
      : null;

  return _Trial(file.path, isPd, leftCv, rightCv, asymmetry);
}

/// Same rising-edge/falling-edge stance detection as
/// `ClinicalGaitAnalysis._stanceIntervals`, applied to this dataset's
/// per-foot total-force column instead of this app's insole pressure sum,
/// reduced directly to the stride-time list (heel-strike to next
/// heel-strike).
List<double> _strideTimesMs(List<int> timesMs, List<double> force, double threshold) {
  final heelStrikes = <int>[];
  var inContact = false;
  for (var i = 0; i < force.length; i++) {
    final contact = force[i] > threshold;
    if (contact && !inContact) heelStrikes.add(timesMs[i]);
    inContact = contact;
  }

  final strides = <double>[];
  for (var i = 0; i < heelStrikes.length - 1; i++) {
    strides.add((heelStrikes[i + 1] - heelStrikes[i]).toDouble());
  }
  return strides;
}

double? _mean(List<double> xs) {
  if (xs.isEmpty) return null;
  return xs.reduce((a, b) => a + b) / xs.length;
}

double? _cvPercent(List<double> xs) {
  if (xs.length < 2) return null;
  final mean = _mean(xs)!;
  if (mean == 0) return null;
  final variance = xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / (xs.length - 1);
  return _sqrt(variance) / mean * 100;
}
