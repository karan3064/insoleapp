import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/insole_record.dart';
import '../models/user_profile.dart';
import 'clinical_gait_analysis.dart';

/// Builds a clinician-facing export of one session's clinical gait metrics,
/// as CSV (for spreadsheets/EHR import) or PDF (for printing/sharing).
///
/// Both formats present the same raw, literature-standard measurements as
/// `ClinicalGaitAnalysis` -- no diagnostic claims or risk scoring.
class ClinicalReportService {
  ClinicalReportService._();

  static String _fmtOr(double? v, String fallback, {int decimals = 1}) =>
      v == null ? fallback : v.toStringAsFixed(decimals);

  static List<_Metric> _metrics(ClinicalGaitReport gait) => [
        _Metric('Cadence', _fmtOr(gait.cadenceStepsPerMin, '--'), 'steps/min'),
        _Metric('Double support', _fmtOr(gait.doubleSupportPercent, '--'), '%'),
        _Metric('Single support', _fmtOr(gait.singleSupportPercent, '--'), '%'),
        _Metric('Stride time (left)', _fmtOr(gait.left.strideTimeMeanMs, '--', decimals: 0), 'ms'),
        _Metric('Stride time (right)', _fmtOr(gait.right.strideTimeMeanMs, '--', decimals: 0), 'ms'),
        _Metric('Stride time CV (left)', _fmtOr(gait.left.strideTimeCvPercent, '--'), '%'),
        _Metric('Stride time CV (right)', _fmtOr(gait.right.strideTimeCvPercent, '--'), '%'),
        _Metric('Stance time (left)', _fmtOr(gait.left.stanceTimeMeanMs, '--', decimals: 0), 'ms'),
        _Metric('Stance time (right)', _fmtOr(gait.right.stanceTimeMeanMs, '--', decimals: 0), 'ms'),
        _Metric('Swing time (left)', _fmtOr(gait.left.swingTimeMeanMs, '--', decimals: 0), 'ms'),
        _Metric('Swing time (right)', _fmtOr(gait.right.swingTimeMeanMs, '--', decimals: 0), 'ms'),
        _Metric('Stride time asymmetry', _fmtOr(gait.strideTimeAsymmetryPercent, '--'), '%'),
        _Metric('Stance time asymmetry', _fmtOr(gait.stanceTimeAsymmetryPercent, '--'), '%'),
        _Metric('Step count (left)', '${gait.left.stepCount}', 'steps'),
        _Metric('Step count (right)', '${gait.right.stepCount}', 'steps'),
      ];

  static String buildCsv({
    required InsoleRecord record,
    required ClinicalGaitReport gait,
    required UserProfile profile,
    String? patientEmail,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('NurvoSync Clinical Gait Report');
    buffer.writeln('Patient,${_csvField(profile.displayName ?? patientEmail ?? 'Unknown')}');
    buffer.writeln('Session,${_csvField(record.name)}');
    buffer.writeln('Date,${_csvField(record.date)}');
    buffer.writeln('Duration (s),${record.time}');
    buffer.writeln();
    buffer.writeln('Metric,Value,Unit');
    for (final m in _metrics(gait)) {
      buffer.writeln('${_csvField(m.label)},${_csvField(m.value)},${_csvField(m.unit)}');
    }
    return buffer.toString();
  }

  static String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static Future<Uint8List> buildPdf({
    required InsoleRecord record,
    required ClinicalGaitReport gait,
    required UserProfile profile,
    String? patientEmail,
  }) async {
    final doc = pw.Document();
    final metrics = _metrics(gait);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('NurvoSync Clinical Gait Report',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Raw gait measurements from heel-strike/toe-off event detection. '
                'This report makes no diagnostic claims -- for review by a treating clinician.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 16),
              _pdfInfoRow('Patient', profile.displayName ?? patientEmail ?? 'Unknown'),
              _pdfInfoRow('Session', record.name),
              _pdfInfoRow('Date', record.date),
              _pdfInfoRow('Duration', '${record.time} s'),
              if (profile.heightCm != null) _pdfInfoRow('Height', '${profile.heightCm!.toStringAsFixed(0)} cm'),
              if (profile.weightKg != null) _pdfInfoRow('Weight', '${profile.weightKg!.toStringAsFixed(0)} kg'),
              pw.SizedBox(height: 20),
              pw.Text('Clinical gait metrics', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: const ['Metric', 'Value', 'Unit'],
                data: metrics.map((m) => [m.label, m.value, m.unit]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {1: pw.Alignment.centerRight},
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.5),
                },
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 80, child: pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700))),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}

class _Metric {
  final String label;
  final String value;
  final String unit;
  const _Metric(this.label, this.value, this.unit);
}
