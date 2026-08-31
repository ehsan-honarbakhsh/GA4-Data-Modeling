# Why GA4 numbers differ

If you only read one page here, make it this one. Everything else in the repo follows from it.

---

## GA4 counts fresh, every time

A warehouse table sits still. You group it one way, then another, and the totals stay put,
because you're re-arranging rows that already exist.

GA4 doesn't work like that. When you ask the Data API for sessions by channel, GA4 walks the
event stream and counts sessions *while grouping by channel*. Ask for sessions by device, and it
walks the stream again and counts *while grouping by device*. Two separate counting runs, each
correct for the question asked.

This sounds like a small distinction. It has large consequences.

### You can't rebuild a cross-tab from two tables

You have exact channel numbers. You have exact device numbers. You cannot combine them into
channel-by-device.

Not because the data is missing, and not because the tool is limited. The joint distribution
simply isn't recoverable from the two margins. If 60% of sessions are mobile and 30% are organic
search, nothing tells you how many are both. That depends on how those two things overlap in real
visitor behaviour, and that information was never in either table.

If you need channel-by-device, you request a report with both dimensions. Every cross-tab is a
deliberate build.

### The same metric can have two right answers

Ask for sessions in July. Then ask for sessions per day in July and add up the days. The second
number is bigger.

Both are correct. A visit starting at 23:50 and ending at 00:10 is one session in the monthly
count, because GA4 counted sessions once over the whole month. In the daily count it has events
in two days, so it appears in both. On one property this gap was about 1.5%.

This is not an error to fix. It's two questions with two answers. The design consequence is that
scorecards and time-series charts should read from different tables, and nobody should ever roll
a daily table up to a month.

---

## The additivity rule

Here's the whole thing in one sentence:

> **A metric adds up across a dimension only if each thing being counted belongs to exactly one
> value of that dimension.**

Sessions and channel: every session has one channel, so sessions add up across channel. ✅

Sessions and page path: a session visits several pages, so GA4 counts it under each one.
Summing double-counts. ❌

Users and anything: a person can use two devices, arrive through three channels, and visit on
ten days. Users almost never add up. ❌

That's it. Every rule in [docs/02](02-scopes-and-compatibility.md) is this sentence applied to a
specific pair.

### What this means for users, specifically

User counts are the ones people get wrong most often, and they're also the ones executives care
about most.

You cannot sum users across days. You cannot sum users across channels, devices, countries, or
segments. You cannot get "users in the last 28 days" from a table of daily users. There is no
clever SQL that fixes this, because deduplicating people requires knowing which rows are the same
person — and a pre-aggregated table doesn't carry that.

The only correct way to get a user count for a period is to have asked GA4 for that exact period.
Which is why this design has separate daily, weekly and monthly tables rather than one table and
a date filter.

It also means the **totals tables are the only place a total comes from**. Every other table
matches GA4 row for row, but reaching a single headline number from one of them means summing, and
summing is what this whole page is about. See
[docs/03](03-report-catalogue.md#the-totals-tables-are-the-only-source-of-a-total).

---

## GA4's own interface doesn't add up either

Worth knowing before someone shows you a screenshot as proof your build is broken.

Open any GA4 report with a breakdown. Add up the rows. Compare to the total at the top. They
usually differ, and the percentage column often sums to slightly more than 100%.

The interface is doing exactly what the API does — computing the total separately from the rows.
It isn't a bug and it isn't going to be fixed. When your table disagrees with a GA4 screenshot,
the first question is always which number in the screenshot, not which line of your SQL.

---

## Things that quietly change your numbers

Four mechanisms remove or reshape data without telling you. Full detail in
[docs/02, section 7](02-scopes-and-compatibility.md#7-limits); the short version:

**Cardinality collapse.** Past roughly 50,000 unique dimension combinations in a day, GA4 stops
tracking individual values and dumps the rest into one row called `(other)`. Your long-tail
report quietly stops showing the long tail.

**Thresholding.** With Google Signals enabled, rows with few enough users to risk identifying
someone are removed entirely. Demographics tables are the usual victims. They won't sum to your
total, and they can't be used as a denominator.

**Restatement.** Attribution keeps changing for days after the fact. Yesterday's number is
provisional. Your pipeline needs to re-read recent days, and your model needs to keep the newest
version of each row.

**Sampling.** Not in the Data API at normal volumes, but yes in Explorations above about 10
million events. If a colleague's Exploration disagrees with your table, this is often why.

---

## The other GA4: the BigQuery event export

GA4 has a second way out: a raw export of individual events to BigQuery. It's a genuinely
different product and it solves different problems.

| | Data API (this repo) | BigQuery event export |
|---|---|---|
| What you get | Rows GA4 already counted | Individual events |
| Matches the GA4 interface | Yes, by construction | Only if you rebuild GA4's logic exactly |
| Sessions | GA4 defines them | You define them |
| Cardinality collapse | Yes | No |
| Thresholding | Yes | No |
| Cross-tabs | Only if requested | Any, any time |
| User-level joins to CRM | No | Yes |
| History | From when you start pulling | From when you enable it, never backfilled |

Use the export when you need cross-tabs you can't predict, user-level joins, or item questions
like "how many people bought product X". Accept that your numbers will differ from the interface,
and that reproducing GA4's session and attribution logic is a real project on its own.

Use the Data API — and this repo — when the numbers need to match what people see in GA4.

Many teams end up running both, for different audiences. That's a reasonable outcome, as long as
everyone knows which is which.

---

**Next:** [Scopes and compatibility](02-scopes-and-compatibility.md) — the rules for which
dimensions and metrics belong in the same table.
