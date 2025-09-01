
"""
Usage:
  python autograde_metrics.py --labels dataset/deliveries.csv --predictions predictions.csv --po dataset/purchase_orders.csv

Expects predictions.csv with columns: order_id,p_late
Outputs PR-AUC, ROC-AUC, F1 at 0.5 and at top-20%.
"""
import argparse
import pandas as pd
from sklearn.metrics import average_precision_score, roc_auc_score, f1_score
parser = argparse.ArgumentParser()
parser.add_argument('--labels', required=True)
parser.add_argument('--predictions', required=True)
parser.add_argument('--po', required=True)
args = parser.parse_args()
po = pd.read_csv(args.po, parse_dates=['order_date','promised_date'])
deliv = pd.read_csv(args.labels, parse_dates=['actual_delivery_date'])
df = po.merge(deliv, on='order_id', how='left')
df = df.query('cancelled == 0').copy()
df['late_delivery'] = df['late_delivery'].fillna(0).astype(int)
pred = pd.read_csv(args.predictions)
assert set(['order_id','p_late']).issubset(pred.columns)
m = df.merge(pred, on='order_id', how='inner')
print(f"Merged rows: {len(m)}")
pr_auc = average_precision_score(m['late_delivery'], m['p_late'])
roc_auc = roc_auc_score(m['late_delivery'], m['p_late'])
thr = 0.5
f1_default = f1_score(m['late_delivery'], (m['p_late']>=thr).astype(int))
k = max(1, int(0.2 * len(m)))
thr_top20 = m['p_late'].nlargest(k).min()
f1_top20 = f1_score(m['late_delivery'], (m['p_late']>=thr_top20).astype(int))
print({'PR_AUC': float(pr_auc), 'ROC_AUC': float(roc_auc), 'F1@0.5': float(f1_default), 'F1@top20%': float(f1_top20)})
