-- =========================================================
-- RetailQ — gold dimension views + calendar
-- Run once as a notebook / SQL task. Views auto-reflect silver.
-- =========================================================

-- dim_customer : current, non-deleted accounts only
CREATE OR REPLACE VIEW retail_q.retail_gold.dim_customer AS
SELECT
    id              AS customer_id,
    customer_name,
    type            AS customer_type,
    billing_city    AS city,
    billing_state   AS state,
    billing_country AS country,
    industry
FROM retail_q.retail_silver.account
WHERE is_deleted = false
  AND is_active  = true;

-- dim_product : current version of each product only
CREATE OR REPLACE VIEW retail_q.retail_gold.dim_product AS
SELECT
    product_id,
    product_name,
    category,
    subcategory,
    brand,
    product_segment,
    unit_price,
    supplier_name
FROM retail_q.retail_silver.product_catalog
WHERE is_active = true;

-- dim_inventory : not part of the star, exposed for dashboards
CREATE OR REPLACE VIEW retail_q.retail_gold.dim_inventory AS
SELECT
    inventory_id,
    product_id,
    store_id,
    stock_quantity,
    reorder_level,
    inventory_status,
    warehouse_location,
    last_stock_update
FROM retail_q.retail_silver.inventory;

-- dim_calendar : generated, one row per day. Built once.
CREATE OR REPLACE TABLE retail_q.retail_gold.dim_calendar AS
WITH dates AS (
    SELECT explode(sequence(
        DATE('2025-01-01'), DATE('2028-12-31'), INTERVAL 1 DAY
    )) AS full_date
)
SELECT
    CAST(date_format(full_date, 'yyyyMMdd') AS INT) AS date_key,
    full_date,
    day(full_date)                     AS day,
    date_format(full_date, 'EEEE')     AS day_name,
    weekofyear(full_date)              AS week_number,
    month(full_date)                   AS month,
    date_format(full_date, 'MMMM')     AS month_name,
    quarter(full_date)                 AS quarter,
    year(full_date)                    AS year,
    CASE WHEN date_format(full_date, 'EEEE') IN ('Saturday','Sunday')
         THEN true ELSE false END      AS is_weekend
FROM dates;

-- =========================================================
-- INTEGRITY CHECKS — run after building fact_sales
-- =========================================================

-- Fan-out check: fact must not exceed the transaction count.
SELECT
  (SELECT COUNT(*) FROM retail_q.retail_silver.transactions) AS txn_rows,
  (SELECT COUNT(*) FROM retail_q.retail_gold.fact_sales)     AS fact_rows;

-- Orphan customers: transactions whose opportunity_name did not match.
SELECT COUNT(*) AS orphan_customer_rows
FROM retail_q.retail_gold.fact_sales
WHERE customer_id IS NULL;

-- Orphan products: fact product_id with no dim_product row.
SELECT COUNT(*) AS orphan_product_rows
FROM retail_q.retail_gold.fact_sales f
LEFT JOIN retail_q.retail_gold.dim_product p ON f.product_id = p.product_id
WHERE p.product_id IS NULL;
