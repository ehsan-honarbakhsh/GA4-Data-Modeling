# Reconciliation

Your pipeline will break at some point. Reconciliation is how you find out.
The hard part isn't writing the checks. It's that GA4's own arithmetic produces permanent,
expected gaps , so a naive "does A equal B" test fires constantly, everyone learns to ignore it,
and the real breakage sails through six months later. A reconciliation layer is only useful if it
distinguishes the two.

---

## 1. The core idea

Compare a breakdown table to a totals table **only on metrics that are genuinely additive across
that breakdown's dimension.**

Get that wrong and you're measuring GA4's design, not your pipeline. Comparing sessions on a
page-path table against total sessions will show a gap of hundreds of percent, every single day,
forever. That's not a finding. That's the additivity rule doing exactly what
[docs/02](02-scopes-and-compatibility.md) says it does.

So the first job is picking the right metric for each table.

| Table type | Reconcile on | Never reconcile on |
|---|---|---|
| Channel, medium, source | sessions, key events, revenue, event count | users |
| Landing pages | sessions, key events, revenue | users |
| Geography | key events, revenue, event count | sessions (5–7% high), users |
| Device, browser, OS | sessions, key events, revenue | users |
| Pages | screen page views, event count | sessions, users |
| Events | event count, key events | sessions, users |
| First-user campaign | new users | sessions (~3% high), users |
| Items | nothing — no shared metric with totals | everything |

Two patterns worth noticing. Key events and revenue are additive nearly everywhere, which makes
them the most broadly useful reconciliation metrics. And users are never on the left-hand column,
anywhere.

---

## 2. What a healthy result looks like

Not zero. A small, stable, *signed* gap.

Signed matters. Early in this work an `ABS()` in a reconciliation query turned a 5.4% excess into
a reported 5.4% shortfall, and sent the investigation in precisely the wrong direction for a day.
Excess and shortfall have opposite causes:

- **Breakdown above total** → double counting. A dimension less additive than you assumed, or
  duplicate rows from restatement.
- **Breakdown below total** → data loss. Thresholding, cardinality collapse into `(other)`, a
  failed sync, or a filter that's quietly dropping rows.

Never take the absolute value.

```sql
-- Signed gap, per period, per dimension
SELECT
  b.period,
  b.dimension_name,
  SUM(b.metric_value)                                   AS breakdown_total,
  ANY_VALUE(t.metric_value)                             AS reported_total,
  SUM(b.metric_value) - ANY_VALUE(t.metric_value)       AS signed_gap,
  SAFE_DIVIDE(
    SUM(b.metric_value) - ANY_VALUE(t.metric_value),
    ANY_VALUE(t.metric_value)
  )                                                     AS signed_gap_pct
FROM breakdowns b
JOIN totals    t USING (period, metric_name)
WHERE b.metric_name IN ('sessions', 'key_events', 'purchase_revenue', 'event_count')
GROUP BY b.period, b.dimension_name
ORDER BY b.period DESC, ABS(signed_gap_pct) DESC;
```

---

## 3. Score against your own baseline, not against zero

This is the part most reconciliation layers skip, and it's what makes the difference between a
check people act on and a check people mute.

Each table has a characteristic gap. Geography sits a few percent high because location resolves
per event. Channel sits very slightly high. Pages sit far above on sessions, which is why you
don't test that at all.

Measure those gaps once, when you know the pipeline is healthy. Store them. Then alert on
**drift from the baseline**, not on distance from zero.

```sql
-- Alert on movement, not on the gap itself
SELECT
  r.period,
  r.dimension_name,
  r.metric_name,
  r.signed_gap_pct,
  b.expected_gap_pct,
  r.signed_gap_pct - b.expected_gap_pct AS drift,
  CASE
    WHEN ABS(r.signed_gap_pct - b.expected_gap_pct) > 0.05 THEN 'INVESTIGATE'
    WHEN ABS(r.signed_gap_pct - b.expected_gap_pct) > 0.02 THEN 'WATCH'
    ELSE 'OK'
  END AS status
FROM reconciliation r
LEFT JOIN expected_gaps b USING (dimension_name, metric_name)
WHERE r.period >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND ABS(r.signed_gap_pct - COALESCE(b.expected_gap_pct, 0)) > 0.02
ORDER BY ABS(drift) DESC;
```

