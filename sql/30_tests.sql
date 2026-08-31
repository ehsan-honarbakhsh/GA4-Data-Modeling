/* =============================================================================
   TESTS
   Every test returns ZERO ROWS when healthy. Rows mean something needs looking at.

   Run the primary key tests before deploying marts. A broken deduplication key
   produces marts that look completely fine.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   TEST 1 — PRIMARY KEYS

   The cheapest and most valuable test here. Rows returned mean the
   deduplication key is missing a dimension, and the view is throwing data away
   without telling you.

   Add a branch for every staging view you create.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.test_primary_keys` AS

SELECT 'stg_totals_daily' AS view_name, report_pk, COUNT(*) AS duplicate_rows
FROM `__MODEL__.stg_totals_daily` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_totals_weekly', report_pk, COUNT(*)
FROM `__MODEL__.stg_totals_weekly` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_totals_monthly', report_pk, COUNT(*)
FROM `__MODEL__.stg_totals_monthly` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_traffic_acquisition_daily', report_pk, COUNT(*)
FROM `__MODEL__.stg_traffic_acquisition_daily` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_user_acquisition_daily', report_pk, COUNT(*)
FROM `__MODEL__.stg_user_acquisition_daily` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_landing_pages_daily', report_pk, COUNT(*)
FROM `__MODEL__.stg_landing_pages_daily` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_pages_daily', report_pk, COUNT(*)
FROM `__MODEL__.stg_pages_daily` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_events_daily', report_pk, COUNT(*)
FROM `__MODEL__.stg_events_daily` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_geo_daily', report_pk, COUNT(*)
FROM `__MODEL__.stg_geo_daily` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_tech_daily', report_pk, COUNT(*)
FROM `__MODEL__.stg_tech_daily` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_channel_monthly', report_pk, COUNT(*)
FROM `__MODEL__.stg_channel_monthly` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_medium_monthly', report_pk, COUNT(*)
FROM `__MODEL__.stg_medium_monthly` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_device_monthly', report_pk, COUNT(*)
FROM `__MODEL__.stg_device_monthly` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_country_monthly', report_pk, COUNT(*)
FROM `__MODEL__.stg_country_monthly` GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_event_monthly', report_pk, COUNT(*)
FROM `__MODEL__.stg_event_monthly` GROUP BY 1, 2 HAVING COUNT(*) > 1;


/* -----------------------------------------------------------------------------
   TEST 2 — FRESHNESS

   Obvious, and routinely missing. A stalled pipeline stays invisible until
   somebody notices a flat line on a chart, which usually takes a week or two.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.test_freshness` AS
SELECT
  _source,
  MAX(date)                                               AS latest_date,
  DATE_DIFF(CURRENT_DATE('__TIMEZONE__'), MAX(date), DAY) AS days_behind
FROM `__MODEL__.stg_totals_daily`
GROUP BY _source
-- Two days is the normal lag from the completeness cutoff. Four means something
-- has stopped.
HAVING DATE_DIFF(CURRENT_DATE('__TIMEZONE__'), MAX(date), DAY) > 4;


/* -----------------------------------------------------------------------------
   TEST 3 — CARDINALITY COLLAPSE

   Any (other) row means a table has stopped being complete. Worth a standing
   check rather than a one-off — cardinality creeps up as a business grows.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.test_other_rows` AS
SELECT
  _source,
  date,
  dimension_name,
  SUM(sessions)                                                 AS other_sessions,
  SAFE_DIVIDE(
    SUM(sessions),
    SUM(SUM(sessions)) OVER (PARTITION BY _source, date, dimension_name)
  )                                                             AS other_share
FROM `__MODEL__.breakdowns_daily`
WHERE dimension_value = '(other)'
GROUP BY _source, date, dimension_name
HAVING SUM(sessions) > 0;


/* -----------------------------------------------------------------------------
   TEST 4 — RECONCILIATION

   Compares each breakdown to the totals table, on metrics that are genuinely
   additive across that breakdown's dimension.

   The gap will NOT be zero, and it isn't meant to be. What matters is that it's
   stable. Compare against your own measured baselines — see baselines/ — not
   against zero.

   Note the signed gap. Never take an absolute value here: excess means double
   counting, shortfall means data loss, and they have opposite causes.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.recon_daily` AS

WITH breakdown AS (
  SELECT
    _source, date, dimension_name,
    SUM(sessions)         AS sessions,
    SUM(key_events)       AS key_events,
    SUM(purchase_revenue) AS purchase_revenue
  FROM `__MODEL__.breakdowns_daily`
  -- Only dimensions where sessions are genuinely additive. Page path and event
  -- name are excluded on purpose: testing sessions there would fail every day,
  -- forever, by design.
  WHERE dimension_name IN ('Session channel', 'Session medium', 'Session source',
                           'Landing page', 'Device category', 'Browser')
  GROUP BY _source, date, dimension_name
)

SELECT
  b._source,
  b.date,
  b.dimension_name,
  b.sessions                                             AS breakdown_sessions,
  t.sessions                                             AS total_sessions,
  b.sessions - t.sessions                                AS session_gap,
  SAFE_DIVIDE(b.sessions - t.sessions, t.sessions)       AS session_gap_pct,
  b.key_events - t.key_events                            AS key_event_gap,
  SAFE_DIVIDE(b.key_events - t.key_events, t.key_events) AS key_event_gap_pct,
  ROUND(b.purchase_revenue - t.purchase_revenue, 2)      AS revenue_gap
FROM breakdown b
JOIN `__MODEL__.stg_totals_daily` t
  USING (_source, date);


/* -----------------------------------------------------------------------------
   TEST 5 — CROSS-GRAIN

   Daily rolled up to a month, against the monthly table.

   Expect a small POSITIVE gap on sessions: a visit spanning midnight is counted
   in both days. Measured at about +1.5% on one property.

   If it goes to zero, you're probably reading the same table twice. If it grows,
   look for duplicate rows.

   Sessions only. Users at two grains aren't comparable and the number means
   nothing.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.recon_cross_grain` AS

WITH daily_rolled AS (
  SELECT
    _source,
    FORMAT_DATE('%Y%m', date) AS year_month,
    SUM(sessions)             AS sessions_from_daily,
    SUM(key_events)           AS key_events_from_daily
  FROM `__MODEL__.stg_totals_daily`
  GROUP BY _source, year_month
)

SELECT
  m._source,
  m.year_month,
  d.sessions_from_daily,
  m.sessions                                                          AS sessions_monthly,
  d.sessions_from_daily - m.sessions                                  AS session_gap,
  SAFE_DIVIDE(d.sessions_from_daily - m.sessions, m.sessions)         AS session_gap_pct,
  SAFE_DIVIDE(d.key_events_from_daily - m.key_events, m.key_events)   AS key_event_gap_pct
FROM `__MODEL__.stg_totals_monthly` m
JOIN daily_rolled d USING (_source, year_month)
WHERE m.is_complete;


/* -----------------------------------------------------------------------------
   TEST 6 — DIMENSION VALUE COUNTS

   Sudden changes in the number of distinct values usually mean a tagging change
   upstream. A country count dropping from 150 to 12 is a broken tag, not a
   collapse in international traffic.

   This one is a report, not a pass/fail. Look at it when something feels off.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.monitor_dimension_values` AS
SELECT
  _source,
  dimension_name,
  DATE_TRUNC(date, MONTH)                AS month,
  COUNT(DISTINCT dimension_value)        AS distinct_values,
  COUNTIF(dimension_value = '(not set)') AS not_set_rows
FROM `__MODEL__.breakdowns_daily`
GROUP BY _source, dimension_name, month
ORDER BY dimension_name, month DESC;


/* -----------------------------------------------------------------------------
   RUNNING THEM

     SELECT * FROM `__MODEL__.test_primary_keys`;   -- expect zero rows
     SELECT * FROM `__MODEL__.test_freshness`;      -- expect zero rows
     SELECT * FROM `__MODEL__.test_other_rows`;     -- expect zero rows

     SELECT * FROM `__MODEL__.recon_daily`
     WHERE date >= CURRENT_DATE() - 30
     ORDER BY ABS(session_gap_pct) DESC;

     SELECT * FROM `__MODEL__.recon_cross_grain` ORDER BY year_month DESC;
   ----------------------------------------------------------------------------- */
