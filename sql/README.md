# SQL

Reference BigQuery models for the design in [docs/](../docs/). Run them in order.

| File | What it does |
|---|---|
| `00_conventions.sql` | Naming rules, the patterns every model follows, and the two constants to change |
| `10_staging.sql` | One view per report — deduplicated, typed, with a primary key |
| `20_marts.sql` | Long-format daily and monthly marts, plus period totals |
| `30_tests.sql` | Primary keys, freshness, `(other)` presence, reconciliation |

## Before you start

Replace these placeholders throughout, or use find-and-replace on the whole directory:

- `__LANDING__` — the dataset your pipeline writes to
- `__MODEL__` — the dataset these views should live in
- `__TIMEZONE__` — the GA4 property's reporting timezone, e.g. `Europe/London`

And confirm your landing tables match [spec/source-contract.md](../spec/source-contract.md). The
information schema query at the end of that page takes a minute and saves a lot of rework.

## Order

```
00_conventions.sql   read it, don't run it
10_staging.sql       creates views in __MODEL__
30_tests.sql         run the primary key tests — stop if any fail
20_marts.sql         creates the marts
30_tests.sql         run the rest
```

Tests come before marts on purpose. A broken deduplication key produces marts that look fine.

## Coverage

`10_staging.sql` implements all four tiers, with a representative subset of the monthly
breakdowns rather than all nineteen. The pattern is identical for each — only the dimension
column changes — so add the rest from [spec/reports.yaml](../spec/reports.yaml) following the
shape of `stg_channel_monthly`.

If you add a staging view, add a matching branch to `test_primary_keys` in `30_tests.sql`. That
test is what catches the deduplication bug described in
[docs/05 §2](../docs/05-operations.md#2-the-deduplication-key-is-load-bearing), and it only
covers the views listed in it.

## Views versus tables

Everything here is a view. Views cost nothing to rebuild, always reflect the latest load, and
can't drift out of sync with their source.

If dashboards feel slow, materialise the marts — they're the ones doing the work — and leave
staging as views. `20_marts.sql` has the materialisation statements commented at the end.
Schedule them after your pipeline's own run, not on a fixed clock, or you'll publish yesterday's
numbers.
