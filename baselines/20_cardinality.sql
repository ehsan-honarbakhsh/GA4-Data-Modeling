/* =============================================================================
   MEASURE: cardinality
   How close is each report to GA4's row ceiling, and is anything already
   collapsing into (other)?

   Run this whenever you add a dimension to an existing report. Dimensions
   multiply, and a report that was comfortable can stop being comfortable in one
   change.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   1. DISTINCT VALUES PER DIMENSION PER MONTH

   GA4 collapses the tail past roughly 50,000 unique combinations in a day.
   Anything in the thousands deserves attention before you add another dimension
   to it.
   ----------------------------------------------------------------------------- */

SELECT
  _source,
  dimension_name,
  year_month,
  COUNT(DISTINCT dimension_value)               AS distinct_values,
  COUNTIF(dimension_value = '(other)')          AS other_rows,
  COUNTIF(dimension_value IN ('(not set)', '')) AS not_set_rows,
  CASE
    WHEN COUNT(DISTINCT dimension_value) > 20000 THEN 'AT RISK'
    WHEN COUNT(DISTINCT dimension_value) >  5000 THEN 'watch'
    ELSE 'fine'
  END                                           AS headroom
FROM `__MODEL__.breakdowns_monthly`
GROUP BY _source, dimension_name, year_month
ORDER BY distinct_values DESC;


/* -----------------------------------------------------------------------------
   2. HOW MUCH DATA IS SITTING IN (other)

   Any share above zero means the table is no longer complete for exactly the
   long-tail values it exists to show.

   The fix is to reduce cardinality — drop query strings, use a coarser
   dimension, split the report. Not to filter (other) out.
   ----------------------------------------------------------------------------- */

SELECT
  _source,
  dimension_name,
  year_month,
  SUM(IF(dimension_value = '(other)', sessions, 0)) AS other_sessions,
  SUM(sessions)                                     AS all_sessions,
  ROUND(SAFE_DIVIDE(
    SUM(IF(dimension_value = '(other)', sessions, 0)),
    SUM(sessions)) * 100, 2)                        AS other_share_pct
FROM `__MODEL__.breakdowns_monthly`
GROUP BY _source, dimension_name, year_month
HAVING other_sessions > 0
ORDER BY other_share_pct DESC;


/* -----------------------------------------------------------------------------
   3. TAGGING GAPS

   A high (not set) share is a tracking problem, not a modelling one. Worth
   separating from (other), which is a design problem — see docs/02 section 7.
   ----------------------------------------------------------------------------- */

SELECT
  _source,
  dimension_name,
  year_month,
  ROUND(SAFE_DIVIDE(
    SUM(IF(dimension_value IN ('(not set)', ''), sessions, 0)),
    SUM(sessions)) * 100, 2)                        AS not_set_share_pct
FROM `__MODEL__.breakdowns_monthly`
GROUP BY _source, dimension_name, year_month
HAVING not_set_share_pct > 1
ORDER BY not_set_share_pct DESC;


/* -----------------------------------------------------------------------------
   4. SUSPICIOUSLY RARE VALUES

   A dimension value with one or two sessions in a month usually isn't a quiet
   segment. It's a tag that almost never fires. Worth checking before anyone
   builds a report on it.
   ----------------------------------------------------------------------------- */

SELECT
  _source,
  dimension_name,
  dimension_value,
  SUM(sessions) AS sessions
FROM `__MODEL__.breakdowns_monthly`
GROUP BY _source, dimension_name, dimension_value
HAVING SUM(sessions) BETWEEN 1 AND 10
ORDER BY dimension_name, sessions;
