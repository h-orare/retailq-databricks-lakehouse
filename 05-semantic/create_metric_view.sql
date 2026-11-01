-- =========================================================
-- RetailQ — metric view, matched to THIS fact_sales
--
-- Built for the fact as it actually stands:
--   transaction_id, opportunity_name, product_id, store_id, quantity,
--   selling_price, discount_amount, transaction_timestamp, transaction_date,
--   payment_mode, sales_channel, name, stage_name, owner_id, amount, customer_id
--
-- The opportunity LEFT JOIN matched no rows (the transactions CSV and the
-- Developer-Edition sample opportunities share no opportunity_name), so every
-- opportunity-side column is NULL: customer_id, name, stage_name, owner_id,
-- amount. Those are therefore EXCLUDED here — a dimension of all-nulls is noise,
-- and COUNT(DISTINCT customer_id) would just return 0.
--
-- What IS usable: the transaction-grain columns, plus the product and calendar
-- joins (product_id and transaction_date are populated).
-- =========================================================

CREATE SCHEMA IF NOT EXISTS retail_q.retail_semantic;

-- COMMAND ----------

CREATE OR REPLACE VIEW retail_q.retail_semantic.retail_metrics
WITH METRICS
LANGUAGE YAML
AS $$
version: 0.1

source: retail_q.retail_gold.fact_sales

joins:
  - name: product
    source: retail_q.retail_gold.dim_product
    on: source.product_id = product.product_id

  - name: calendar
    source: retail_q.retail_gold.dim_calendar
    on: source.transaction_date = calendar.date

dimensions:
  # --- time (from dim_calendar) ---
  - name: Year
    expr: calendar.year
  - name: Quarter
    expr: calendar.year_quarter
  - name: Month
    expr: calendar.year_month
  - name: Month name
    expr: calendar.month_name
  - name: Day of week
    expr: calendar.day_of_week_name
  - name: Is weekend
    expr: calendar.is_weekend

  # --- product (from dim_product) ---
  - name: Category
    expr: product.category
  - name: Subcategory
    expr: product.subcategory
  - name: Brand
    expr: product.brand
  - name: Product segment
    expr: product.product_segment
  - name: Product name
    expr: product.product_name

  # --- degenerate dimensions (live on the fact itself) ---
  - name: Payment mode
    expr: source.payment_mode
  - name: Sales channel
    expr: source.sales_channel
  - name: Store
    expr: source.store_id

measures:
  # Revenue = quantity * price, net of discount. NOT SUM(selling_price).
  - name: Total revenue
    expr: SUM(source.quantity * source.selling_price - coalesce(source.discount_amount, 0))

  - name: Gross revenue
    expr: SUM(source.quantity * source.selling_price)

  - name: Total quantity
    expr: SUM(source.quantity)

  - name: Total discount
    expr: SUM(source.discount_amount)

  # Grain is one row per transaction, so COUNT(1) is the transaction count.
  - name: Transaction count
    expr: COUNT(1)

  - name: Unique products sold
    expr: COUNT(DISTINCT source.product_id)

  - name: Stores selling
    expr: COUNT(DISTINCT source.store_id)

  # Ratio measures reference the base expressions, so they stay correct under
  # any GROUP BY (no average-of-averages).
  - name: Average transaction value
    expr: SUM(source.quantity * source.selling_price - coalesce(source.discount_amount, 0)) / COUNT(1)

  - name: Average discount per transaction
    expr: SUM(source.discount_amount) / COUNT(1)
$$;

-- COMMAND ----------

-- TEST 1 — revenue and volume by product category
SELECT
    Category,
    MEASURE(`Total revenue`)     AS total_revenue,
    MEASURE(`Total quantity`)    AS units_sold,
    MEASURE(`Transaction count`) AS txns
FROM retail_q.retail_semantic.retail_metrics
GROUP BY Category
ORDER BY total_revenue DESC;

-- COMMAND ----------

-- TEST 2 — the SAME measures, sliced by month instead. No new object needed.
SELECT
    Year,
    Month,
    MEASURE(`Total revenue`)            AS total_revenue,
    MEASURE(`Average transaction value`) AS atv
FROM retail_q.retail_semantic.retail_metrics
GROUP BY Year, Month
ORDER BY Year, Month;

-- COMMAND ----------

-- TEST 3 — a two-dimensional slice: brand x payment mode
SELECT
    Brand,
    `Payment mode`,
    MEASURE(`Total revenue`) AS total_revenue
FROM retail_q.retail_semantic.retail_metrics
GROUP BY Brand, `Payment mode`
ORDER BY Brand, total_revenue DESC;
