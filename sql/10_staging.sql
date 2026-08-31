/* =============================================================================
   STAGING
   One view per report. Deduplicated, typed, keyed.

   Replace __LANDING__, __MODEL__ and __TIMEZONE__ before running.
   Patterns explained in 00_conventions.sql.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   TIER 0 — TOTALS
   No dimensions, so no additivity problems. These are the anchors everything
   else is measured against, and the only source of an exact user count.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.stg_totals_daily` AS
SELECT
  _source,
  date,
  total_users,
  active_users,
  new_users,
  sessions,
  engaged_sessions,
  screen_page_views,
  event_count,
  key_events,                                   -- FLOAT64: fractional attribution credit
  purchase_revenue,
  user_engagement_duration,
  SAFE_DIVIDE(engaged_sessions, sessions)    AS engagement_rate,
  SAFE_DIVIDE(sessions, active_users)        AS sessions_per_active_user,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, '')) AS report_pk
FROM `__LANDING__.ga4_totals_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (PARTITION BY _source, date ORDER BY _synced_at DESC) = 1;


CREATE OR REPLACE VIEW `__MODEL__.stg_totals_weekly` AS
SELECT
  _source,
  iso_year_iso_week,
  -- Rebuild the Monday. Never parse a calendar year from the first four
  -- characters: 2026-12-28 belongs to ISO week 202701.
  PARSE_DATE('%G%V%u', CONCAT(iso_year_iso_week, '1'))       AS week_start_date,
  DATE_ADD(PARSE_DATE('%G%V%u', CONCAT(iso_year_iso_week, '1')), INTERVAL 6 DAY) AS week_end_date,
  total_users, active_users, new_users, sessions, engaged_sessions,
  screen_page_views, event_count, key_events, purchase_revenue,
  user_engagement_duration,
  DATE_ADD(PARSE_DATE('%G%V%u', CONCAT(iso_year_iso_week, '1')), INTERVAL 6 DAY)
    <= CURRENT_DATE('__TIMEZONE__') - 2                      AS is_complete,
  CONCAT(iso_year_iso_week, '|', COALESCE(_source, ''))      AS report_pk
FROM `__LANDING__.ga4_totals_weekly`
QUALIFY ROW_NUMBER() OVER (PARTITION BY _source, iso_year_iso_week ORDER BY _synced_at DESC) = 1;


CREATE OR REPLACE VIEW `__MODEL__.stg_totals_monthly` AS
SELECT
  _source,
  year_month,
  PARSE_DATE('%Y%m%d', CONCAT(year_month, '01'))             AS month_start_date,
  LAST_DAY(PARSE_DATE('%Y%m%d', CONCAT(year_month, '01')))   AS month_end_date,
  total_users, active_users, new_users, sessions, engaged_sessions,
  screen_page_views, event_count, key_events, purchase_revenue,
  user_engagement_duration,
  LAST_DAY(PARSE_DATE('%Y%m%d', CONCAT(year_month, '01')))
    <= CURRENT_DATE('__TIMEZONE__') - 2                      AS is_complete,
  CONCAT(year_month, '|', COALESCE(_source, ''))             AS report_pk
FROM `__LANDING__.ga4_totals_monthly`
QUALIFY ROW_NUMBER() OVER (PARTITION BY _source, year_month ORDER BY _synced_at DESC) = 1;


/* -----------------------------------------------------------------------------
   TIER 1 — DAILY BREAKDOWNS

   Session and event metrics are reliable here. User metrics are valid per row
   and per day only — never sum them across dimension values or across dates.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.stg_traffic_acquisition_daily` AS
SELECT
  _source, date,
  session_source, session_medium, session_campaign_name, session_default_channel_group,
  sessions, engaged_sessions, engagement_rate, active_users, key_events,
  purchase_revenue, transactions,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, ''),
         '|', COALESCE(session_source, ''), '|', COALESCE(session_medium, ''),
         '|', COALESCE(session_campaign_name, ''),
         '|', COALESCE(session_default_channel_group, '')) AS report_pk
FROM `__LANDING__.ga4_traffic_acquisition_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, date, session_source, session_medium,
               session_campaign_name, session_default_channel_group
  ORDER BY _synced_at DESC) = 1;


-- User-scoped dimensions. new_users is the honest headline metric here; the
-- session metrics run about 3% high because identity stitching can change a
-- user's first-touch value inside the window. See docs/02 section 4.2.
CREATE OR REPLACE VIEW `__MODEL__.stg_user_acquisition_daily` AS
SELECT
  _source, date,
  first_user_source, first_user_medium, first_user_campaign_name,
  first_user_default_channel_group,
  new_users, total_users, engaged_sessions, key_events, purchase_revenue,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, ''),
         '|', COALESCE(first_user_source, ''), '|', COALESCE(first_user_medium, ''),
         '|', COALESCE(first_user_campaign_name, ''),
         '|', COALESCE(first_user_default_channel_group, '')) AS report_pk
FROM `__LANDING__.ga4_user_acquisition_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, date, first_user_source, first_user_medium,
               first_user_campaign_name, first_user_default_channel_group
  ORDER BY _synced_at DESC) = 1;


-- Landing page is SESSION-scoped, unlike page path. This is the table to use
-- when somebody asks for "sessions by page".
CREATE OR REPLACE VIEW `__MODEL__.stg_landing_pages_daily` AS
SELECT
  _source, date,
  landing_page_plus_query_string AS landing_page,
  sessions, engaged_sessions, active_users, key_events, purchase_revenue, transactions,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, ''),
         '|', COALESCE(landing_page_plus_query_string, '')) AS report_pk
FROM `__LANDING__.ga4_landing_pages_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, date, landing_page_plus_query_string
  ORDER BY _synced_at DESC) = 1;


-- EVENT-SCOPED. No session or user metrics, by design. Page path is event-scoped,
-- so sessions here would run roughly 2.5x high when summed.
CREATE OR REPLACE VIEW `__MODEL__.stg_pages_daily` AS
SELECT
  _source, date, host_name, page_path,
  screen_page_views, event_count, user_engagement_duration, bounce_rate,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, ''),
         '|', COALESCE(host_name, ''), '|', COALESCE(page_path, '')) AS report_pk
FROM `__LANDING__.ga4_pages_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, date, host_name, page_path
  ORDER BY _synced_at DESC) = 1;


-- EVENT-SCOPED. Adding sessions here was measured at 5.3x the true count.
CREATE OR REPLACE VIEW `__MODEL__.stg_events_daily` AS
SELECT
  _source, date, event_name,
  event_count, event_value, key_events,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, ''),
         '|', COALESCE(event_name, '')) AS report_pk
FROM `__LANDING__.ga4_events_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, date, event_name ORDER BY _synced_at DESC) = 1;


-- Location resolves per event, so summed sessions run about 5% high. Fine for
-- shape; don't use it for a figure that has to tie out.
CREATE OR REPLACE VIEW `__MODEL__.stg_geo_daily` AS
SELECT
  _source, date, country, region,
  sessions, engaged_sessions, active_users, new_users, transactions,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, ''),
         '|', COALESCE(country, ''), '|', COALESCE(region, '')) AS report_pk
FROM `__LANDING__.ga4_geo_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, date, country, region ORDER BY _synced_at DESC) = 1;


CREATE OR REPLACE VIEW `__MODEL__.stg_geo_city_daily` AS
SELECT
  _source, date, city,
  sessions, active_users, transactions,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, ''),
         '|', COALESCE(city, '')) AS report_pk
FROM `__LANDING__.ga4_geo_city_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, date, city ORDER BY _synced_at DESC) = 1;


CREATE OR REPLACE VIEW `__MODEL__.stg_tech_daily` AS
SELECT
  _source, date, device_category, browser, operating_system,
  sessions, engaged_sessions, active_users, transactions,
  CONCAT(CAST(date AS STRING), '|', COALESCE(_source, ''),
         '|', COALESCE(device_category, ''), '|', COALESCE(browser, ''),
         '|', COALESCE(operating_system, '')) AS report_pk
FROM `__LANDING__.ga4_tech_daily`
WHERE date <= CURRENT_DATE('__TIMEZONE__') - 2
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, date, device_category, browser, operating_system
  ORDER BY _synced_at DESC) = 1;


/* -----------------------------------------------------------------------------
   TIER 2 — MONTHLY BREAKDOWNS

   These exist for one reason: exact user counts per dimension value. A monthly
   user count cannot be derived from daily rows, so it has to be asked for
   directly.

   The pattern below repeats for every monthly report. Only the dimension column
   changes. Add the rest from spec/reports.yaml following this shape.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.stg_channel_monthly` AS
SELECT
  _source,
  year_month,
  PARSE_DATE('%Y%m%d', CONCAT(year_month, '01'))           AS month_start_date,
  session_default_channel_group                            AS dimension_value,
  total_users, active_users, new_users,
  sessions, engaged_sessions, event_count, key_events,
  purchase_revenue, transactions,
  LAST_DAY(PARSE_DATE('%Y%m%d', CONCAT(year_month, '01')))
    <= CURRENT_DATE('__TIMEZONE__') - 2                    AS is_complete,
  CONCAT(year_month, '|', COALESCE(_source, ''),
         '|', COALESCE(session_default_channel_group, '')) AS report_pk
FROM `__LANDING__.ga4_channel_monthly`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, year_month, session_default_channel_group
  ORDER BY _synced_at DESC) = 1;


CREATE OR REPLACE VIEW `__MODEL__.stg_medium_monthly` AS
SELECT
  _source, year_month,
  PARSE_DATE('%Y%m%d', CONCAT(year_month, '01'))           AS month_start_date,
  session_medium                                           AS dimension_value,
  total_users, active_users, new_users,
  sessions, engaged_sessions, event_count, key_events,
  purchase_revenue, transactions,
  LAST_DAY(PARSE_DATE('%Y%m%d', CONCAT(year_month, '01')))
    <= CURRENT_DATE('__TIMEZONE__') - 2                    AS is_complete,
  CONCAT(year_month, '|', COALESCE(_source, ''),
         '|', COALESCE(session_medium, ''))                AS report_pk
FROM `__LANDING__.ga4_medium_monthly`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, year_month, session_medium
  ORDER BY _synced_at DESC) = 1;


CREATE OR REPLACE VIEW `__MODEL__.stg_device_monthly` AS
SELECT
  _source, year_month,
  PARSE_DATE('%Y%m%d', CONCAT(year_month, '01'))           AS month_start_date,
  device_category                                          AS dimension_value,
  total_users, active_users, new_users,
  sessions, engaged_sessions, event_count, key_events,
  purchase_revenue, transactions,
  LAST_DAY(PARSE_DATE('%Y%m%d', CONCAT(year_month, '01')))
    <= CURRENT_DATE('__TIMEZONE__') - 2                    AS is_complete,
  CONCAT(year_month, '|', COALESCE(_source, ''),
         '|', COALESCE(device_category, ''))               AS report_pk
FROM `__LANDING__.ga4_device_monthly`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, year_month, device_category
  ORDER BY _synced_at DESC) = 1;


CREATE OR REPLACE VIEW `__MODEL__.stg_country_monthly` AS
SELECT
  _source, year_month,
  PARSE_DATE('%Y%m%d', CONCAT(year_month, '01'))           AS month_start_date,
  country                                                  AS dimension_value,
  total_users, active_users, new_users,
  sessions, engaged_sessions, event_count, key_events,
  purchase_revenue, transactions,
  LAST_DAY(PARSE_DATE('%Y%m%d', CONCAT(year_month, '01')))
    <= CURRENT_DATE('__TIMEZONE__') - 2                    AS is_complete,
  CONCAT(year_month, '|', COALESCE(_source, ''),
         '|', COALESCE(country, ''))                       AS report_pk
FROM `__LANDING__.ga4_country_monthly`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, year_month, country
  ORDER BY _synced_at DESC) = 1;


-- EVENT-SCOPED monthly. Event metrics only.
CREATE OR REPLACE VIEW `__MODEL__.stg_event_monthly` AS
SELECT
  _source, year_month,
  PARSE_DATE('%Y%m%d', CONCAT(year_month, '01'))           AS month_start_date,
  event_name                                               AS dimension_value,
  event_count, event_value, key_events,
  LAST_DAY(PARSE_DATE('%Y%m%d', CONCAT(year_month, '01')))
    <= CURRENT_DATE('__TIMEZONE__') - 2                    AS is_complete,
  CONCAT(year_month, '|', COALESCE(_source, ''),
         '|', COALESCE(event_name, ''))                    AS report_pk
FROM `__LANDING__.ga4_event_monthly`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, year_month, event_name
  ORDER BY _synced_at DESC) = 1;


/* -----------------------------------------------------------------------------
   TIER 3 — CROSS-TABS

   Read row by row, or filtered to one value of one axis. Never summed across
   either axis while carrying user metrics.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW `__MODEL__.stg_country_by_channel_monthly` AS
SELECT
  _source, year_month,
  PARSE_DATE('%Y%m%d', CONCAT(year_month, '01'))           AS month_start_date,
  country,
  session_default_channel_group,
  total_users, active_users, new_users,
  sessions, engaged_sessions, event_count, key_events,
  purchase_revenue, transactions,
  CONCAT(year_month, '|', COALESCE(_source, ''),
         '|', COALESCE(country, ''),
         '|', COALESCE(session_default_channel_group, '')) AS report_pk
FROM `__LANDING__.ga4_country_by_channel_monthly`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, year_month, country, session_default_channel_group
  ORDER BY _synced_at DESC) = 1;


-- The one cross-tab that IS fully additive in both directions, because both
-- metrics count events and every event has one name and one session medium.
-- Adding sessions or users here would destroy that property.
CREATE OR REPLACE VIEW `__MODEL__.stg_event_by_medium_monthly` AS
SELECT
  _source, year_month,
  PARSE_DATE('%Y%m%d', CONCAT(year_month, '01'))           AS month_start_date,
  session_medium,
  event_name,
  event_count, key_events,
  CONCAT(year_month, '|', COALESCE(_source, ''),
         '|', COALESCE(session_medium, ''),
         '|', COALESCE(event_name, ''))                    AS report_pk
FROM `__LANDING__.ga4_event_by_medium_monthly`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _source, year_month, session_medium, event_name
  ORDER BY _synced_at DESC) = 1;
