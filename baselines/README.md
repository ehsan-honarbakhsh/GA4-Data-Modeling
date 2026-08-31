# Baselines

The figures quoted throughout this repo , sessions running 5.3× high when summed across event
names, users at 1.14× when summed across days , came from one real property. **They are not GA4
constants.** They describe how one set of visitors behaved.

Yours will differ, sometimes a lot. A single-page site has almost no page-path overcount. A
content site with heavy internal navigation has an enormous one. A property whose visitors come
back weekly has a much higher user overlap than one whose visitors come once.

So measure your own. It takes a few minutes, and afterwards you have numbers you can defend.

## Why this matters more than it sounds

Once you know your own baselines, reconciliation stops being noise.

Without them, every check compares against zero, every check fails, and everyone learns to ignore
the alerts. With them, you compare against what *your* property normally does, and a real problem
stands out immediately. A geography table sitting 5% above total is fine if it always sits 5%
above total. The same table at 1% is worth investigating, even though it's closer to zero.

See [docs/04 §3](../docs/04-reconciliation.md#3-score-against-your-own-baseline-not-against-zero).

## The queries

| File | Measures |
|---|---|
| `10_additivity.sql` | How far each dimension overcounts when summed |
| `20_cardinality.sql` | Distinct values per report, and any `(other)` rows |
| `30_cross_grain.sql` | Daily rolled up vs monthly |
| `40_subset_rollup.sql` | Bounds for user counts across a group of dimension values |

Run them on a complete month with healthy data. Record the results somewhere durable , a file in
this repo works well, and it's the thing you'll want when a number changes six months from now.

## One property's results, for scale

Roughly 65,000 sessions and 51,000 monthly users, ecommerce, multi-site hospitality.

| Measurement | Result |
|---|---|
| Sessions summed across event names | **5.3×** the true count |
| Sessions summed across page paths | **~2.5×** |
| Sessions summed across cities | **+7%** |
| Sessions summed across countries or regions | **+5%** |
| Sessions summed across an event-scoped segment dimension | **+13.75%** |
| Sessions summed across first-user campaign | **+3%** |
| Sessions summed across device, browser, OS | **under 1%** |
| Daily sessions summed to a month | **+1.5%** |
| Daily users summed to a month | **1.14×** |

Read these as orders of magnitude, not as targets. The point of the table is that the errors range
from "ignore it" to "your number is five times too big" depending entirely on which dimension you
summed across , and nothing in the data tells you which case you're in.
