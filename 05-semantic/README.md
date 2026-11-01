# Section 9 — Semantic layer with Databricks Metric Views

## What a metric view is

A **metric view** is a Unity Catalog object that sits between the gold star
schema and every consumer. It defines, in one place:

- **dimensions** — the angles you slice by (year, category, brand, region).
  No aggregation; just columns, usually from the dimension tables.
- **measures** — the quantities (revenue, quantity, customer count), each
  carrying its own **aggregation rule** (SUM, COUNT, COUNT DISTINCT, a ratio).

The key idea: a measure defines **how to aggregate**; the query defines
**by what**. You never pre-build a "revenue by brand" view and a "revenue by
month" view. You define revenue once, and the query's `GROUP BY` chooses the
dimension at run time.

## It is YAML, not "ML"

The create statement is:

```sql
CREATE VIEW retail_q.retail_semantic.retail_metrics
WITH METRICS
LANGUAGE YAML
AS $$
  version: 0.1
  source: retail_q.retail_gold.fact_sales
  joins: ...
  dimensions: ...
  measures: ...
$$;
```

"WITH METRICS LANGUAGE YAML" is what the tutorial mis-says as
"matrix language ML". The definition language is **YAML**.

Reference definition: `retail_metrics.yaml` in this folder.

## How you query it

```sql
SELECT
    Category,
    MEASURE(`Total revenue`)
FROM retail_q.retail_semantic.retail_metrics
GROUP BY Category;
```

- `MEASURE(...)` invokes a defined measure and applies its stored aggregation.
- The `GROUP BY` picks the dimension. Change it to `Year` and the same measure
  re-aggregates by year — no new object needed.

## Why it matters

| Governs     | Mechanism                            |
| ----------- | ------------------------------------ |
| Access      | Unity Catalog (who can read a table) |
| **Meaning** | **Metric view (what "revenue" is)**  |

Without a semantic layer, every dashboard redefines "revenue" in its own SQL,
and three dashboards quietly disagree. The metric view makes one definition
that SQL, dashboards, Genie and alerts all inherit. This is governance of
_meaning_, the complement to Unity Catalog's governance of _access_.

## Synonyms — what makes Genie work (section 11)

Each measure and dimension can list synonyms: the words real users type. So
"distinct customers", "number of customers" and "customer count" all resolve to
`Unique customers`. Genie (natural-language querying) depends on these to map
plain English to the correct governed metric. Spend time on them — Genie's
answer quality is downstream of this.

Each field also has a display name (what the user sees), a technical name, a
comment, and a format (number, currency, percent).

## What the AI got right, and what to CHECK

The assistant generated the whole YAML from the table schemas and sample data.
It produced sensible dimensions and measures, but **it cannot know table grain**,
so every measure expression must be reviewed. Three checks:

1. **Revenue must be `SUM(quantity * selling_price)`**, not `SUM(selling_price)`.
   A unit price summed across rows is meaningless. Net revenue subtracts
   discount.

2. **No measure may `SUM(amount)`.** `amount` is the opportunity's deal value,
   carried onto the transaction-grain fact and repeated across a deal's
   transactions. Summing it double-counts. If the AI created a
   `total_amount = SUM(amount)` measure, delete it. (This is section-8 Flag B
   reaching the semantic layer.)

3. **Confirm the customer join exists.** The AI first built the view WITHOUT
   dim_customer, because `customer_id` was still missing from `fact_sales` at
   that point. The tutor then went back, added `account_id AS customer_id` to
   the fact, re-ran the pipeline, and had the AI add the join. Verify
   `customer_id` is present in the fact and the customer join is in the YAML.
