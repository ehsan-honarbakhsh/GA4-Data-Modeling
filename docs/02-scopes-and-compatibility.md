# Scopes and compatibility

Almost everything that goes wrong with a GA4 table goes wrong for one of two reasons. Either a
dimension and a metric were put together at incompatible scopes, or a limit was hit quietly. This
page covers both.

The rule from [docs/01](01-why-ga4-numbers-differ.md), restated:

> **A metric adds up across a dimension only if each thing being counted belongs to exactly one
> value of that dimension.**

---

## 1. The four scopes

GA4 counts four kinds of thing, and they nest inside each other:

```
user
 └── session
      └── event
           └── item        (only on ecommerce events)
```

A **dimension** belongs to the level where its value is fixed. Channel is fixed for a session.
Page path changes with every event. Age bracket is fixed for a person.

A **metric** counts things at one level. Sessions counts sessions. Event count counts events.

Whether a pair is safe depends on which way you cross the hierarchy.

**Safe: the dimension sits at or above the metric's level.** An event happens inside exactly one
session, so an event metric split by a session dimension is exact.

**Unsafe: the dimension sits below.** The thing being counted touches many values, and GA4 counts
it under each one. A session with eight different events shows up under all eight event names.

| Metric counts | User dimension | Session dimension | Event dimension | Item dimension |
|---|---|---|---|---|
| **users** | exact | overcounts | overcounts badly | API refuses |
| **sessions** | mostly — see §4.2 | exact | overcounts badly | API refuses |
| **events** | exact | exact | exact | API refuses |
| **items** | API refuses | API refuses | API refuses | exact |

Two things stand out. Event metrics are safe against everything above them, which makes them the
most flexible thing to put in a report. And item scope isn't really part of the same hierarchy —
the API won't mix it with anything else at all.

> **The API mostly won't stop you.** Only the item-scope combinations get rejected. Every other
> unsafe pairing returns a perfectly normal response full of numbers that are wrong as soon as
> you add them up. No warning, no flag, no null. This is the most important sentence in this
> repository.

---

## 2. Dimensions by scope

### User-scoped

Fixed for the life of the person. Every session and event they ever generate carries the same
value.

`firstUserSource`, `firstUserMedium`, `firstUserSourceMedium`, `firstUserCampaignName`,
`firstUserDefaultChannelGroup`, `firstUserGoogleAdsAdGroupName`, `userAgeBracket`, `userGender`,
`newVsReturning`, `signedInWithUserId`, `audienceName`, `customUser:<name>`

One catch: a person can belong to several audiences at once, so `audienceName` behaves like a
lower-scoped dimension in practice. Don't sum users across it.

### Session-scoped

Set when the session starts, carried by every event in it.

`sessionSource`, `sessionMedium`, `sessionSourceMedium`, `sessionCampaignName`,
`sessionDefaultChannelGroup`, `sessionCustomChannelGroup:<id>`, `sessionGoogleAdsAdGroupName`,
`sessionManualAdContent`, `landingPage`, `landingPagePlusQueryString`

### Event-scoped

Changes from event to event inside a single session. This is the scope that breaks session and
user metrics.

`eventName`, `pagePath`, `pagePathPlusQueryString`, `pageTitle`, `pageLocation`, `hostName`,
`unifiedPagePathScreen`, `contentGroup`, `linkUrl`, `linkText`, `fileName`, `fileExtension`,
`method`, `percentScrolled`, `searchTerm`, `videoTitle`, `customEvent:<name>`

Note that custom dimensions come in two flavours. `customUser:<name>` is user-scoped and
`customEvent:<name>` is event-scoped. If you register a segment dimension at event scope — a very
common choice — it behaves like page path, not like channel. See §4.3.

### Item-scoped

Only on ecommerce events, and only combinable with item metrics.

`itemId`, `itemName`, `itemBrand`, `itemCategory` through `itemCategory5`, `itemVariant`,
`itemListName`, `itemPromotionName`, `itemAffiliation`

