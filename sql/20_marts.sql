/* =============================================================================
   MARTS
   Long format: one row per period, dimension, dimension value and metric.

   Why long rather than wide — see 00_conventions.sql, pattern 4.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   DAILY MART

   Every metric here is additive across its own dimension. User metrics are
   deliberately absent: they're valid per row and per day, but a long mart
   invites summing, and summing users is always wrong.

   Read this for trends. Read totals_by_period for headline figures.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.breakdowns_daily` AS

WITH unioned AS (

  SELECT _source, date, 'Session channel' AS dimension_name,
         session_default_channel_group    AS dimension_value,
         sessions, engaged_sessions, key_events, purchase_revenue,
         transactions, CAST(NULL AS INT64) AS screen_page_views, CAST(NULL AS INT64) AS event_count
  FROM `__MODEL__.stg_traffic_acquisition_daily`

  UNION ALL
  SELECT _source, date, 'Session medium', session_medium,
         sessions, engaged_sessions, key_events, purchase_revenue,
         transactions, NULL, NULL
  FROM `__MODEL__.stg_traffic_acquisition_daily`

  UNION ALL
  SELECT _source, date, 'Session source', session_source,
         sessions, engaged_sessions, key_events, purchase_revenue,
         transactions, NULL, NULL
  FROM `__MODEL__.stg_traffic_acquisition_daily`

  UNION ALL
  SELECT _source, date, 'Landing page', landing_page,
         sessions, engaged_sessions, key_events, purchase_revenue,
         transactions, NULL, NULL
  FROM `__MODEL__.stg_landing_pages_daily`

  UNION ALL
  SELECT _source, date, 'Country', country,
         sessions, engaged_sessions, NULL, NULL, transactions, NULL, NULL
  FROM `__MODEL__.stg_geo_daily`

  UNION ALL
  SELECT _source, date, 'Device category', device_category,
         sessions, engaged_sessions, NULL, NULL, transactions, NULL, NULL
  FROM `__MODEL__.stg_tech_daily`

  UNION ALL
  SELECT _source, date, 'Browser', browser,
         sessions, engaged_sessions, NULL, NULL, transactions, NULL, NULL
  FROM `__MODEL__.stg_tech_daily`

  -- Event- and page-scoped sources contribute their own metrics only. No
  -- sessions, no users. This is the rule that keeps the mart safe to sum.
  UNION ALL
  SELECT _source, date, 'Page path', page_path,
         NULL, NULL, NULL, NULL, NULL, screen_page_views, event_count
  FROM `__MODEL__.stg_pages_daily`

  UNION ALL
  SELECT _source, date, 'Event name', event_name,
         NULL, NULL, key_events, NULL, NULL, NULL, event_count
  FROM `__MODEL__.stg_events_daily`

)

-- Aggregate to the dimension level, because several branches come from the same
-- multi-dimension source table.
SELECT
  _source,
  date,
  dimension_name,
  COALESCE(dimension_value, '(not set)') AS dimension_value,
  SUM(sessions)          AS sessions,
  SUM(engaged_sessions)  AS engaged_sessions,
  SUM(key_events)        AS key_events,
  SUM(purchase_revenue)  AS purchase_revenue,
  SUM(transactions)      AS transactions,
  SUM(screen_page_views) AS screen_page_views,
  SUM(event_count)       AS event_count
FROM unioned
GROUP BY _source, date, dimension_name, dimension_value;


/* -----------------------------------------------------------------------------
   MONTHLY MART

   This one DOES carry user metrics, because each row is a figure GA4 computed
   for that exact month and dimension value. Every row is exact.

   Read row by row. Filtering to one dimension_value and reading its user count
   is correct. Summing user columns across rows is not — no matter how tempting
   the column name makes it look.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.breakdowns_monthly` AS

SELECT _source, year_month, month_start_date, is_complete,
       'Session channel' AS dimension_name, dimension_value,
       total_users, active_users, new_users,
       sessions, engaged_sessions, event_count, key_events,
       purchase_revenue, transactions
FROM `__MODEL__.stg_channel_monthly`

UNION ALL
SELECT _source, year_month, month_start_date, is_complete,
       'Session medium', dimension_value,
       total_users, active_users, new_users,
       sessions, engaged_sessions, event_count, key_events,
       purchase_revenue, transactions
FROM `__MODEL__.stg_medium_monthly`

UNION ALL
SELECT _source, year_month, month_start_date, is_complete,
       'Device category', dimension_value,
       total_users, active_users, new_users,
       sessions, engaged_sessions, event_count, key_events,
       purchase_revenue, transactions
FROM `__MODEL__.stg_device_monthly`

UNION ALL
SELECT _source, year_month, month_start_date, is_complete,
       'Country', dimension_value,
       total_users, active_users, new_users,
       sessions, engaged_sessions, event_count, key_events,
       purchase_revenue, transactions
FROM `__MODEL__.stg_country_monthly`

-- Event-scoped source: user and session columns are NULL, not zero. Zero would
-- read as "no users", NULL reads as "not applicable here", which is the truth.
UNION ALL
SELECT _source, year_month, month_start_date, is_complete,
       'Event name', dimension_value,
       NULL, NULL, NULL,
       NULL, NULL, event_count, key_events,
       NULL, NULL
FROM `__MODEL__.stg_event_monthly`;


/* -----------------------------------------------------------------------------
   TOTALS BY PERIOD

   Day, ISO week and month in one shape.

   THIS IS THE ONLY PLACE A TOTAL COMES FROM.

   The breakdown marts match GA4 row for row, but reaching a single headline
   number from one of them means summing, and summing is where the additivity
   rule bites. For user counts there is no approximation at all — a monthly user
   figure has to be one GA4 was asked for directly, which is what the monthly
   branch below is.

   On a dashboard: scorecard tiles read THIS view, breakdown charts read the
   breakdown marts. Two separate data sources. One source doing both is how a
   summed breakdown ends up in a scorecard.

   Expect the two to disagree slightly and expect somebody to notice. Both are
   correct — see docs/01.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.totals_by_period` AS

SELECT
  _source, 'day' AS grain,
  date AS period_start, date AS period_end,
  FORMAT_DATE('%Y-%m-%d', date) AS period_label,
  TRUE AS is_complete,
  total_users, active_users, new_users, sessions, engaged_sessions,
  key_events, purchase_revenue, screen_page_views, event_count,
  engagement_rate, sessions_per_active_user
FROM `__MODEL__.stg_totals_daily`

UNION ALL
SELECT
  _source, 'iso_week',
  week_start_date, week_end_date,
  iso_year_iso_week,
  is_complete,
  total_users, active_users, new_users, sessions, engaged_sessions,
  key_events, purchase_revenue, screen_page_views, event_count,
  SAFE_DIVIDE(engaged_sessions, sessions),
  SAFE_DIVIDE(sessions, active_users)
FROM `__MODEL__.stg_totals_weekly`

UNION ALL
SELECT
  _source, 'month',
  month_start_date, month_end_date,
  FORMAT_DATE('%Y-%m', month_start_date),
  is_complete,
  total_users, active_users, new_users, sessions, engaged_sessions,
  key_events, purchase_revenue, screen_page_views, event_count,
  SAFE_DIVIDE(engaged_sessions, sessions),
  SAFE_DIVIDE(sessions, active_users)
FROM `__MODEL__.stg_totals_monthly`;


/* -----------------------------------------------------------------------------
   HOW TO QUERY THESE

   Sessions by channel, last 90 days — correct:
     SELECT date, dimension_value, sessions
     FROM breakdowns_daily
     WHERE dimension_name = 'Session channel'
       AND date >= CURRENT_DATE() - 90;

   Users last month — correct, from the totals view:
     SELECT total_users FROM totals_by_period
     WHERE grain = 'month' AND period_label = '2026-07';

   Users by channel last month — correct, row by row:
     SELECT dimension_value, total_users
     FROM breakdowns_monthly
     WHERE dimension_name = 'Session channel' AND year_month = '202607';

   Users for a GROUP of channels — NOT available by summing. See
   baselines/40_subset_rollup.sql for what you can do instead.

   Anything filtered to ONE dimension value and then summed over periods is
   safe. The additivity problem only bites when summing ACROSS values.
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   MATERIALISATION (optional)

   Only if dashboards feel slow. Schedule these AFTER your pipeline's own run,
   not on a fixed clock, or you'll publish yesterday's numbers.
   ----------------------------------------------------------------------------- */

-- CREATE OR REPLACE TABLE `__MODEL__.breakdowns_daily_mat`
-- PARTITION BY date
-- CLUSTER BY _source, dimension_name, dimension_value AS
-- SELECT * FROM `__MODEL__.breakdowns_daily`;

-- CREATE OR REPLACE TABLE `__MODEL__.breakdowns_monthly_mat`
-- PARTITION BY month_start_date
-- CLUSTER BY _source, dimension_name, dimension_value AS
-- SELECT * FROM `__MODEL__.breakdowns_monthly`;
