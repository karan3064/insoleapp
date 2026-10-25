#!/usr/bin/env python3
"""Trains and validates GaitScreeningModel (lib/services/gait_screening_model.dart)
against the PhysioNet "Gait in Parkinson's Disease" database (Frenkel-Toledo,
Hausdorff, Yogev et al. -- https://physionet.org/content/gaitpdb/1.0.0/).

This is the actual script that produced the weights hardcoded in
GaitScreeningModel -- keep them in sync if you re-run this with more/different
data. No external ML libraries used on purpose: with ~100 subjects' worth of
data, anything beyond a small regularized logistic regression would overfit
and report false confidence, so this is a from-scratch, auditable
implementation rather than a scikit-learn call you'd have to trust blindly.

USAGE:
  1. Download https://physionet.org/content/gaitpdb/1.0.0/ (free, no special
     credentialing needed) -- the *.txt per-trial recordings plus
     demographics.txt, all in one folder.
  2. python3 tool/train_gait_screening_model.py <folder>

WHAT IT DOES:
  1. Parses every GaXxNN_NN.txt / JuXxNN_NN.txt / SiXxNN_NN.txt file (19
     tab-separated columns, see format.txt in the dataset -- col 18/19 are
     total left/right foot force in Newtons, 100 samples/sec). Excludes
     walk number "10" (the Ga study's dual-task/serial-7 condition) to
     keep a clean "usual walking" dataset.
  2. Detects stance intervals the same way ClinicalGaitAnalysis does
     (threshold crossing + a 100ms debounce -- see that class's doc comment
     for why the debounce is there: without it, sensor noise alone
     inflated some trials' step counts 2-3x).
  3. Computes 10 features per trial: per-side stride/swing/stance-time
     CV%, L/R stride-time asymmetry%, cadence, double-support%, and gait
     speed (from demographics.txt's Speed_01 column).
  4. CRITICAL DATA-QUALITY NOTE: demographics.txt encodes missing values as
     the literal string "NaN". Python's float("NaN") does NOT raise -- it
     silently returns the IEEE NaN float, which then poisons every
     downstream computation (trained weights silently became NaN the
     first time this script was written, with no error, no crash, no
     warning -- just garbage weights). This script explicitly checks
     `math.isnan()` on every parsed value and drops incomplete rows,
     rather than trusting `float()` to fail loudly. If you adapt this
     script, keep that check.
  5. Trains a regularized logistic regression via plain gradient descent.
  6. Validates HONESTLY: subject-level train/test splits (a subject's
     trials never span both train and test -- otherwise the model can
     "recognize" a person instead of generalizing, which inflates test
     accuracy without meaning anything), repeated over many random splits
     and averaged, since ~100 subjects makes any single split's number
     noisy.

RESULTS as of the last run (143 usable trials, 99 subjects, 30 random
subject-level splits):
  10-feature model (what's deployed): accuracy ~68% (range ~53-83%
    depending on the split), AUC ~0.78.
  4-feature baseline (stride/swing CV averaged across feet, asymmetry,
    cadence only): accuracy ~62%, AUC ~0.67 -- barely better than always
    guessing the majority class (63% of trials are PD in this dataset).
  Gait speed alone: AUC ~0.73 -- the single strongest individual feature,
    consistent with PD's well-documented gait slowing.

This is FAIR discrimination, not diagnostic-grade, and this script says so
plainly rather than rounding up. See GaitScreeningModel's doc comment for
the limitations that matter when actually using this in the app (domain
shift from lab force-plates to this app's own insole hardware, small
training set, substantial PD/control overlap in predicted probability).
"""

import csv
import glob
import math
import os
import random
import re
import sys
from statistics import mean, pstdev

PATTERN = re.compile(r'^(Ga|Ju|Si)(Co|Pt)(\d+)_(\d+)\.txt$')
CONTACT_THRESHOLD_N = 20.0
MIN_GAP_MS = 100  # must match ClinicalGaitAnalysis._minGapMs
FEATURES = [
    'lStrideCv', 'rStrideCv', 'lSwingCv', 'rSwingCv', 'lStanceCv',
    'rStanceCv', 'asym', 'cadence', 'dsupPct', 'speed',
]


def stance_intervals(times_ms, force, threshold):
    raw = []
    start = None
    for t, f in zip(times_ms, force):
        contact = f > threshold
        if contact and start is None:
            start = t
        elif not contact and start is not None:
            raw.append((start, t))
            start = None
    if start is not None:
        raw.append((start, times_ms[-1]))
    return raw


def debounce(intervals, min_gap_ms):
    if not intervals:
        return intervals
    merged = [intervals[0]]
    for s, e in intervals[1:]:
        ps, pe = merged[-1]
        if s - pe < min_gap_ms:
            merged[-1] = (ps, e)
        else:
            merged.append((s, e))
    return merged


