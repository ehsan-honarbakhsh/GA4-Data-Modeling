# Operations

Practical notes on running this design: how changes propagate, what breaks quietly, and the
mistakes that cost the most time. 

---

## 1. A change moves through three layers, in order

Adding a metric or a dimension is never one edit. It's three, and they have to happen in sequence.

1. **Ingestion.** Add the field to the report definition. Whatever tool you use, this is where the
   data starts arriving.
2. **Staging.** Add the column to the model. If your staging layer uses an explicit column list —
   and it should — a new field in the source table does **not** appear downstream on its own.
3. **Mart.** Expose it wherever the mart selects columns or unpivots metrics.

Skipping step 2 is the usual mistake, because step 1 succeeds visibly: you can see the column in
the raw table, so it feels done. Everything downstream stays silently unchanged.

Deploying step 2 before step 1 has landed is safe in itself, but produces a table full of NULLs
that looks exactly like a broken model. If you can't do them in order, at least know which
situation you're in.

---

## 2. The deduplication key is load-bearing

Because GA4 restates recent periods, your pipeline will re-read days it has already loaded. You
need a rule that keeps the newest version of each row:

```sql
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY <every dimension in the report>
  ORDER BY _synced_at DESC
) = 1
```

**Every dimension.** Miss one and the query keeps a single row per partial key and throws the rest
away.

This is the most damaging bug in the whole design, and the reason it deserves its own section is
that it doesn't look like a bug. There's no error. The table has rows. The numbers are simply
smaller than they should be, in a way nobody notices until someone compares against GA4 months
later.

It bites hardest when you add a dimension. Existing staging views were written with the old key,
they still run, and from the day the new dimension arrives they start discarding everything but
one value per period. If you add a dimension to your reports, updating every deduplication key is
part of that change, not a follow-up task.

A primary key uniqueness test catches it immediately. Run one on every staging table.

---

## 3. When a dimension gets added to existing reports

Three things happen at once, and only the first is obvious.

**The grain changes.** Every table is now at (period, new dimension) grain. Queries that assumed
one row per period start returning several. Anything computing a share or a rate silently changes
meaning.

**You may lose your property-wide total.** If the dimension went onto your totals reports too,
there's no unfiltered anchor left. Every reconciliation that compared a breakdown to a total needs
rethinking, and your acceptance test no longer reproduces as written.

**Old rows don't disappear.** Rows loaded before the change kept their own identifiers and are
still sitting there with a NULL in the new column. Now you have two families of row for the same
period — one old and unsegmented, one new and segmented — and counting both doubles every additive
metric.

That last one needs an explicit guard: drop the NULL-dimension row only where a non-NULL row
exists for the same key.

```sql
AND NOT (
  segment IS NULL
  AND COUNTIF(segment IS NOT NULL) OVER (PARTITION BY period, dimension_value) > 0
)
```

Reports created *after* the change never had an old row family, so they shouldn't carry this
guard. Dead code that implies a problem is its own kind of problem.

---

## 4. Handling NULLs and empty values consistently

Ingestion tools commonly flatten `(not set)`, `(other)` and genuine NULL into one value. If yours
does, you lose the distinction described in
[docs/02 §7](02-scopes-and-compatibility.md#not-set-is-not-other).

Where a segment dimension is involved, three states need separating and they're easy to confuse:

```sql
CASE
  WHEN segment IS NULL              THEN '(all)'        -- no segmentation on this source
  WHEN segment IN ('', '(not set)') THEN '(not set)'    -- segmented, but untagged
  ELSE segment
END AS segment
```

`(all)` and `(not set)` mean opposite things. The first is "this source doesn't split by segment,
so this row covers everything." The second is "this source does split, and this row is the part
nobody tagged." Merging them turns a tagging gap into a phantom total.

---

## 5. Tagging problems look like data problems

Two that recur, both worth checking early because both are invisible in SQL:

**Case and punctuation splits.** `X_north` and `X North` are two values as far as GA4 is
concerned. A brand or segment that appears twice in a dimension list with slightly different
spelling is a tagging inconsistency, and normalising it in SQL only hides it. Fix the tag.

**Values with implausibly low counts.** A segment with one session in a month isn't a quiet
segment, it's a segment where tagging fires almost never. Treat any value with a near-zero count
as a tagging failure until proven otherwise.

Neither shows up in reconciliation, because the totals still add up. You find them by looking at
the dimension value list, which is worth doing whenever a new dimension goes live.

---

## 6. Adding a new report

1. Work through the design procedure in
   [docs/02 §5](02-scopes-and-compatibility.md#5-how-to-design-a-report).
2. Check compatibility against the API before building anything.
3. Estimate cardinality with the dimensions combined, not separately.
4. Add it to [spec/reports.yaml](../spec/reports.yaml) first , that file is the source of truth,
   and generating config from it keeps every environment consistent.
5. Build the staging model, including every dimension in the deduplication key.
6. Add the primary key test.
7. Write the "never use this for" note into the model file.
8. Wire up the mart last.

### When cloning to another property

The safest pattern is to copy an existing report definition from the **target** property and
change only what differs , the table name, the dimensions, the metrics. Property-specific things
like custom dimension IDs and custom channel group IDs then follow the target automatically, and
any field you didn't think about is preserved rather than guessed.

The alternative , exporting from a source property and stripping out what doesn't apply , works
for a bulk migration but is backwards for adding one report, because it requires you to know in
advance how the target is configured.

Custom dimension and channel group IDs are per-property. They will not transfer. Anything
referencing `customEvent:`, `customUser:` or `sessionCustomChannelGroup:` needs checking on every
property you clone to.

---

## 7. Two failure modes that waste the most time

### A schema change can park your pipeline

Many ingestion tools treat a new column or table as a schema change requiring approval. Until
someone approves it, the pipeline sits waiting. **No sync runs and no error is raised.** The
symptom is simply that nothing happens, which reads like a failed deployment.

If a change appears not to have taken effect, check the pipeline's schema status before you check
your code. And batch schema changes so you approve once rather than three times.

### Environment variables don't survive a new shell

An authentication error immediately after opening a terminal is almost always empty credentials
rather than wrong ones , an empty user and password sends a malformed auth header, and the API
reports it as an auth failure.

Keep credentials in a single file with restrictive permissions, source it at the start of a
session, and put a guard at the top of any script that uses them so the real cause is named:

```bash
[ -n "$API_KEY" ] && [ -n "$API_SECRET" ] || {
  echo "credentials not loaded in this shell"; exit 1; }
```

Never commit that file. The [.gitignore](../.gitignore) here covers the usual names.

---

## 8. Deployment order

For a full rebuild:

1. Confirm the source tables exist and have the columns you expect. Query the information schema
   rather than assuming — guessing a schema is how you get three rounds of rework.
2. Deploy staging.
3. Run the primary key tests. Stop if any fail.
4. Deploy marts.
5. Run reconciliation. Compare against your recorded baselines, not against zero.
6. Materialise if you need the speed, and schedule it after the pipeline's own run.

For a metric addition: ingestion, wait for a completed load, staging, marts, then re-run the
tests.

---

## 9. Things worth writing down once

Keep a short record somewhere durable — a file in this repo works — of:

- The property's reporting timezone. Every date boundary depends on it.
- The date of your last successful acceptance test, and its numbers.
- Your measured baseline gaps per table.
- Which reports carry a segment dimension and which don't.
- Any dimension whose values are known to be unreliable, and why.

