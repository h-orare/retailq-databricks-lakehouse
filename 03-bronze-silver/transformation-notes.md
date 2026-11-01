# Bronze to silver — transformations applied, per table

Tutorial versions are kept verbatim in `tutor-reference/`.
`product_catalog.py` in this folder is the revised implementation.

---

## account  (Salesforce → silver)

Source `retail_q.salesforce_bronze.account` — SCD type 2. Streaming read.

| Category | Applied |
|---|---|
| Column pruning | ~21 columns kept from several hundred standard Salesforce fields |
| Renaming | `PascalCase` → `snake_case`; `Name` → `customer_name` |
| Standardisation | `upper(trim(Name))` |
| Null handling | `Industry` null → `'UNKNOWN'` |
| Derived | `is_active = __END_AT IS NULL` |

Expectations: `id IS NOT NULL` (drop); `customer_name IS NOT NULL` (warn).

---

## inventory  (PostgreSQL → silver)

Source `retail_q.postgres_bronze.inventory` — SCD type 1. Streaming read.

| Category | Applied |
|---|---|
| Column pruning | all 7 source columns kept |
| Renaming | none — source is already snake_case |
| Derived | `inventory_status` = `LOW_STOCK` when `stock_quantity < reorder_level`, else `HEALTHY` |

Expectations: `inventory_id IS NOT NULL` (drop); `stock_quantity > 0`,
`product_id IS NOT NULL`, `store_id IS NOT NULL` (all warn).

No SCD columns, correctly — history tracking was off for this table.

---

## opportunity  (Salesforce → silver)

Source `retail_q.salesforce_bronze.opportunity` — SCD type 1. Streaming read.

| Category | Applied |
|---|---|
| Column pruning | 19 columns kept |
| Renaming | `PascalCase` → `snake_case` |
| Derived | `deal_size` = `ENTERPRISE` > 100,000; `MID_MARKET` > 25,000; else `SMALL` |

Expectations: `id IS NOT NULL` (drop); `name IS NOT NULL`,
`amount IS NULL OR amount >= 0`, `probability` between 0 and 100,
`stage_name IN ('Prospecting','Closed Won','Closed Lost')` (all warn).

The stage list is deliberately incomplete so that warnings are generated.

---

## transactions  (cloud files → silver)

Source `retail_q.blob_bronze.transactions`. **Batch read** — the only table of
the five read with `spark.read` rather than `spark.readStream`, which makes it
a materialized view.

| Category | Applied |
|---|---|
| Column pruning | `_rescued_data` excluded |
| Type casting | `quantity`, `selling_price`, `discount_amount` → `int` |
| Type parsing | `transaction_timestamp` string → `TIMESTAMP` via format `dd-MMM-yyyy hh.mm.ss a` |
| Derived | `gross_amount = quantity * selling_price` |

Expectations: `transaction_id IS NOT NULL` (drop); `quantity > 0`,
`selling_price >= 0`, `discount_amount >= 0`, `product_id IS NOT NULL`,
`payment_mode IN ('UPI','Card','Cash','Net Banking')` (all warn).

---

# Review findings

## Significant — affects the gold layer

### The customer link runs through Opportunity

`transactions` has **no `customer_id`**. It carries `opportunity_name`.
But `fact_sales` in the gold star schema has `customer_id` as a foreign key.

The only path from a transaction to a customer is:

```
transactions.opportunity_name  →  opportunity.name
opportunity.account_id         →  account.id
account                        →  dim_customer
```

So Salesforce `Opportunity` is **not** merely ingested for demonstration — it is
a **bridge table** resolving transactions to customers. The earlier assessment
that it was ingested but unused was wrong, and the summary document should say
so: Opportunity is not modelled as a fact or a dimension, but it is required to
populate `fact_sales.customer_id`.

Consequence: any transaction whose `opportunity_name` does not match an
opportunity loses its customer. That join needs a referential check in section 8.

### SCD type 2 tables keep full history with no date columns

`account` keeps every version (no `__END_AT IS NULL` filter) and adds
`is_active`, but **does not carry `__START_AT` or `__END_AT` through**.

Two consequences:

1. `retail_silver.account` has duplicate `id` values for any account that has
   changed. Building `dim_customer` without filtering `is_active = true`
   produces duplicate customers and double-counted revenue.
2. History is retained but unusable — without the validity dates there is no way
   to ask what an account looked like at a point in time. It is the cost of
   SCD type 2 without the benefit.

Either filter to current in silver, or carry the date columns through.

### `store_id` is ingested but has no dimension

Both `inventory` and `transactions` carry `store_id`, and there is no
`dim_store` in the gold model. Noted, not actioned — out of scope.

## Bugs

### `selling_price` cast to `int` truncates money

```python
F.col("selling_price").cast("int")
```

Cents are silently discarded on every row, and `gross_amount` inherits the
error. Money belongs in `DECIMAL(10,2)`.

### Casting may be unnecessary, and `to_timestamp` may fail

This project set `cloudFiles.inferColumnTypes` in section 6, so the bronze
columns already have correct types — unlike the tutorial's, which were all
`STRING`. Run `DESCRIBE TABLE retail_q.blob_bronze.transactions` first.

If `transaction_timestamp` is already a `TIMESTAMP`, applying
`to_timestamp(col, 'dd-MMM-yyyy hh.mm.ss a')` to it will not behave as intended.

### `deal_size` labels a null amount as `SMALL`

```python
F.when(F.col("amount") > 100000, "ENTERPRISE")
 .when(F.col("amount") > 25000, "MID_MARKET")
 .otherwise("SMALL")
```

An opportunity with no amount falls through to `SMALL`, fabricating a
classification from missing data. Needs a `.when(F.col("amount").isNotNull(), "SMALL")`
before the `otherwise`.

### Soft-deleted Salesforce records are never filtered

Both Salesforce tables select `is_deleted` and neither filters on it. Deleted
accounts and opportunities flow into silver and will appear in the gold layer.
`WHERE is_deleted = false` is missing.

## Smaller observations

- **Fact tables should drop, not warn.** Every `transactions` rule except
  `transaction_id` is a warning, so rows with zero quantity or negative prices
  reach gold. The dimension policy (repair and flag) and the fact policy
  (drop what cannot be measured) should differ.
- **`stock_quantity > 0`** flags legitimate out-of-stock rows. `>= 0` is the
  correct validity test; negative stock is the actual defect.
- **Streaming reads from merge-maintained bronze tables.** `account`,
  `inventory` and `opportunity` use `readStream` against tables that are
  updated in place. This can fail with "Detected a data update" once rows are
  rewritten. `transactions` correctly uses a batch read. If the error appears,
  the fix is a batch read, not `skipChangeCommits`.
- **`F.col("amount")` inside the same `select` that creates the `amount` alias**
  resolves to the source column `Amount` because Spark is case-insensitive by
  default. It works, but it reads as though it references the alias, which it
  does not.
