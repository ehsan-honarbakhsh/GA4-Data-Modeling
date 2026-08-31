/* =============================================================================
   CONVENTIONS
   Read this file. Don't run it.

   Everything in sql/ follows the four patterns below. If you add a model, follow
   them too — most of the bugs this design can produce are caught by doing so.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   THE TWO THINGS TO CHANGE

     __LANDING__   the dataset your pipeline writes to
     __MODEL__     the dataset these views should live in

   If your pipeline names its housekeeping columns differently, change these too:

     _synced_at    when the row was loaded
     _source       which property or pipeline it came from
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   PATTERN 1 — DEDUPLICATION

   GA4 restates recent periods, so your pipeline re-reads days it already loaded
   and the same logical row arrives more than once. Keep the newest.

     QUALIFY ROW_NUMBER() OVER (
       PARTITION BY <every dimension in the report>
       ORDER BY _synced_at DESC
     ) = 1

   EVERY dimension. Miss one and this keeps a single row per partial key and
   throws the rest away — silently, with no error, producing numbers that are
   simply too small.

   This is the most damaging bug the design can have, and the reason every
   staging view below is followed by a primary key test.
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   PATTERN 2 — THE PRIMARY KEY

   Every staging view builds a report_pk from its full natural key. It exists so
   the test in 30_tests.sql can prove the deduplication worked.

     CONCAT(
       COALESCE(CAST(period  AS STRING), ''),
       '|', COALESCE(CAST(_source AS STRING), ''),
       '|', COALESCE(CAST(dim_1 AS STRING), ''),
       '|', COALESCE(CAST(dim_2 AS STRING), '')
     ) AS report_pk

   COALESCE every part. A NULL anywhere in CONCAT makes the whole string NULL,
   and every NULL key then collides with every other.
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   PATTERN 3 — COMPLETENESS

   The last day or two of GA4 data is still moving. Publishing it produces a
   chart that dips at the right-hand edge and a stream of questions about it.

   Daily models cut off:
     WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2

   Monthly models flag rather than cut, so month-to-date is available but
   labelled:
     LAST_DAY(month_start) <= CURRENT_DATE('__TIMEZONE__') - 2 AS is_complete

   Use the GA4 property's reporting timezone, not your own.
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   PATTERN 4 — LONG-FORMAT MARTS

   The marts are long, not wide: one row per period, dimension, dimension value
   and metric.

     period | dimension_name | dimension_value | metric_name | metric_value

   Wide marts need a schema change every time a report is added. Long marts
   don't, and BI tools handle them well. The cost is that you can't compute a
   ratio across two metrics in a single row — which is a feature here, because
   ratios shouldn't be computed that way anyway. See docs/02 section 3.
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   NAMING

     stg_<report>            staging view, one per report
     breakdowns_daily        long-format daily mart
     breakdowns_monthly      long-format monthly mart
     totals_by_period        day / ISO week / month totals in one view
     recon_*                 reconciliation views
     test_*                  tests, each returning zero rows when healthy

   Dimension values in the marts get a human-readable dimension_name — 'Session
   channel', not 'session_default_channel_group'. It's what ends up on a chart
   legend.
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   THE SEGMENT COLUMN (optional)

   If you run a custom dimension that splits the business, it must appear in
   every deduplication key, and three states need keeping apart:

     CASE
       WHEN segment IS NULL              THEN '(all)'
       WHEN segment IN ('', '(not set)') THEN '(not set)'
       ELSE segment
     END AS segment

   '(all)'      this source doesn't split by segment; the row covers everything
   '(not set)'  this source does split, and nobody tagged this row

   They mean opposite things. Merging them turns a tagging gap into a phantom
   total. See docs/05 section 4.

   The models below leave the segment column out. Add it to the SELECT list and
   to every PARTITION BY if you need it.
   ----------------------------------------------------------------------------- */


-- Create the model dataset. Set the location to match your landing dataset.
CREATE SCHEMA IF NOT EXISTS `__MODEL__` OPTIONS (location = 'EU');
