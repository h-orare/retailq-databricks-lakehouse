-- =========================================================
-- RetailQ — data quality monitoring from the pipeline event log
--
-- Expectation results are not just a UI panel. Every run writes them to the
-- pipeline's event log, which is queryable SQL. These queries turn that into
-- something a data engineer can review, trend and alert on.
--
-- NOTE ON SYNTAX: the event_log() table-valued function accepts either a
-- pipeline id or a TABLE() reference to a dataset produced by that pipeline.
-- Which form your workspace accepts varies. Run query 0 first and adjust.
-- =========================================================


-- ---------------------------------------------------------
-- 0. Confirm access and inspect the raw structure
--    Run this first. The details column is JSON; look at it before
--    assuming the paths used below are correct for your runtime.
-- ---------------------------------------------------------
SELECT
    timestamp,
    event_type,
    message,
    details
FROM event_log(TABLE(retail_q.retail_silver.product_catalog))
WHERE event_type = 'flow_progress'
ORDER BY timestamp DESC
LIMIT 20;


-- ---------------------------------------------------------
-- 1. Expectation results for the most recent run
--    The everyday check: what failed last night?
-- ---------------------------------------------------------
WITH events AS (
    SELECT
        timestamp,
        from_json(
            details:flow_progress.data_quality.expectations,
            'array<struct<name:string, dataset:string,
                          passed_records:bigint, failed_records:bigint>>'
        ) AS expectations
    FROM event_log(TABLE(retail_q.retail_silver.product_catalog))
    WHERE event_type = 'flow_progress'
      AND details:flow_progress.data_quality.expectations IS NOT NULL
),
flattened AS (
    SELECT timestamp, explode(expectations) AS e
    FROM events
)
SELECT
    e.dataset,
    e.name                AS expectation,
    e.passed_records,
    e.failed_records,
    ROUND(100.0 * e.failed_records
          / NULLIF(e.passed_records + e.failed_records, 0), 2) AS failure_pct
FROM flattened
WHERE timestamp = (SELECT MAX(timestamp) FROM flattened)
ORDER BY e.failed_records DESC, e.name;


-- ---------------------------------------------------------
-- 2. Failure rate over time
--    The query that actually matters. A rule whose failure rate is climbing
--    means the source system changed. A rule at a flat 0% forever may be
--    testing nothing — both are worth knowing.
-- ---------------------------------------------------------
WITH events AS (
    SELECT
        timestamp,
        from_json(
            details:flow_progress.data_quality.expectations,
            'array<struct<name:string, dataset:string,
                          passed_records:bigint, failed_records:bigint>>'
        ) AS expectations
    FROM event_log(TABLE(retail_q.retail_silver.product_catalog))
    WHERE event_type = 'flow_progress'
      AND details:flow_progress.data_quality.expectations IS NOT NULL
),
flattened AS (
    SELECT DATE(timestamp) AS run_date, explode(expectations) AS e
    FROM events
)
SELECT
    run_date,
    e.dataset,
    e.name                       AS expectation,
    SUM(e.failed_records)        AS failed_records,
    SUM(e.passed_records)        AS passed_records,
    ROUND(100.0 * SUM(e.failed_records)
          / NULLIF(SUM(e.passed_records) + SUM(e.failed_records), 0), 2) AS failure_pct
FROM flattened
GROUP BY run_date, e.dataset, e.name
ORDER BY run_date DESC, failed_records DESC;


-- ---------------------------------------------------------
-- 3. Run outcomes — did the pipeline itself succeed?
--    Expectation metrics are meaningless if the run never completed.
-- ---------------------------------------------------------
SELECT
    timestamp,
    details:flow_progress.status   AS status,
    message,
    level
FROM event_log(TABLE(retail_q.retail_silver.product_catalog))
WHERE event_type IN ('flow_progress', 'update_progress')
  AND level IN ('WARN', 'ERROR')
ORDER BY timestamp DESC
LIMIT 50;


-- ---------------------------------------------------------
-- 4. Row-level investigation — what the event log CANNOT tell you
--    The event log records counts, never the offending rows. Because this
--    pipeline repairs rather than drops, the rows are still in silver and
--    can be inspected directly. A pipeline that dropped them would need a
--    separate quarantine table carrying the inverse condition.
-- ---------------------------------------------------------
SELECT
    product_id,
    product_name,
    category,
    unit_price,
    unit_price_status,
    has_quality_issue,
    silver_loaded_at
FROM retail_q.retail_silver.product_catalog
WHERE has_quality_issue
ORDER BY product_id;


-- ---------------------------------------------------------
-- 5. Snapshot the event log for long-term audit
--    The event log lives with the pipeline. Delete or recreate the pipeline
--    and the history goes with it. If data quality history has to outlive
--    the pipeline, persist it.
-- ---------------------------------------------------------
-- CREATE TABLE IF NOT EXISTS retail_q.retail_ops.dq_history AS
-- SELECT current_timestamp() AS captured_at, *
-- FROM event_log(TABLE(retail_q.retail_silver.product_catalog))
-- WHERE event_type = 'flow_progress';
