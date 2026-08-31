/* =============================================================================
   MEASURE: cross-grain consistency
   Daily rolled up to a month, against the monthly table.

   Expect a small positive gap on sessions — visits spanning midnight land in two
   days. Measured at about +1.5% on one property.

   What the result tells you:
     small, positive, stable   healthy
     zero                      you're probably reading the same table twice
     growing over time         duplicate rows from restatement; check your keys
     negative                  data loss in the daily table
   ============================================================================= */

WITH daily_rolled AS (
  SELECT
    _source,
    FORMAT_DATE('%Y%m', date)  AS year_month,
    COUNT(*)                   AS days_present,
    SUM(sessions)              AS sessions,
    SUM(engaged_sessions)      AS engaged_sessions,
    SUM(key_events)            AS key_events,
    SUM(purchase_revenue)      AS purchase_revenue,
    SUM(event_count)           AS event_count,
    SUM(total_users)           AS users_summed
  FROM `__MODEL__.stg_totals_daily`
  GROUP BY _source, year_month
)

SELECT
  m._source,
  m.year_month,
  d.days_present,
  EXTRACT(DAY FROM m.month_end_date)                                   AS days_in_month,

  -- Sessions: expect a small positive gap
  d.sessions                                                           AS sessions_from_daily,
  m.sessions                                                           AS sessions_monthly,
  ROUND(SAFE_DIVIDE(d.sessions - m.sessions, m.sessions) * 100, 2)     AS session_gap_pct,

  -- Event-scoped metrics: expect these to match almost exactly, because every
  -- event belongs to exactly one day
  ROUND(SAFE_DIVIDE(d.key_events  - m.key_events,  m.key_events)  * 100, 2) AS key_event_gap_pct,
  ROUND(SAFE_DIVIDE(d.event_count - m.event_count, m.event_count) * 100, 2) AS event_count_gap_pct,
  ROUND(d.purchase_revenue - m.purchase_revenue, 2)                    AS revenue_gap,

  -- Users: NOT a gap, a category error. Shown to make the point visible.
  d.users_summed                                                       AS users_summed_from_daily,
  m.total_users                                                        AS true_monthly_users,
  ROUND(SAFE_DIVIDE(d.users_summed, m.total_users), 3)                 AS user_overlap_factor

FROM `__MODEL__.stg_totals_monthly` m
JOIN daily_rolled d USING (_source, year_month)
WHERE m.is_complete
ORDER BY m.year_month DESC;


/* -----------------------------------------------------------------------------
   A note on days_present

   If days_present is lower than days_in_month, the daily table has gaps and
   every gap figure above is understated. Fix that before reading anything else
   here.
   ----------------------------------------------------------------------------- */
