# Section 8 — Gold layer and the star schema

Built in a second folder, `silver_to_gold`, inside the same pipeline, plus a
one-time notebook for the views and the calendar table.

## What gets built, and as what

| Gold object | Built as | From | Why |
|---|---|---|---|
| `fact_sales` | materialised TABLE (in the pipeline) | `transactions` ⨝ `opportunity` | a real join — compute once, store |
| `dim_customer` | VIEW (notebook) | `silver.account` | already clean — no need to copy |
| `dim_product` | VIEW (notebook) | `silver.product_catalog` | same |
| `dim_inventory` | VIEW (notebook) | `silver.inventory` | not in the star; used in dashboards |
| `dim_calendar` | generated TABLE (notebook) | a date sequence | no source; built once |

The gold layer is a **mix**: one materialised fact, three virtual dimensions,
one generated dimension. This is a legitimate and fairly mature pattern
(virtual dimensions over a clean silver), not a shortcut.

## fact_sales — the assembly

```
transactions  LEFT JOIN  opportunity
  ON transactions.opportunity_name = opportunity.name
```

- **Left join** keeps one row per transaction — the declared grain — and never
  drops a transaction that has no matching opportunity.
- The customer link is reached *through* opportunity: `transactions` has no
  `customer_id`, so `fact_sales.customer_id` is sourced from
  `opportunity.account_id`. Opportunity is the bridge.
- `date_key` is derived from the transaction timestamp so the fact joins to
  `dim_calendar`.

## Tables vs views in gold

- **Table** when the object is the result of real computation that should not be
  repeated on every read (the fact).
- **View** when the upstream (silver) is already clean and the gold object only
  renames, filters and presents (the dimensions). No data is copied and the view
  always reflects the latest silver.
- **Generated table** for the calendar: no source, static, built once.

Trade-off of a view: it recomputes on every query, and it cannot hold a
surrogate key or any gold-only column — which is exactly what Flag 2 below needs.

## The dimension view filters — these matter

```sql
-- dim_customer
CREATE OR REPLACE VIEW retail_q.retail_gold.dim_customer AS
SELECT id AS customer_id, customer_name, type AS customer_type, ...
FROM retail_q.retail_silver.account
WHERE is_deleted = false     -- drop soft-deleted Salesforce records
  AND is_active  = true;     -- keep only the current SCD2 version

-- dim_product
CREATE OR REPLACE VIEW retail_q.retail_gold.dim_product AS
SELECT ... FROM retail_q.retail_silver.product_catalog
WHERE is_active = true;
```

These two filters quietly fix the two gaps flagged in section 7:
- `is_deleted = false` removes soft-deleted accounts.
- `is_active = true` removes the SCD2 history duplicates that would otherwise
  double-count customers and products.

Good that they are here. But see Flag 2 — the `is_active = true` filter also has
a side effect.

## The DAG is now real

Running the pipeline, the lineage graph shows `fact_sales` depending on
`silver.transactions` and `silver.opportunity`, and the engine runs it only
after both complete. No ordering was specified — it was inferred from the table
references. This is the first point where the dependency graph has real edges.

Reminder: a new file created outside the included folder gets a skip icon.
Use "Include as pipeline source code" or drag it into the folder.

## Flag 1 — the bridge join can inflate revenue  (IMPORTANT)

The join key is `opportunity.name`, a text label, not an id. Salesforce does
**not** enforce unique opportunity names. If two opportunities share a name,
every transaction matching that name fans out into multiple fact rows, and
revenue double-counts.

A left join guarantees each transaction *survives*; it does **not** guarantee
each transaction matches at most one opportunity. Verify the relationship is
1-to-1 before trusting any total:

```sql
-- any transaction matching more than one opportunity?
SELECT t.opportunity_name, COUNT(*) AS opp_matches
FROM retail_q.retail_silver.transactions t
JOIN retail_q.retail_silver.opportunity o
  ON t.opportunity_name = o.name
GROUP BY t.opportunity_name
HAVING COUNT(*) > 1;

-- did the fact row count exceed the transaction count? (it never should)
SELECT
  (SELECT COUNT(*) FROM retail_q.retail_silver.transactions) AS txn_rows,
  (SELECT COUNT(*) FROM retail_q.retail_gold.fact_sales)     AS fact_rows;
```

If `fact_rows > txn_rows`, the join fanned out. The fix is to deduplicate
opportunity to one row per name before joining, or join on a real key.

## Flag 2 — SCD type 2 collapses to type 1 at gold  (CONCEPTUAL, important)

Bronze and silver went to real trouble to keep full history for `product_catalog`
and `account` (SCD type 2, `__START_AT` / `__END_AT`, `is_active`). But the gold
dimension views filter `is_active = true`, so gold only ever exposes the
**current** version of each product and customer.

Consequence: a sale from six months ago joins to **today's** product price and
category, not the values that were live when it sold. The historical versions
sit in silver and are never read.

This is not a bug — "current-value dimensions" are a common and valid choice.
But it means the SCD type 2 machinery is **latent, not realised**: the project
builds type 2 and consumes it as type 1.

Realising it would require:
- a **surrogate key** on the dimension (one per version, not per product), and
- the fact join resolving to the version whose `[__START_AT, __END_AT)` window
  contains the transaction date.

Natural keys (`product_id`) plus a current-only view can only ever be type 1.
This connects back to the natural-key observation from section 3.

Left as-is (in scope). Worth stating plainly in the summary and listing the
surrogate-key version as an extension.

## Calendar table

Generated with a date `sequence` exploded to one row per day, then `year`,
`quarter`, `month`, `month_name`, `week_number`, `day_name`, `is_weekend`
derived from each date. Range chosen to cover the data (≈2025–2028). Built once;
rows never change. Renamed to `dim_calendar` to match the convention.

A generated calendar is standard practice: it lets every date question
(year-over-year, quarter, weekday vs weekend) be a join rather than ad-hoc date
arithmetic in each query.
