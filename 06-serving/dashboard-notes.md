# Section 10 — Databricks Dashboard

A dashboard is the consumption layer. It reads the metric view and lets a
viewer see the numbers without writing SQL.

## Two ways to build

1. **Genie / AI** — describe the dashboard, it generates widgets. Fast start,
   needs fixing (see below).
2. **Manual** — add a dataset (the metric view), then add widgets and pick a
   measure + a dimension per widget. More control, no surprises.

Either way the metric view does the aggregation; the dashboard just picks
measure × dimension and renders it.

## Anatomy

| Part                   | What it is                                                           |
| ---------------------- | -------------------------------------------------------------------- |
| Dataset                | the data source behind the dashboard — here, the metric view         |
| Widget / visualization | one chart or number tile, = a measure sliced by a dimension          |
| SQL warehouse          | the compute that runs the queries; starts automatically on first use |
| Draft vs Published     | draft = editor view; Published = what viewers see. Must publish.     |

## The metric-view payoff, made concrete

"Revenue by payment mode" and "revenue by stage" are two widgets with no extra
SQL and no extra datasets — each is just `MEASURE(Total revenue)` grouped by a
different dimension, resolved at render time. Without the metric view, each
widget would need its own `GROUP BY` query or view. This is the single clearest
demonstration of why the semantic layer exists.

## The AI-generation gotcha

The assistant built the dashboard but every widget came up empty —
"select fields to visualize". A follow-up prompt ("all visualizations are empty,
no fields selected") made it populate them. Expect this: AI dashboard generation
often creates the widgets but fails to bind fields. Build the KPI row and one or
two charts by hand first so you understand the widget editor, then let AI fill
the rest.

## Cost note

Dashboards run on a **SQL warehouse**, which is compute = credits. It
auto-starts on first query and auto-stops after an idle timeout. Fine for this
project; just know a dashboard left open and refreshing is spending credits.

## THIS project's dashboard — matched to the actual data

`customer_id` and all opportunity-side columns are null (the transaction↔
opportunity join matched nothing).

### KPI row (Counter widgets — one measure, no dimension)

- Total revenue
- Transaction count
- Total quantity
- Average transaction value
- Unique products sold

### Charts (measure × dimension)

| Widget                   | Dimension       | Measure        | Type      |
| ------------------------ | --------------- | -------------- | --------- |
| Revenue over time        | Month           | Total revenue  | line      |
| Revenue by category      | Category        | Total revenue  | bar       |
| Revenue by brand         | Brand           | Total revenue  | bar       |
| Revenue by payment mode  | Payment mode    | Total revenue  | donut/bar |
| Units by product segment | Product segment | Total quantity | bar       |
| Revenue by sales channel | Sales channel   | Total revenue  | bar       |
| Revenue by store         | Store           | Total revenue  | bar       |
| Weekend vs weekday       | Is weekend      | Total revenue  | bar       |

### Do NOT build (all-null source columns)

- Revenue by customer / country / industry / customer type
- Unique customers (returns 0)
- Revenue by opportunity stage
- Average deal amount
