"""
Silver — product_catalog

Source : retail_q.postgres_bronze.product_catalog   (SCD type 2, merge-maintained)
Target : retail_q.retail_silver.product_catalog     (materialized view)

Design decisions, with reasoning, are documented inline. The short version:

1.  Materialized view, not a streaming table.
    The bronze table is SCD type 2 and is maintained by merge, so rows are
    rewritten in place. A streaming read of a mutable Delta table errors out,
    and the usual workaround (skipChangeCommits) suppresses the error by
    ignoring rewritten files — which can silently miss the updates this table
    exists to capture. A batch read recomputes current state every run and is
    correct by construction. Facts stream; dimensions recompute.

2.  Current version only.
    __END_AT IS NULL selects the live version of each product, giving exactly
    one row per product_id. Full history remains queryable in bronze.

3.  Discontinued products are kept.
    A product that is no longer sold still has historical sales referencing it.
    Filtering it out would orphan those facts. The flag is carried as an
    attribute so the consumer decides.

4.  Soft failures warn; they do not drop.
    Dropping a row from a dimension breaks referential integrity for every fact
    pointing at it. Only a missing product_id is fatal, because a dimension row
    with no key cannot be joined to at all. Everything else is repaired to a
    sentinel and flagged. The opposite policy applies in fact_sales, where a
    bad row costs one measurement rather than orphaning many.

5.  Repair at column granularity, not row granularity.
    An invalid list price invalidates that column, not the product. The value
    is nulled so it cannot reach gold, the key and every other attribute are
    kept, and unit_price_status records why the null is there. Bronze retains
    the original.
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

SOURCE_TABLE = "retail_q.postgres_bronze.product_catalog"

# Canonical category set, agreed with the data owner. Anything outside it is a
# warning rather than a drop: an unexpected category is a signal that the source
# has changed, not a reason to lose the product.
VALID_CATEGORIES = ["Electronics", "Fashion", "Groceries", "Home"]

MISSING = "Unknown"


def _clean(column):
    """Trim, collapse repeated internal whitespace, and title-case a text column."""
    return F.initcap(F.regexp_replace(F.trim(F.col(column)), r"\s+", " "))


def _clean_or_unknown(column):
    """As _clean, but empty or null values become the MISSING sentinel.

    A sentinel rather than a null, so that the value still groups and joins
    predictably downstream and the gap stays visible in a dashboard.
    """
    cleaned = _clean(column)
    return F.when(cleaned.isNull() | (F.length(cleaned) == 0), F.lit(MISSING)).otherwise(cleaned)


@dp.table(
    name="product_catalog",
    comment=(
        "Current version of each product from the PostgreSQL catalogue, "
        "standardised and quality-checked. One row per product_id. "
        "Discontinued products are retained so historical facts remain joinable."
    ),
    table_properties={
        "quality": "silver",
        "delta.enableChangeDataFeed": "true",
    },
)
# --- Hard contract: without a key the row cannot be joined to at all. ---
@dp.expect_or_fail(
    "product_id_present",
    "product_id IS NOT NULL AND length(product_id) > 0",
)
# --- Soft checks: reported, never dropped. Expressions reference the OUTPUT
#     columns, which is why they test against the sentinel rather than NULL. ---
@dp.expect("product_name_present", f"product_name <> '{MISSING}'")
@dp.expect("category_known", f"category IN ({', '.join(repr(c) for c in VALID_CATEGORIES)})")
@dp.expect("unit_price_present", "unit_price_status <> 'missing'")
@dp.expect("unit_price_valid", "unit_price_status <> 'invalid'")
@dp.expect("supplier_present", f"supplier_name <> '{MISSING}'")
@dp.expect("launch_date_not_future", "launch_date IS NULL OR launch_date <= current_date()")
def product_catalog():
    bronze = (
        spark.read.table(SOURCE_TABLE)
        # Current SCD type 2 version only — one row per product.
        .where(F.col("__END_AT").isNull())
    )

    return bronze.select(
        # --- Business key ---
        F.trim(F.col("product_id")).alias("product_id"),

        # --- Descriptive attributes, standardised ---
        _clean_or_unknown("product_name").alias("product_name"),
        _clean_or_unknown("category").alias("category"),
        _clean_or_unknown("subcategory").alias("subcategory"),
        _clean_or_unknown("brand").alias("brand"),
        _clean_or_unknown("supplier_name").alias("supplier_name"),

        # Money as DECIMAL, never INTEGER — an integer cast silently truncates
        # the minor units on every row.
        #
        # A non-positive list price is not a price. The value is nulled rather
        # than propagated into gold, where it could produce a negative discount.
        # The product row itself survives, so facts referencing this product
        # still join. The original value remains in bronze if anyone needs it —
        # that is what the raw layer is for.
        F.when(F.col("unit_price") > 0, F.col("unit_price").cast("decimal(10,2)"))
         .otherwise(F.lit(None).cast("decimal(10,2)"))
         .alias("unit_price"),

        # Records WHY the price is null, so "never supplied" and "supplied but
        # invalid" stay distinguishable after the repair above.
        F.when(F.col("unit_price").isNull(), F.lit("missing"))
         .when(F.col("unit_price") <= 0, F.lit("invalid"))
         .otherwise(F.lit("ok"))
         .alias("unit_price_status"),

        F.col("launch_date"),

        # --- Derived: price band. dim_product carries this column in the gold
        #     star schema, so it is built once here rather than in every query. ---
        F.when(F.col("unit_price") > 50000, F.lit("Premium"))
         .when(F.col("unit_price") > 10000, F.lit("Mid-range"))
         .when(F.col("unit_price") > 0, F.lit("Budget"))
         .otherwise(F.lit(MISSING))
         .alias("product_segment"),

        # --- Commercial status from the source system. Retained as an
        #     attribute, not applied as a filter. ---
        F.coalesce(F.col("is_active"), F.lit(False)).alias("is_currently_sold"),

        # --- Row-level quality marker. Because nothing is dropped, downstream
        #     consumers need a way to exclude suspect rows themselves. ---
        (
            F.col("product_name").isNull()
            | F.col("unit_price").isNull()
            | (F.col("unit_price") <= 0)
            | ~F.col("category").isin(VALID_CATEGORIES)
        ).alias("has_quality_issue"),

        # --- Lineage and audit ---
        F.col("__START_AT").alias("version_effective_from"),
        F.col("updated_at").alias("source_updated_at"),
        F.current_timestamp().alias("silver_loaded_at"),
    )
