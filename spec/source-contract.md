# The source contract

This repo's SQL doesn't fetch anything from GA4. It expects to find tables that somebody else has
already loaded. This page defines exactly what those tables have to look like.

Meet this contract with any tool — a managed connector, a scheduled script, whatever you already
run — and everything downstream works unchanged.

---

## One table per report

Each entry in [reports.yaml](reports.yaml) becomes one table in your landing dataset. No merging,
no wide tables. If a report asks GA4 for four dimensions and six metrics, its table has those ten
columns plus the housekeeping ones below.

Table names match the `name` field in the spec.

---

## Column naming

GA4's API uses camelCase. Warehouse convention is snake_case. Convert on the way in:

| GA4 API | Column |
|---|---|
| `sessionDefaultChannelGroup` | `session_default_channel_group` |
| `landingPagePlusQueryString` | `landing_page_plus_query_string` |
| `yearMonth` | `year_month` |
| `keyEvents` | `key_events` |
| `customEvent:segment_name` | `custom_event_segment_name` |

The pattern for custom dimensions is to drop the colon and snake_case the rest. Whatever you
choose, be consistent — the SQL in this repo assumes the table above.

---

## Required housekeeping columns

Every table needs these two beyond its dimensions and metrics.

| Column | Type | Purpose |
|---|---|---|
| `_synced_at` | `TIMESTAMP` | When this row was loaded. Drives deduplication. |
| `_source` | `STRING` | Which property or pipeline the row came from. |

`_synced_at` is not optional. Without it there's no way to tell a restated row from its earlier
version, and the deduplication in every staging model depends on it.

`_source` matters as soon as you have more than one property. Include it even if you have one
today — adding it later means rewriting every deduplication key.

If your tool names these differently (`_extracted_at`, `_loaded_at`, `_synced`), either rename on
landing or change the two constants at the top of
[sql/00_conventions.sql](../sql/00_conventions.sql).

---

## Data types

| GA4 kind | Type | Note |
|---|---|---|
| Dimensions | `STRING` | Including `year_month` — it's `'202608'`, not a number |
| `date` | `DATE` | |
| Count metrics | `INT64` | sessions, users, event count, transactions |
| `key_events` | **`FLOAT64`** | Data-driven attribution splits credit fractionally |
| Revenue | `FLOAT64` | |
| Ratio metrics | `FLOAT64` | |

`key_events` as a float is the one people get wrong. Loading it as an integer truncates every row
and your totals drift downward for reasons nobody can find later.

---

## Load behaviour

**Append or upsert, both fine.** The staging layer deduplicates on its own, so you don't need
exactly-once delivery.

**Re-read recent periods.** GA4 restates attribution for days after the fact. Your pipeline needs
a rollback window that re-loads recent periods on every run. Thirty days is a reasonable default;
ninety if you use data-driven attribution and care about revenue accuracy.

**Don't delete and reload.** Restated rows should arrive as new rows with a newer `_synced_at`.
The staging layer keeps the newest and ignores the rest. Truncate-and-load also works but throws
away your ability to see what changed.

**Nulls.** GA4 returns `(not set)` and `(other)` as literal strings. Keep them as strings if you
can — they mean different things, and mapping both to NULL loses that. If your tool nulls them
regardless, note it, because it changes how you read
[docs/02 §7](../docs/02-scopes-and-compatibility.md#not-set-is-not-other).

---

## Multiple properties

Two workable shapes.

**One dataset per property.** Simple, isolated, and every property gets its own validation. Costs
you a copy of the models per property, and a union layer if you want a combined view.

**One set of tables, `_source` telling them apart.** One model per report regardless of how many
properties you have. New properties need no new SQL. This is what the reference models assume.

Whichever you pick, remember that **user counts never sum across properties.** GA4 issues its own
identifiers per property, so the same person visiting two of your sites is two users and there's
no way to deduplicate them. Summing gives you "users per property, added together" — a real
figure, but not unique people. Name the column so nobody mistakes it.

---

## A minimal example

For a report defined as:

```yaml
name: ga4_channel_monthly
dimensions: [yearMonth, sessionDefaultChannelGroup]
metrics: [totalUsers, sessions, keyEvents, purchaseRevenue]
```

the landed table is:

| Column | Type |
|---|---|
| `year_month` | STRING |
| `session_default_channel_group` | STRING |
| `total_users` | INT64 |
| `sessions` | INT64 |
| `key_events` | FLOAT64 |
| `purchase_revenue` | FLOAT64 |
| `_synced_at` | TIMESTAMP |
| `_source` | STRING |

---

## Checking your landing tables

Before deploying any models, confirm the tables match what the SQL expects. Guessing a schema is
a reliable way to generate three rounds of rework.

```sql
SELECT
  table_name,
  column_name,
  data_type
FROM `your_project.your_landing_dataset.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name LIKE 'ga4_%'
ORDER BY table_name, ordinal_position;
```

Worth checking specifically:

- Does every table have `_synced_at` and `_source`?
- Is `key_events` a FLOAT64?
- Did every report you configured actually produce a table? Reports GA4 rejects — demographics
  without Google Signals, item reports without ecommerce tracking — often produce nothing at all
  rather than an error.
