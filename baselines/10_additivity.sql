/* =============================================================================
   MEASURE: additivity
   How far does each dimension overcount when you sum across it?

   Run on a COMPLETE month. Record the results — these become the expected gaps
   your reconciliation scores against.
   ============================================================================= */

DECLARE target_month STRING DEFAULT '202607';   -- change me


/* -----------------------------------------------------------------------------
   1. SESSION OVERCOUNT BY DIMENSION

   Sums sessions across each dimension and compares to the true monthly total.

   ratio near 1.00  the dimension is effectively session-scoped
   ratio 1.01-1.10  resolved per event but nearly stable (geography, tech)
   ratio above 2    event-scoped; never sum sessions across this
   ----------------------------------------------------------------------------- */

WITH truth AS (
  SELECT _source, sessions AS true_sessions
  FROM `__MODEL__.stg_totals_monthly`
  WHERE year_month = target_month
),

summed AS (
  SELECT _source, dimension_name, SUM(sessions) AS summed_sessions
  FROM `__MODEL__.breakdowns_monthly`
  WHERE year_month = target_month
  GROUP BY _source, dimension_name
)

SELECT
  s._source,
  s.dimension_name,
  t.true_sessions,
  s.summed_sessions,
  ROUND(SAFE_DIVIDE(s.summed_sessions, t.true_sessions), 4)         AS ratio,
  ROUND(SAFE_DIVIDE(s.summed_sessions - t.true_sessions,
                    t.true_sessions) * 100, 2)                      AS overcount_pct,
  CASE
    WHEN SAFE_DIVIDE(s.summed_sessions, t.true_sessions) > 1.5  THEN 'NEVER SUM'
    WHEN SAFE_DIVIDE(s.summed_sessions, t.true_sessions) > 1.02 THEN 'sum with caution'
    ELSE 'safe to sum'
  END                                                               AS verdict
FROM summed s
JOIN truth  t USING (_source)
ORDER BY ratio DESC;


/* -----------------------------------------------------------------------------
   2. USER OVERLAP FACTOR

   How much do daily users overstate monthly users?

   This is the number to quote when somebody asks why they can't just add up
   daily users. It's also a rough proxy for how often your visitors return.
   ----------------------------------------------------------------------------- */

WITH daily AS (
  SELECT
    _source,
    FORMAT_DATE('%Y%m', date) AS year_month,
    SUM(total_users)          AS users_summed_from_daily
  FROM `__MODEL__.stg_totals_daily`
  GROUP BY _source, year_month
)

SELECT
  m._source,
  m.year_month,
  d.users_summed_from_daily,
  m.total_users                                                      AS true_monthly_users,
  ROUND(SAFE_DIVIDE(d.users_summed_from_daily, m.total_users), 4)    AS user_overlap_factor,
  ROUND((SAFE_DIVIDE(d.users_summed_from_daily, m.total_users) - 1) * 100, 1)
                                                                     AS overstatement_pct
FROM `__MODEL__.stg_totals_monthly` m
JOIN daily d USING (_source, year_month)
WHERE m.is_complete
ORDER BY m.year_month DESC;


/* -----------------------------------------------------------------------------
   3. USER OVERCOUNT ACROSS A DIMENSION

   Same idea, one dimension at a time. Tells you how much a "users by channel"
   table would overstate if somebody summed it.
   ----------------------------------------------------------------------------- */

WITH truth AS (
  SELECT _source, total_users AS true_users
  FROM `__MODEL__.stg_totals_monthly`
  WHERE year_month = target_month
),

summed AS (
  SELECT _source, dimension_name, SUM(total_users) AS summed_users
  FROM `__MODEL__.breakdowns_monthly`
  WHERE year_month = target_month
    AND total_users IS NOT NULL
  GROUP BY _source, dimension_name
)

SELECT
  s._source,
  s.dimension_name,
  t.true_users,
  s.summed_users,
  ROUND(SAFE_DIVIDE(s.summed_users, t.true_users), 4) AS ratio,
  'never sum users across anything'                   AS verdict
FROM summed s
JOIN truth  t USING (_source)
ORDER BY ratio DESC;