def cv_percent(xs):
    if len(xs) < 2:
        return None
    m = mean(xs)
    if m == 0:
        return None
    sd = pstdev(xs) * math.sqrt(len(xs) / (len(xs) - 1))
    return sd / m * 100


def overlap_ms(left, right):
    total = 0
    for ls, le in left:
        for rs, re_ in right:
            s, e = max(ls, rs), min(le, re_)
            if e > s:
                total += e - s
    return total


def is_valid_num(x):
    return isinstance(x, (int, float)) and not math.isnan(x)


def load_demographics(folder):
    demo = {}
    path = os.path.join(folder, 'demographics.txt')
    if not os.path.exists(path):
        print(f'warning: {path} not found -- gait speed feature will be unavailable', file=sys.stderr)
        return demo
    with open(path) as f:
        reader = csv.reader(f, delimiter='\t')
        header = next(reader)
        for row in reader:
            if not row or not row[0].strip():
                continue
            d = dict(zip(header, row))

            def num(key):
                try:
                    v = float(d.get(key, ''))
                except (TypeError, ValueError):
                    return None
                return v if not math.isnan(v) else None  # see module docstring, point 4

            demo[d['ID']] = {'speed': num('Speed_01'), 'age': num('Age')}
    return demo


def extract_features(folder):
    demo = load_demographics(folder)
    rows = []
    for path in sorted(glob.glob(os.path.join(folder, '*.txt'))):
        name = os.path.basename(path)
        m = PATTERN.match(name)
        if not m:
            continue
        study, group, subj, walk = m.groups()
        if walk == '10':
            continue
        subject_id = f'{study}{group}{subj}'

        times_ms, left, right = [], [], []
        with open(path) as f:
            for line in f:
                parts = line.split()
                if len(parts) < 19:
                    continue
                try:
                    t, l, r = float(parts[0]), float(parts[17]), float(parts[18])
                except ValueError:
                    continue
                times_ms.append(round(t * 1000))
                left.append(l)
                right.append(r)
        if not times_ms:
            continue

        lst = debounce(stance_intervals(times_ms, left, CONTACT_THRESHOLD_N), MIN_GAP_MS)
        rst = debounce(stance_intervals(times_ms, right, CONTACT_THRESHOLD_N), MIN_GAP_MS)
        lstrides = [lst[i + 1][0] - lst[i][0] for i in range(len(lst) - 1)]
        rstrides = [rst[i + 1][0] - rst[i][0] for i in range(len(rst) - 1)]
        lswings = [lst[i + 1][0] - lst[i][1] for i in range(len(lst) - 1)]
        rswings = [rst[i + 1][0] - rst[i][1] for i in range(len(rst) - 1)]
        lstances = [e - s for s, e in lst]
        rstances = [e - s for s, e in rst]

        if len(lstrides) < 2 or len(rstrides) < 2:
            continue
        lmean, rmean = mean(lstrides), mean(rstrides)
        if lmean + rmean == 0:
            continue

        duration_s = (times_ms[-1] - times_ms[0]) / 1000
        if duration_s <= 0:
            continue

        d = demo.get(subject_id, {})
        rows.append({
            'subject': subject_id,
            'is_pd': group == 'Pt',
            'lStrideCv': cv_percent(lstrides), 'rStrideCv': cv_percent(rstrides),
            'lSwingCv': cv_percent(lswings), 'rSwingCv': cv_percent(rswings),
            'lStanceCv': cv_percent(lstances), 'rStanceCv': cv_percent(rstances),
            'asym': abs(lmean - rmean) / (0.5 * (lmean + rmean)) * 100,
            'cadence': (len(lst) + len(rst)) / (duration_s / 60),
            'dsupPct': overlap_ms(lst, rst) / (duration_s * 1000) * 100,
            'speed': d.get('speed'),
        })
    return [r for r in rows if all(is_valid_num(r.get(f)) for f in FEATURES)]


def standardize_fit(X):
    n, d = len(X), len(X[0])
    means = [sum(row[j] for row in X) / n for j in range(d)]
    sds = [math.sqrt(sum((row[j] - means[j]) ** 2 for row in X) / n) or 1.0 for j in range(d)]
    return means, sds


def standardize_apply(X, means, sds):
    return [[(row[j] - means[j]) / sds[j] for j in range(len(row))] for row in X]


def sigmoid(z):
    if z < -30:
        return 0.0
    if z > 30:
        return 1.0
    return 1 / (1 + math.exp(-z))