A geography table sitting 5% high is fine. The same table sitting 5% high on Monday and 1% high on
Tuesday is worth a look — something changed, even though the second number is closer to zero.

---

## 4. Checks that catch different problems

### Cross-grain

Daily rolled up to a month, compared to the monthly table. The gap should be small, positive and
stable — sessions spanning midnight, as described in
[docs/01](01-why-ga4-numbers-differ.md#the-same-metric-can-have-two-right-answers).

If it goes to zero, you've probably started reading the same table twice. If it grows, look for
duplicate rows from restatement.

Run it on sessions only. Users at two grains aren't comparable and the number means nothing.

### Primary key uniqueness

The cheapest and most valuable test in the repo.

```sql
SELECT report_pk, COUNT(*) AS n
FROM your_staging_table
GROUP BY report_pk
HAVING COUNT(*) > 1;   -- expect nothing
```

If this returns rows, your deduplication key is wrong — most often because a dimension is missing
from it. See [docs/05 §2](05-operations.md#2-the-deduplication-key-is-load-bearing).

### Freshness

```sql
SELECT
  MAX(date)                                          AS latest_date,
  DATE_DIFF(CURRENT_DATE(), MAX(date), DAY)          AS days_behind,
  IF(DATE_DIFF(CURRENT_DATE(), MAX(date), DAY) > 3, 'STALE', 'OK') AS status
FROM your_totals_table;
```

Obvious, and routinely missing. A stalled pipeline is invisible until somebody notices a flat line
on a chart, which usually takes a week or two.

### `(other)` presence

Any `(other)` row means a table has stopped being complete. Worth a standing check rather than a
one-off — cardinality creeps up as a business grows.

### Row counts by dimension

Sudden changes in the number of distinct values often mean a tagging change upstream. A country
count dropping from 150 to 12 is a broken tag, not a collapse in international traffic.

---

## 5. The acceptance test

Reconciliation tells you the pipeline is *stable*. It doesn't tell you it's *right*. For that,
compare against the GA4 interface once, deliberately, and write down the result.

Pick a complete month. Open GA4 with the matching date range, matching dimension, and no filters
in place that your table doesn't also apply. Compare, value by value.

Things that will trip you up:

- **Custom channel groups.** If the interface is set to a custom channel group and your table uses
  the default, the values won't line up and nothing is wrong. Check the dimension selector before
  you check the data.
- **The interface's own totals.** As noted in docs/01, GA4's rows don't sum to GA4's total. Compare
  rows to rows.
- **Incomplete periods.** Attribution is still moving for the last few days. Use a month that
  closed at least a week ago.
- **Timezone.** Your date boundaries need to match the property's reporting timezone, not your
  own. This one is easy to get wrong and hard to spot.

Record the result with its date. When it stops reproducing later, you'll want to know what it
looked like when it worked — and whether anything changed in between, like a new dimension that
altered the grain of every table.

---

## 6. Things not to reconcile

- **Users, anywhere, across anything.** Not a reconciliation. A category error.
- **`itemRevenue` against `purchaseRevenue`.** Item revenue excludes shipping and tax. They are
  not meant to match.
- **`transactions` against `ecommercePurchases`.** Transactions include subscriptions and
  in-app purchases and are net of refunds. Purchases are neither.
- **Demographics against totals.** Thresholding removes rows. The table is incomplete by design.
- **Anything against an Exploration.** Explorations sample above ~10 million events.
- **Sessions on page or event tables.** Guaranteed to fail, permanently, by design.

---

**Next:** [Operations](05-operations.md) — deployment order, restatement, and the mistakes that
cost the most time.
