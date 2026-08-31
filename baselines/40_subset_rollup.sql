/* =============================================================================
   MEASURE: rolling up a subset of dimension values

   The most common real question this design can't answer directly:

     "How many users came from ALL the organic channels combined?"

   Sessions and revenue sum fine. Users don't — somebody who arrived via organic
   search in week one and organic social in week three sits in both rows.

   This query gives you exact figures where they exist and honest bounds where
   they don't.
   ============================================================================= */

DECLARE target_month STRING DEFAULT '202607';   -- change me


/* -----------------------------------------------------------------------------
   1. WHAT YOU CAN GET TODAY

   Session-scoped metrics are exact. User metrics come with bounds:
     upper = the sum, which double-counts anyone who used two of these channels
     lower = the largest single value, which ignores everyone else

   The truth is between them, usually much closer to the upper bound.
   ----------------------------------------------------------------------------- */

SELECT
  _source,
  year_month,

  -- Exact: every session belongs to exactly one channel
  SUM(sessions)          AS sessions,
  SUM(engaged_sessions)  AS engaged_sessions,
  SUM(event_count)       AS event_count,
  SUM(key_events)        AS key_events,
  SUM(purchase_revenue)  AS purchase_revenue,
  SUM(transactions)      AS transactions,

  -- Bounds only
  SUM(total_users)       AS users_upper_bound,
  MAX(total_users)       AS users_lower_bound,
  COUNT(*)               AS channels_included

FROM `__MODEL__.breakdowns_monthly`
WHERE dimension_name = 'Session channel'
  AND year_month     = target_month
  AND dimension_value LIKE 'Organic%'     -- change to your subset
GROUP BY _source, year_month;


/* -----------------------------------------------------------------------------
   2. HOW WIDE ARE THOSE BOUNDS, REALLY?

   Measure your property's overlap once and you'll know roughly where inside the
   bounds the truth sits. Compare the sum across ALL channels to the true total.
   ----------------------------------------------------------------------------- */

WITH all_channels AS (
  SELECT _source, year_month, SUM(total_users) AS users_summed
  FROM `__MODEL__.breakdowns_monthly`
  WHERE dimension_name = 'Session channel'
  GROUP BY _source, year_month
)

SELECT
  t._source,
  t.year_month,
  a.users_summed,
  t.total_users                                              AS true_users,
  ROUND(SAFE_DIVIDE(a.users_summed, t.total_users), 4)       AS inflation_factor,
  ROUND((SAFE_DIVIDE(a.users_summed, t.total_users) - 1) * 100, 1)
                                                             AS inflation_pct
FROM `__MODEL__.stg_totals_monthly` t
JOIN all_channels a USING (_source, year_month)
WHERE t.is_complete
ORDER BY t.year_month DESC;


/* -----------------------------------------------------------------------------
   3. THE PROPER FIX

   Bounds are a workaround. To get an exact user count for a group of values,
   GA4 has to do the grouping.

   Define a CUSTOM CHANNEL GROUP in GA4 (Admin > Data display > Channel groups)
   with a bucket for the combination you care about — "Organic (all)", "Paid
   (all)", whatever the business actually asks for. Then add a report using
   sessionCustomChannelGroup instead of sessionDefaultChannelGroup.

   GA4 then counts users for the combined bucket server-side, in one pass, and
   the number is exact.

   This scales to any grouping you define later. A one-off filtered report
   answers only the question somebody asked today.

   Custom channel group IDs are per-property and will not transfer when cloning
   reports elsewhere. See docs/05 section 6.
   ----------------------------------------------------------------------------- */