### Environment dimensions — the honest category

`country`, `region`, `city`, `continent`, `deviceCategory`, `browser`, `operatingSystem`,
`operatingSystemVersion`, `platform`, `screenResolution`, `mobileDeviceModel`, `language`

These get described everywhere as session attributes, and the GA4 interface reports them next to
session metrics. **They're actually resolved on every event.** Location comes from the IP address,
which changes when someone walks out of wifi range onto mobile data. Device and browser strings
are read again on every hit. So one session can genuinely hold two values.

In practice they behave *almost* like session dimensions, and the error is small enough that most
people never notice — which is exactly why it's worth writing down. Measured on one property:

| Dimension | Session overcount when summed |
|---|---|
| `country`, `region` | about 5% |
| `city` | about 7% |
| `deviceCategory`, `browser`, `operatingSystem` | under 1% |
| `language` | under 1% |

Treat them as session-scoped when designing, and as event-scoped when reconciling. If a number has
to tie out exactly, don't get it from a geography table.

### Time is an event-scoped dimension

`date`, `dateHour`, `hour`, `isoYearIsoWeek`, `yearMonth`, `yearWeek`

This one surprises people, and it explains two of the most common GA4 complaints. Time buckets
are assigned per *event*, by timestamp. So:

- A session running from 23:50 to 00:10 has events in two days and counts as a session in both.
  Summing daily sessions across a month comes out above the monthly figure — measured at about
  **+1.5%** on one property.
- Somebody who visits on the 3rd, the 11th and the 27th is an active user on all three days.
  Summing daily users across a month is meaningless — measured at about **1.14×** the true
  monthly number.

Nothing is broken and there's no fix. Ask for the grain you intend to report. This is why the
reference design has separate daily and monthly tables instead of one daily table that gets
rolled up.

---

## 3. Metrics by scope

| Scope | Metrics |
|---|---|
| **User** | `totalUsers`, `activeUsers`, `newUsers`, `totalPurchasers`, `firstTimePurchasers` |
| **Session** | `sessions`, `engagedSessions`, `engagementRate`, `bounceRate`, `sessionsPerUser`, `averageSessionDuration`, `transactions`, `purchaseRevenue`, `totalRevenue`, `ecommercePurchases`, `purchaserRate`, `averagePurchaseRevenue`, `cartToViewRate` |
| **Event** | `eventCount`, `eventValue`, `eventCountPerUser`, `keyEvents`, `screenPageViews`, `userEngagementDuration` |
| **Item** | `itemsViewed`, `itemsAddedToCart`, `itemsPurchased`, `itemRevenue`, `itemViewEvents`, `itemsClickedInList` |

### Ratios never add up, across anything

`engagementRate`, `bounceRate`, `purchaserRate`, `cartToViewRate`, `eventCountPerUser`,
`sessionsPerUser`, `averageSessionDuration`, `averagePurchaseRevenue`.

Each is a division GA4 performed for that exact row. Averaging them across rows is wrong. Summing
them is nonsense.

If you need one at a rolled-up level, carry the top and bottom of the fraction as separate columns
and divide after you aggregate. Engagement rate, for instance, is engaged sessions over sessions —
carry both and compute it yourself. Where the components aren't separately available, request the
ratio at the exact grain you plan to publish it.

---

## 4. Where each scope bites

### 4.1 Item scope is a hard wall

The API **refuses** item dimensions alongside user or session metrics. That's an error, not a
wrong number.

So a whole class of question has no answer in pre-aggregated GA4 data:

- How many people bought product X?
- What share of sessions viewed category Y?
- What's the conversion rate for brand Z?

Item reports carry item metrics only. Use `itemsPurchased` as your volume measure.

Also: `itemRevenue` **leaves out shipping and tax**, so it will never equal `purchaseRevenue`.
Don't build a reconciliation between them and don't let anyone else try.

The real answer to those three questions is the BigQuery event export, which is a different
project.

### 4.2 First-user dimensions can't carry session metrics honestly

