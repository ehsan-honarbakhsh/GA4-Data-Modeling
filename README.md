# GA4 Data Modeling

**GA4 Data API table design for BigQuery : scope rules, additivity, and models whose numbers match the GA4 UI.**

---

## The problem this repo solves

You build a warehouse table from GA4, put it on a dashboard, and someone compares it to the GA4
interface. The numbers don't match. You check your SQL. The SQL is fine.

The numbers don't match because GA4 doesn't work the way a database works. It doesn't store a
table you can slice however you like. It counts things fresh, on the server, for the exact
question you asked. Ask a slightly different question and you get a legitimately different
answer.

This repo is the shortcut: the rules, the table designs that follow from
them, and the tests that tell you whether your build is right.

## What's here

| | |
|---|---|
| **[docs/](docs/)** | The reasoning. Why GA4 behaves this way, and what follows from it. |
| **[spec/](spec/)** | The report catalogue as a machine-readable file, plus the ingestion boundary. |
| **[sql/](sql/)** | Reference BigQuery models — staging, marts, and tests. |
| **[baselines/](baselines/)** | Queries that measure these effects on *your* property. |

## The one rule to take away

Every table in this design matches the GA4 interface row for row. But **only the no-breakdown
totals tables give you a correct total** everywhere else, reaching a headline number means
summing rows, and summing is where GA4 stops behaving like a database.

For user counts there isn't even an approximation. A monthly user figure has to be one you asked
GA4 for directly.

[The full explanation](docs/03-report-catalogue.md#the-totals-tables-are-the-only-source-of-a-total).

## Start here

1. **[Why GA4 numbers differ](docs/01-why-ga4-numbers-differ.md)** the one idea everything else
   rests on.
2. **[Scopes and compatibility](docs/02-scopes-and-compatibility.md)** which dimensions and
   metrics can go in the same table, and what breaks when they can't.
3. **[The report catalogue](docs/03-report-catalogue.md)** the actual set of tables, what each
   one answers, and what it must never be used for.

## What this repo is not

**It's not a pipeline.** There's no code here that talks to the GA4 API. That's deliberate.
Whichever tool you use to move data , a managed connector, a scheduled script, whatever comes
next , the modelling problem is identical. Putting an ingestion layer in the middle would tie
this to a vendor and hide the part that actually matters.

Instead, [spec/source-contract.md](spec/source-contract.md) defines exactly what the SQL expects
to find. Meet that contract with any tool and everything downstream works.

**It's not about the BigQuery event export.** The GA4 Data API and the raw event export are two
different products with two different sets of problems. This repo covers the Data API: you
receive rows GA4 has already counted, which is why they match the interface, and also why they
behave in ways that surprise people. With the raw export you count sessions yourself and none of
this applies. See
[docs/01](docs/01-why-ga4-numbers-differ.md#the-other-ga4-the-bigquery-event-export) for the
comparison.

**The measured numbers aren't constants.** Figures like "summing sessions across event names
gives 5.3× the real total" came from one real property. Yours will differ. They're here to show
the size of the problem, not to be quoted. [baselines/](baselines/) has the queries to measure
your own.

## Conventions

Table names are generic and prefixed `ga4_`, with the grain in the name:
`ga4_channel_monthly`, `ga4_traffic_acquisition_daily`. Rename to fit your warehouse , nothing
depends on the names except the SQL in this repo.

SQL is BigQuery standard SQL. It uses `QUALIFY`, `DATE_TRUNC` and `FORMAT_DATE`, so it isn't
portable as written, but the logic is plain enough to translate.

## Licence

MIT. See [LICENSE](LICENSE).
