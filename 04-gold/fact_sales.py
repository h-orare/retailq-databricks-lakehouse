"""
Gold — fact_sales
Built inside the declarative pipeline as a materialised TABLE.

Grain: one row per transaction.
Assembly: transactions LEFT JOIN opportunity on opportunity_name.
The customer link is carried from opportunity.account_id, because the
transactions source has no customer id of its own.
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

TRANSACTIONS = "retail_q.retail_silver.transactions"
OPPORTUNITY  = "retail_q.retail_silver.opportunity"


@dp.table(
    name="fact_sales",
    comment="Central sales fact. One row per transaction. Customer is resolved "
            "through the opportunity bridge; date_key joins to dim_calendar.",
)
def fact_sales():
    txn = spark.read.table(TRANSACTIONS)

    # Deduplicate the bridge to one row per name BEFORE joining.
    # opportunity.name is not guaranteed unique, and a many-match would fan the
    # transaction out into several fact rows, double-counting revenue. Collapsing
    # to one opportunity per name guarantees the join preserves transaction grain.
    # (If a real opportunity key existed on the transaction, we would join on it
    # instead and drop this step.)
    opp = (
        spark.read.table(OPPORTUNITY)
        .where(F.col("is_deleted") == False)  # noqa: E712
        .withColumn(
            "_rn",
            F.row_number().over(
                __import__("pyspark.sql.window", fromlist=["Window"]).Window
                .partitionBy("name").orderBy(F.col("last_modified_date").desc())
            ),
        )
        .where(F.col("_rn") == 1)
        .select(
            F.col("name").alias("opp_name"),
            F.col("account_id").alias("customer_id"),
            F.col("deal_size"),
            F.col("stage_name"),
        )
    )

    joined = txn.join(opp, txn["opportunity_name"] == opp["opp_name"], "left")

    return joined.select(
        # grain
        F.col("transaction_id"),

        # foreign keys
        F.to_date(F.col("transaction_timestamp")).alias("date_key"),
        F.col("customer_id"),
        F.col("product_id"),

        # measures
        F.col("quantity"),
        F.col("selling_price"),
        F.col("discount_amount"),
        (F.col("quantity") * F.col("selling_price") - F.coalesce(F.col("discount_amount"), F.lit(0)))
            .alias("net_sales_amount"),

        # degenerate dimensions (attributes of the sale itself)
        F.col("payment_mode"),
        F.col("sales_channel"),

        # carried from the bridge for convenience
        F.col("deal_size"),
    )