The API accepts `sessions` next to `firstUserCampaignName`, and on paper it looks fine — a session
belongs to one person, and a person has one first campaign. Measured, it came out about **3%**
high.

The cause is identity stitching. When GA4 merges someone's activity across devices, or re-resolves
their first-touch record, their first-campaign value can change inside your reporting window, and
their sessions get attributed under both values. GA4's own User acquisition report has no Sessions
column for exactly this reason.

**Use `newUsers` as the headline metric on any `firstUser*` report.** Somebody is new precisely
once, and at that moment they have precisely one first campaign.

### 4.3 Event-scoped dimensions are where session metrics go to die

This is the biggest error in the whole model.

Ask for `sessions` alongside `eventName` and each row tells you how many sessions contained that
event. That's a real, useful number. Add the rows up and you've counted every session once for
each different event it contained.

Measured on one property: summing sessions across event names gave **5.3×** the true session
count. Across page paths, about **2.5×**.

The same applies to any custom dimension registered at event scope. A segment dimension used to
split a property will spread each session across every value that appeared during it — measured
at **+13.75%** on a property where the value was near-constant per visit. Near-constant isn't
constant.

**Never put a session or user metric on an event-scoped report.** Carry `eventCount` and
`keyEvents` and stop there. That's a rule, not a preference.

---

## 5. How to design a report

1. **Write down the question.** "Transactions by channel by month," not "a channel table."
2. **Find the scope of the answer.** Transactions are session-scoped.
3. **Pick dimensions at or above that scope.** `sessionDefaultChannelGroup` is session-scoped.
   `yearMonth` is technically event-scoped, which is fine here — you're asking for that grain,
   not summing across it.
4. **Throw out anything below it.** No event names, no page paths, no item brands.
5. **Check it with the API first.** The `checkCompatibility` method takes your proposed dimensions
   and metrics and tells you which combinations it will accept. It catches the hard refusals. It
   will *not* warn you about silent overcounting — that part is still on you.
6. **Estimate cardinality.** See §6.
7. **Write down what the table must never be used for**, in the model file, right next to the SQL.
   The person who misuses it in eighteen months will not have read this page.

### Two reports that look identical

**Safe, and unusually so.** Dimensions `sessionMedium` + `eventName`, metrics `eventCount` +
`keyEvents`. Every event has one name and sits in one session, which has one medium, so each
event falls in exactly one cell. Roll up across medium, across event name, or both — all exact.
Cross-tabs this well-behaved are rare, so it's a good table to have.

That safety comes entirely from the *metric* list. Add `sessions` and you've built a 5.3×
overcount. Add `totalUsers` and it's worse. There's room for eight more metrics and only one of
them (`eventValue`) is safe to spend.

**Unsafe, and indistinguishable at a glance.** Dimensions `sessionMedium` + `eventName`, metrics
`sessions` + `totalUsers`. Same dimensions. Valid response. Every row individually correct. Every
total wrong.

---

## 6. Cross-tabs

Because GA4 counts fresh for each request, margins can't be recombined into joints. A channel
table and a device table can't produce channel-by-device, no matter how exact each one is.

So every cross-tab is a deliberate build with a cardinality cost. And once built, a cross-tab is
**read row by row, or filtered to one value of one axis**. If it carries user metrics, never sum
across either axis.

This is also why "just give me everything and I'll slice it in the BI tool" doesn't work with GA4.
The slice has to exist when the request is made.

---

## 7. Limits

### Request shape

| Limit | Value |
|---|---|
| Dimensions per request | 9 |
| Metrics per request | 10 |
| Rows per response | 250,000 (paginated) |

The metric cap bites more often than the dimension cap. A totals report carrying a full engagement
set has no room left for transactions, which forces a second date-only report joined one-to-one.
Two reports at identical grain join safely — that's the standard escape hatch.

### Cardinality and `(other)`

Past roughly **50,000 unique dimension combinations** in a day, GA4 stops tracking individual
values and collapses the remainder into one row literally named `(other)`.

