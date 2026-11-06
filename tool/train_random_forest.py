#!/usr/bin/env python3
"""Trains a from-scratch Random Forest as a SECOND gait-screening model,
alongside GaitScreeningModel's logistic regression -- same PhysioNet "Gait
in Parkinson's Disease" dataset, same 10 features, same subject-level
honest cross-validation discipline as tool/train_gait_screening_model.py
(see that script's module docstring for the dataset/feature details this
one reuses via `extract_features`).

WHY A SECOND MODEL, NOT A REPLACEMENT:
Run against the real data, this Random Forest scores accuracy ~69%
(range ~60-80%), AUC ~0.75 (range ~0.64-0.91) across 30 subject-level
splits -- essentially TIED with the logistic regression's ~68%/0.78, not
better. With only ~100 subjects, that's the expected outcome, not a
surprise: a bigger/different model doesn't out-generalize a small one on
this little data, it just overfits differently. This script does NOT
claim the Random Forest is more accurate.

What it IS honestly useful for: EnsembleGaitScreening (lib/services/) runs
both models and reports whether they agree. Two models of genuinely
different architecture (a linear model vs. an ensemble of non-linear
decision trees) making uncorrelated errors is a real, standard technique
for an uncertainty signal -- when they agree, that's modestly more
trustworthy than either alone; when they disagree, that's a legitimate
reason to call the result inconclusive rather than picking one model's
answer arbitrarily. That is the actual point of training this, not a
raw-accuracy upgrade.

No external ML libraries used on purpose -- same rationale as the
logistic-regression script: with this little data, a library call you'd
have to trust blindly buys nothing over a small, auditable, from-scratch
implementation.

USAGE:
  1. Download https://physionet.org/content/gaitpdb/1.0.0/ (free, no
     special credentialing needed) -- the same folder
     tool/train_gait_screening_model.py uses.
  2. python3 tool/train_random_forest.py <folder>

This prints the honest cross-validated accuracy/AUC, then fits a final
forest on ALL available rows and writes its tree structure to
lib/services/random_forest_trees.dart (plain data, no logic -- see
lib/services/random_forest_gait_model.dart for the Dart-side tree
traversal that reads it).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from train_gait_screening_model import FEATURES, extract_features  # noqa: E402

random.seed(42)


# ---------------- Decision tree (CART, gini impurity) ----------------

class Node:
    __slots__ = ('feature', 'threshold', 'left', 'right', 'value')

    def __init__(self, feature=None, threshold=None, left=None, right=None, value=None):
        self.feature = feature
        self.threshold = threshold
        self.left = left
        self.right = right
        self.value = value  # leaf: predicted probability of class 1 (PD)


def gini(ys):
    n = len(ys)
    if n == 0:
        return 0.0
    p1 = sum(ys) / n
    return 1 - p1 * p1 - (1 - p1) * (1 - p1)


def best_split(X, ys, feature_subset):
    n = len(ys)
    best_gain = 0.0
    best_feat = None
    best_thresh = None
    base_gini = gini(ys)
    for f in feature_subset:
        values = sorted(set(row[f] for row in X))
        if len(values) < 2:
            continue
        thresholds = [(values[i] + values[i + 1]) / 2 for i in range(len(values) - 1)]
        for t in thresholds:
            left_ys = [ys[i] for i in range(n) if X[i][f] <= t]
            right_ys = [ys[i] for i in range(n) if X[i][f] > t]
            if len(left_ys) < 3 or len(right_ys) < 3:
                continue
            weighted = (len(left_ys) * gini(left_ys) + len(right_ys) * gini(right_ys)) / n
            gain = base_gini - weighted
            if gain > best_gain:
                best_gain = gain
                best_feat = f
                best_thresh = t
    return best_feat, best_thresh, best_gain


def build_tree(X, ys, depth, max_depth, min_leaf, n_features_per_split, rng):
    n = len(ys)
    p1 = sum(ys) / n if n else 0.5
    if depth >= max_depth or n < 2 * min_leaf or p1 == 0.0 or p1 == 1.0:
        return Node(value=p1)

    feature_subset = rng.sample(range(len(FEATURES)), n_features_per_split)
    feat, thresh, gain = best_split(X, ys, feature_subset)
    if feat is None or gain <= 1e-9:
        return Node(value=p1)

    left_idx = [i for i in range(n) if X[i][feat] <= thresh]
    right_idx = [i for i in range(n) if X[i][feat] > thresh]
    left = build_tree([X[i] for i in left_idx], [ys[i] for i in left_idx],
                       depth + 1, max_depth, min_leaf, n_features_per_split, rng)
    right = build_tree([X[i] for i in right_idx], [ys[i] for i in right_idx],
                        depth + 1, max_depth, min_leaf, n_features_per_split, rng)
    return Node(feature=feat, threshold=thresh, left=left, right=right)


def predict_tree(node, x):
    while node.value is None:
        node = node.left if x[node.feature] <= node.threshold else node.right
    return node.value


class RandomForest:
    def __init__(self, n_trees=25, max_depth=4, min_leaf=5, n_features_per_split=4, seed=0):
        self.n_trees = n_trees
        self.max_depth = max_depth
        self.min_leaf = min_leaf
        self.n_features_per_split = n_features_per_split
        self.seed = seed
        self.trees = []

    def fit(self, X, ys):
        rng = random.Random(self.seed)
        n = len(ys)
        self.trees = []
        for _ in range(self.n_trees):
            idx = [rng.randrange(n) for _ in range(n)]
            self.trees.append(build_tree(
                [X[i] for i in idx], [ys[i] for i in idx],
                0, self.max_depth, self.min_leaf, self.n_features_per_split, rng,
            ))

    def predict_proba(self, x):
        return sum(predict_tree(t, x) for t in self.trees) / len(self.trees)


# ---------------- Evaluation (subject-level, repeated splits) ----------------

def auc(ys_true, ys_score):
    pairs = list(zip(ys_true, ys_score))
    pos = [s for y, s in pairs if y == 1]
    neg = [s for y, s in pairs if y == 0]
    if not pos or not neg:
        return None
    count = sum((1 if p > n else 0.5 if p == n else 0) for p in pos for n in neg)
    return count / (len(pos) * len(neg))


def cross_validate(rows, n_splits=30, test_frac=1 / 3):
    X_all = [[r[f] for f in FEATURES] for r in rows]
    y_all = [1 if r['is_pd'] else 0 for r in rows]
    subject_of = [r['subject'] for r in rows]
    subjects = sorted(set(subject_of))
    rng = random.Random(123)
    accs, aucs = [], []
    for split_i in range(n_splits):
        rng.shuffle(subjects)
        test_subjects = set(subjects[:max(1, int(len(subjects) * test_frac))])
        train_idx = [i for i, s in enumerate(subject_of) if s not in test_subjects]
        test_idx = [i for i, s in enumerate(subject_of) if s in test_subjects]
        if not train_idx or not test_idx:
            continue
        rf = RandomForest(seed=split_i)
        rf.fit([X_all[i] for i in train_idx], [y_all[i] for i in train_idx])
        scores = [rf.predict_proba(X_all[i]) for i in test_idx]
        yte = [y_all[i] for i in test_idx]
        preds = [1 if s >= 0.5 else 0 for s in scores]
        accs.append(sum(1 for p, y in zip(preds, yte) if p == y) / len(yte))
        a = auc(yte, scores)
        if a is not None:
            aucs.append(a)
    return accs, aucs


# ---------------- Export: fit on all data, serialize to Dart ----------------

def serialize_tree(node, nodes):
    idx = len(nodes)
    nodes.append(None)
    if node.value is not None:
        nodes[idx] = {'leaf': True, 'value': round(node.value, 6)}
    else:
        left_idx = serialize_tree(node.left, nodes)
        right_idx = serialize_tree(node.right, nodes)
        nodes[idx] = {'leaf': False, 'feature': node.feature,
                       'threshold': round(node.threshold, 6), 'left': left_idx, 'right': right_idx}
    return idx


def export_dart(rows, path):
    X = [[r[f] for f in FEATURES] for r in rows]
    y = [1 if r['is_pd'] else 0 for r in rows]
    rf = RandomForest(seed=7)
    rf.fit(X, y)

    lines = [
        "// AUTO-GENERATED by tool/train_random_forest.py -- do not hand-edit.",
        "// Each tree is a flat list of nodes; node 0 is the root.",
        "// Leaf: {'leaf': true, 'value': <double>}",
        "// Split: {'leaf': false, 'feature': <int>, 'threshold': <double>, 'left': <int>, 'right': <int>}",
        "const List<List<Map<String, Object>>> randomForestTrees = [",
    ]
    for tree in rf.trees:
        nodes = []
        serialize_tree(tree, nodes)
        lines.append("  [")
        for n in nodes:
            if n['leaf']:
                lines.append(f"    {{'leaf': true, 'value': {n['value']}}},")
            else:
                lines.append(
                    f"    {{'leaf': false, 'feature': {n['feature']}, "
                    f"'threshold': {n['threshold']}, 'left': {n['left']}, 'right': {n['right']}}},"
                )
        lines.append("  ],")
    lines.append("];")
    with open(path, 'w') as f:
        f.write("\n".join(lines) + "\n")
    print(f"Exported {len(rf.trees)} trees to {path}")


def main():
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <folder-of-gaitpdb-files>', file=sys.stderr)
        sys.exit(1)

    rows = extract_features(sys.argv[1])
    print(f"{len(rows)} usable trials, {len(set(r['subject'] for r in rows))} subjects")

    accs, aucs = cross_validate(rows)
    print(f"Random Forest -- accuracy: {sum(accs)/len(accs):.3f} "
          f"(range {min(accs):.3f}-{max(accs):.3f}), "
          f"AUC: {sum(aucs)/len(aucs):.3f} (range {min(aucs):.3f}-{max(aucs):.3f})")
    print("Compare against GaitScreeningModel's own documented ~0.68 acc / 0.78 AUC "
          "-- this is NOT meant to beat it, see module docstring.")

    out_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'lib', 'services', 'random_forest_trees.dart'
    )
    export_dart(rows, out_path)


if __name__ == '__main__':
    main()