def train_logreg(X, y, lr=0.1, epochs=5000, l2=0.05):
    n, d = len(X), len(X[0])
    w, b = [0.0] * d, 0.0
    for _ in range(epochs):
        gw, gb = [0.0] * d, 0.0
        for i in range(n):
            p = sigmoid(sum(w[j] * X[i][j] for j in range(d)) + b)
            err = p - y[i]
            for j in range(d):
                gw[j] += err * X[i][j]
            gb += err
        for j in range(d):
            w[j] -= lr * (gw[j] / n + l2 * w[j])
        b -= lr * (gb / n)
    return w, b


def auc(y_true, y_score):
    n_pos, n_neg = sum(y_true), len(y_true) - sum(y_true)
    if n_pos == 0 or n_neg == 0:
        return None
    order = sorted(range(len(y_score)), key=lambda i: y_score[i])
    rank_of = [0] * len(y_score)
    r, i = 1, 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and y_score[order[j + 1]] == y_score[order[i]]:
            j += 1
        avg_rank = (r + r + (j - i)) / 2
        for k in range(i, j + 1):
            rank_of[order[k]] = avg_rank
        r += j - i + 1
        i = j + 1
    sum_ranks_pos = sum(rank_of[i] for i in range(len(y_true)) if y_true[i] == 1)
    return (sum_ranks_pos - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)


def cross_validate(rows, feats, n_repeats=30, seed=42):
    by_subject = {}
    for r in rows:
        by_subject.setdefault(r['subject'], []).append(r)
    subjects = list(by_subject.keys())
    random.seed(seed)
    accs, aucs = [], []
    for _ in range(n_repeats):
        random.shuffle(subjects)
        test_subj = set(subjects[:max(1, len(subjects) // 3)])
        train_rows = [r for r in rows if r['subject'] not in test_subj]
        test_rows = [r for r in rows if r['subject'] in test_subj]
        ytr = [1.0 if r['is_pd'] else 0.0 for r in train_rows]
        if sum(ytr) in (0, len(ytr)):
            continue
        Xtr = [[r[f] for f in feats] for r in train_rows]
        Xte = [[r[f] for f in feats] for r in test_rows]
        yte = [1.0 if r['is_pd'] else 0.0 for r in test_rows]
        means, sds = standardize_fit(Xtr)
        w, b = train_logreg(standardize_apply(Xtr, means, sds), ytr)
        preds = [sigmoid(sum(w[j] * row[j] for j in range(len(row))) + b)
                 for row in standardize_apply(Xte, means, sds)]
        accs.append(sum(1 for p, y in zip(preds, yte) if (p >= 0.5) == bool(y)) / len(yte))
        a = auc(yte, preds)
        if a is not None:
            aucs.append(a)
    return accs, aucs


def main():
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <folder-of-gaitpdb-files>', file=sys.stderr)
        sys.exit(1)

    rows = extract_features(sys.argv[1])
    n_pd = sum(1 for r in rows if r['is_pd'])
    print(f'{len(rows)} usable trials, {len(set(r["subject"] for r in rows))} subjects '
          f'({n_pd} PD, {len(rows) - n_pd} control)')
    print(f'Majority-class baseline accuracy: {max(n_pd, len(rows) - n_pd) / len(rows):.3f}\n')

    accs, aucs = cross_validate(rows, FEATURES)
    print(f'10-feature model: acc={mean(accs):.3f} [{min(accs):.3f},{max(accs):.3f}]  auc={mean(aucs):.3f}')

    rows_avg = [dict(r, strideCvAvg=(r['lStrideCv'] + r['rStrideCv']) / 2,
                      swingCvAvg=(r['lSwingCv'] + r['rSwingCv']) / 2) for r in rows]
    accs4, aucs4 = cross_validate(rows_avg, ['strideCvAvg', 'swingCvAvg', 'asym', 'cadence'])
    print(f'4-feature baseline: acc={mean(accs4):.3f} [{min(accs4):.3f},{max(accs4):.3f}]  auc={mean(aucs4):.3f}')

    accs_speed, aucs_speed = cross_validate(rows, ['speed'])
    print(f'speed alone: acc={mean(accs_speed):.3f}  auc={mean(aucs_speed):.3f}')

    # Final deployable model, trained on all available data.
    X = [[r[f] for f in FEATURES] for r in rows]
    y = [1.0 if r['is_pd'] else 0.0 for r in rows]
    means, sds = standardize_fit(X)
    w, b = train_logreg(standardize_apply(X, means, sds), y)
    print('\n--- Paste these into GaitScreeningModel if retraining ---')
    print('features:', FEATURES)
    print('_featureMeans:', [round(m, 6) for m in means])
    print('_featureSds:', [round(s, 6) for s in sds])
    print('_weights:', [round(x, 6) for x in w])
    print('_bias:', round(b, 6))


if __name__ == '__main__':
    main()