That row is real data, it just isn't attributable. It shows up without warning, it isn't an error,
and it quietly makes a long-tail report incomplete for exactly the values a long-tail report
exists to show.

Dimensions multiply, which is what catches people out. A landing-page report at 12,000 values a
month is comfortable on its own. Add a channel dimension and a segment dimension and it isn't.
Check cardinality after *every* dimension you add, not once at the start.

```sql
-- Run this against any report before you commit to it
SELECT
  period,
  COUNT(*)                                        AS rows_returned,
  COUNTIF(dimension_value = '(other)')            AS other_rows,
  SAFE_DIVIDE(
    SUM(IF(dimension_value = '(other)', metric_value, 0)),
    SUM(metric_value)
  )                                               AS other_share
FROM your_report_table
GROUP BY period
ORDER BY period DESC;
```

Anything above zero means the table is no longer complete. Fix it by reducing cardinality — drop
query strings, use a coarser dimension, split the report — rather than filtering `(other)` out.

### `(not set)` is not `(other)`

Two different problems, often flattened into the same NULL by ingestion tools. Separate them
before they reach a model:

- **`(not set)`** — there was no value. A tagging gap, or a visit that couldn't be attributed.
- **`(other)`** — there was a value, but cardinality collapsed it.

The first is a tracking problem you can fix. The second is a design problem you fix by asking for
less. One bucket hides both.

### Thresholding

With Google Signals switched on, GA4 **removes rows** whose user counts are low enough that
someone might be identifiable. Demographics and interests are the usual casualties.

Removed rows are gone, not zeroed and not flagged in the response. So a demographics table won't
sum to your property total and **must never be used as a denominator**.

Check rather than assume. A common mistake is concluding "no thresholding here" because the table
is full of rows with tiny user counts — that reasoning doesn't hold, because thresholding deletes
rows rather than raising them to a floor. Look at whether Signals is enabled and whether your
ingestion surfaces a thresholding warning.

### Sampling

Standard reports and the Data API aren't sampled at ordinary volumes. Sampling shows up in
Explorations above roughly 10 million events for the range requested. If your table disagrees with
someone's Exploration, this is a likely cause, and the API side is the one to trust.

### Restatement

Attribution and key-event data keep changing after the fact, usually for several days and longer
with data-driven attribution. So your ingestion needs a rollback window that re-reads recent
periods, and your model needs a rule that keeps the newest version of each row. The reference
staging layer in [sql/](../sql/) does this with `QUALIFY ROW_NUMBER()`.

`keyEvents` arrives as a **decimal**, not a whole number, because data-driven attribution splits
credit across touchpoints. Sum first, round last. Rounding each row and then adding won't tie back
to your totals.

Refund-bearing metrics — `transactions`, `totalRevenue` — can restate *downward*. That's expected,
not a fault. Don't put an alert on it.

### Quotas

Property-level token quotas apply hourly and daily, and cost scales with how complex a request is,
not just how many you make. Many narrow reports tend to be cheaper and far easier to debug than a
few wide ones, which happens to match the design advice above.

---

## 8. The rules, collected

1. **One scope per report.** Mixing scopes is where the errors live. Exceptions should be
   deliberate, documented and rare.
2. **Never put session or user metrics on an event-scoped or item-scoped report.**
3. **Never put user metrics on a report you intend to sum across anything.**
4. **Ask for the grain you'll publish.** Don't roll a daily table up to a month.
5. **Cross-tabs are read row by row.** If it carries user metrics, filter to one value of one axis.
6. **Ratios are carried, not computed** — or computed from separately carried parts, after
   aggregating.
7. **Check cardinality after each dimension you add.** Treat any `(other)` row as a design failure,
   not something to filter away.
8. **Put the "never use this for" note in the model file.** Documentation that lives somewhere
   else doesn't survive contact with a deadline.

---

**Next:** [The report catalogue](03-report-catalogue.md) — the actual set of tables, and what each
one is for.
