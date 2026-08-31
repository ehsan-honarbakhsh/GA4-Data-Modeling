# The report catalogue

A working set of GA4 reports, organised by what each one is for. Every table here follows the
rules in [docs/02](02-scopes-and-compatibility.md) , nothing mixes scopes, and nothing carries a
metric it can't support.

The machine-readable version is [spec/reports.yaml](../spec/reports.yaml). Use that to generate
your ingestion config rather than retyping any of this.

---

## The three tiers

The catalogue splits into three groups that do different jobs.

**Tier 0 — totals.** One row per period, no breakdown. Because they have no dimensions, they have
no additivity problems at all , which makes them the only place a correct *total* comes from. See
[the section below](#the-totals-tables-are-the-only-source-of-a-total).

**Tier 1 — daily breakdowns.** One dimension set, daily grain. These drive trend charts. Session
and event metrics are reliable here. User metrics are per-day only and must never be summed.

**Tier 2 — monthly breakdowns.** One dimension, monthly grain. These exist for one reason: **exact
user counts per dimension value.** A monthly user count can't be derived from daily rows, so if
anyone needs "users by channel last month" as a real number, it has to be its own report.

The split looks redundant until someone asks for monthly users by channel and you realise there's
no way to compute it from the daily table.

---

## Tier 0 — totals

| Table | Dimension | Grain |
|---|---|---|
| `ga4_totals_daily` | `date` | daily |
| `ga4_totals_weekly` | `isoYearIsoWeek` | weekly |
| `ga4_totals_monthly` | `yearMonth` | monthly |

Same ten metrics on each: `totalUsers`, `activeUsers`, `newUsers`, `sessions`, `engagedSessions`,
`screenPageViews`, `eventCount`, `keyEvents`, `purchaseRevenue`, `userEngagementDuration`.

That's the ten-metric cap exactly, which is why transactions can't go in. If you need transaction
counts reconciled, add a second date-only report (`ga4_ecommerce_totals_daily`) carrying
`transactions`, `totalRevenue` and `totalPurchasers`. Two date-only tables join one-to-one safely.

> **Why ISO weeks and not `yearWeek`.** `yearWeek` starts weeks on Sunday and forces January 1st
> into week 01, so weeks 01 and 53 can be anywhere from one to seven days long. A partial week
> looks like a cliff on a week-over-week chart. ISO weeks are always exactly seven days, Monday to
> Sunday.
>
> The catch: the ISO *year* isn't the calendar year at the boundaries. December 28th 2026 falls in
> ISO week `202701`. Never take a calendar year from the first four characters. In BigQuery,
> rebuild the key with `FORMAT_DATE('%G%V', date)` and get the week's Monday with
> `DATE_TRUNC(date, ISOWEEK)`.

---

## The totals tables are the only source of a total

This is the rule that saves the most arguments, so it's worth being exact about what it does and
doesn't claim.

**Every table here matches the GA4 interface, row for row.** Query `ga4_channel_monthly` for last
month and you'll get the same numbers as GA4's Traffic acquisition report, channel by channel.
That's true of the geography tables, the device tables, all of them. Each row is a figure GA4
computed for that exact question, so each row is exactly what GA4 would show you.

**But only the totals tables give you a correct total.** Everywhere else, getting to a single
headline number means summing rows , and summing is precisely where the additivity rule bites.

So the practical rule:

> **Any number without a breakdown comes from a totals table. Any number with a breakdown comes
> from a breakdown table, read row by row.**

### Why there's no way around it

For sessions and revenue, summing a well-behaved breakdown gets close. Channel is session-scoped,
so summing sessions across channels lands within a percent or so of the real total. Close, and
tempting, and it will still drift , because the moment somebody points that query at the geography
table or the page table instead, the answer moves by 5% or 250% and nothing in the SQL looks
different.

For **users** there's no approximation at all. A person visits through two channels, on three
devices, across eight days. GA4 counted them once in each of those rows because each row was a
separate question. Nothing in a pre-aggregated table records which rows are the same person, so
no amount of SQL can put them back together. The only correct monthly user count is one you asked
GA4 for directly — which is what `ga4_totals_monthly` is.

This is also why the weekly and daily totals tables exist as separate reports rather than as
rollups. A weekly user count can't be derived from daily rows either. If you want users by week,
you have to ask for users by week.

### What each totals table is for

| Table | Use it for |
|---|---|
| `ga4_totals_monthly` | Monthly headline figures. The number that goes on a board pack. |
| `ga4_totals_weekly` | Week-over-week trends where the user count has to be right. |
| `ga4_totals_daily` | Daily trend lines, and the denominator for daily reconciliation. |

`ga4_totals_monthly` is the one people reach for most, because monthly is the grain businesses
report on and because it's the strictest test of whether the pipeline is right. If it reproduces
GA4 exactly for a closed month, the ingestion, the deduplication and the timezone handling are all
working. That's why the acceptance test in
[docs/04](04-reconciliation.md#5-the-acceptance-test) is built around it.

### Putting it on a dashboard

Give the scorecard tiles and the breakdown charts **separate data sources**: tiles read
`totals_by_period`, charts read the breakdown marts. One source doing both is how a summed
breakdown ends up in a scorecard.

Expect the two to disagree slightly, and expect somebody to notice. The tile says 64,945 sessions;
adding up the channel chart gives 65,885. Both are correct — see
[docs/01](01-why-ga4-numbers-differ.md#the-same-metric-can-have-two-right-answers). Deciding in
advance which one is the published number is a governance choice, and making it early is cheaper
than making it in a meeting.

And never put a column called `users` on a chart that can be rolled up. Somebody will roll it up.

---

## Tier 1 — daily breakdowns

| Table | Dimensions | Metrics |
|---|---|---|
| `ga4_traffic_acquisition_daily` | date, sessionSource, sessionMedium, sessionCampaignName, sessionDefaultChannelGroup | sessions, engagedSessions, engagementRate, activeUsers, keyEvents, purchaseRevenue, transactions |
| `ga4_user_acquisition_daily` | date, firstUserSource, firstUserMedium, firstUserCampaignName, firstUserDefaultChannelGroup | newUsers, totalUsers, engagedSessions, keyEvents, purchaseRevenue |
| `ga4_landing_pages_daily` | date, landingPagePlusQueryString | sessions, engagedSessions, activeUsers, keyEvents, purchaseRevenue, transactions |
| `ga4_pages_daily` | date, hostName, pagePath | screenPageViews, eventCount, userEngagementDuration, bounceRate |
| `ga4_events_daily` | date, eventName | eventCount, eventValue, keyEvents |
| `ga4_geo_daily` | date, country, region | sessions, engagedSessions, activeUsers, newUsers, transactions |
| `ga4_geo_city_daily` | date, city | sessions, activeUsers, transactions |
| `ga4_tech_daily` | date, deviceCategory, browser, operatingSystem | sessions, engagedSessions, activeUsers, transactions |
| `ga4_ecommerce_channel_daily` | date, sessionDefaultChannelGroup | transactions, purchaseRevenue, averagePurchaseRevenue, purchaserRate, cartToViewRate |
| `ga4_ecommerce_items_daily` | date, itemId, itemName, itemBrand, itemCategory | itemsViewed, itemsAddedToCart, itemsPurchased, itemRevenue |

Two of these need care:

**`ga4_pages_daily`** carries no session or user metrics. Page path is event-scoped, so sessions
would come out around 2.5× too high when summed. If someone asks for "sessions by page", they
almost always mean landing page — point them at `ga4_landing_pages_daily`, which is session-scoped
and correct.

**`ga4_user_acquisition_daily`** carries `newUsers`, not `sessions`. See
[docs/02 §4.2](02-scopes-and-compatibility.md#42-first-user-dimensions-cant-carry-session-metrics-honestly).

---

## Tier 2 — monthly breakdowns

All of these are `yearMonth` plus exactly one dimension, at monthly grain.

### Session-scoped

These share one metric set: `totalUsers`, `activeUsers`, `newUsers`, `sessions`,
`engagedSessions`, `eventCount`, `keyEvents`, `purchaseRevenue`, `transactions`.

| Table | Dimension | Typical values/month |
|---|---|---|
| `ga4_channel_monthly` | `sessionDefaultChannelGroup` | ~12 |
| `ga4_medium_monthly` | `sessionMedium` | ~25 |
| `ga4_source_monthly` | `sessionSource` | ~200 |
| `ga4_campaign_monthly` | `firstUserCampaignName` | ~100 |
| `ga4_landing_pages_monthly` | `landingPagePlusQueryString` | 10,000+ ⚠ |
| `ga4_device_monthly` | `deviceCategory` | 4 |
| `ga4_os_monthly` | `operatingSystem` | ~8 |
| `ga4_browser_monthly` | `browser` | ~15 |
| `ga4_language_monthly` | `language` | ~50 |
| `ga4_country_monthly` | `country` | ~150 |
| `ga4_region_monthly` | `region` | ~700 |
| `ga4_city_monthly` | `city` | 5,000+ ⚠ |

The two marked ⚠ are the ones to watch as you add dimensions. See
[docs/02 §7](02-scopes-and-compatibility.md#cardinality-and-other).

`ga4_campaign_monthly` uses a first-user dimension, so `newUsers` is its honest headline. The
session metrics are there for completeness and carry the ~3% inflation described in docs/02.

### Demographics

| Table | Dimension | Metrics |
|---|---|---|
| `ga4_age_monthly` | `userAgeBracket` | the session-scoped set |
| `ga4_gender_monthly` | `userGender` | the session-scoped set |

Build these as **separate reports, never combined**. Age crossed with gender multiplies the number
of small groups, and small groups are exactly what thresholding removes.

Both depend on Google Signals, and both are thresholded. They won't sum to your property total and
can't be used as a denominator. Treat them as shape, not size: "our audience skews older" is a
fair reading, "we had 4,102 users aged 25–34" is not.

### Event and page scope

| Table | Dimension | Metrics |
|---|---|---|
| `ga4_event_monthly` | `eventName` | eventCount, eventValue, keyEvents |
| `ga4_pages_monthly` | `pagePath` | screenPageViews, eventCount, userEngagementDuration |

Event metrics only. No sessions, no users. This is the rule that most often gets argued with, and
the 5.3× figure in docs/02 is what the argument costs.

### Item scope

| Table | Dimension | Metrics |
|---|---|---|
| `ga4_item_name_monthly` | `itemName` | itemsViewed, itemsAddedToCart, itemsPurchased, itemRevenue |
| `ga4_item_category_monthly` | `itemCategory` | same |
| `ga4_item_brand_monthly` | `itemBrand` | same |

Item metrics only — the API refuses anything else. `itemRevenue` excludes shipping and tax.

> **`itemBrand` is not your brand.** If you also run a segment dimension for business units or
> sub-brands, these are two unrelated things one word apart in the same schema. `itemBrand` is the
> manufacturer on a product. Grouping one by the other produces a plausible-looking table of
> nonsense. Consider naming your segment column something that can't be confused with it.

---

## Cross-tabs

Built deliberately, because margins can't be recombined. Each is read row by row.

| Table | Dimensions | Notes |
|---|---|---|
| `ga4_country_by_channel_monthly` | yearMonth, country, sessionDefaultChannelGroup | session-scoped metrics; row-wise only |
| `ga4_landing_page_by_channel_monthly` | yearMonth, landingPage, sessionDefaultChannelGroup | watch cardinality; use plain `landingPage`, not the query-string version |
| `ga4_event_by_medium_monthly` | yearMonth, sessionMedium, eventName | eventCount + keyEvents only — **fully additive both ways** |

That last one is the exception worth knowing about. Because both metrics count events, and every
event sits in exactly one session with exactly one medium, you can roll it up across either axis
or both and stay exact. It's the only cross-tab in the catalogue that behaves like a normal
warehouse table — and only because of what was left out of it.

---

## Optional: a segment dimension

Many properties carry a custom dimension that splits the business , brand, region, business unit,
site section. Adding it to every report gives you per-segment reporting across the board.

Before you do, three things to know.

**It's usually event-scoped.** `customEvent:<name>` is set per event. Even when the value is
effectively constant for a whole visit, GA4 spreads sessions across every value seen — measured at
**+13.75%** on one property where the value looked stable. If you can register it as
`customUser:<name>` instead, session metrics behave properly.

**You lose your property-wide total.** Once the dimension is on your totals reports too, every
table is at (period, segment) grain and there's no unfiltered anchor left. Either keep the totals
reports unsegmented, or add segmented twins alongside them. Deciding this after the fact means
re-running your validation.

**It multiplies cardinality.** Every table's row count goes up by roughly the number of segments.
Check your landing-page and city reports first , they're closest to the ceiling.

If you add it, the segment column belongs in the deduplication key of every staging view. Leaving
it out silently keeps one segment per period and discards the rest, which looks like missing data
rather than a modelling bug. The reference SQL handles this; see
[docs/05 §2](05-operations.md#2-the-deduplication-key-is-load-bearing).

---

## What's deliberately missing

**Hourly.** Rarely worth the row count, and time-of-day questions are usually better answered in
the GA4 interface.

**Search terms and site search.** Add if you use them; they follow the event-scoped rules.

**Ad platform detail.** Google Ads dimensions belong in a separate design keyed to campaign
structure, not bolted onto this one.

**Anything item-plus-user.** Not possible. See docs/02 §4.1.

---

**Next:** [Reconciliation](04-reconciliation.md) — how to tell a broken pipeline from GA4's own
arithmetic.
