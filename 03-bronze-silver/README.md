# Section 7 — Bronze to silver with Lakeflow Declarative Pipelines

## Pipeline setup

`Jobs & Pipelines` → **ETL pipeline**. Creates a skeleton with a
`transformations/` folder and a starter file.

| Item | Value |
|---|---|
| Pipeline name | `retail_transformations` |
| Folder | `bronze_to_silver` (renamed from `transformations`) |
| Files | one per table: `product_catalog`, `inventory`, `account`, `opportunity`, `transactions` |
| Default catalog | `retail_q` |
| Default schema | `retail_silver` |

Setting the default catalog and schema means `@dp.table(name="product_catalog")`
creates `retail_q.retail_silver.product_catalog`. Source tables are still read by
their fully qualified names.

One silver schema for all sources — silver is standardised and
source-independent, which is the whole point of the layer.

### Files must sit inside the included folder

A file created outside `bronze_to_silver` gets a skip icon and is ignored by
`Run pipeline`. Either drag it into the folder, or set
**Include as pipeline source code** on it. Folders can also be excluded
wholesale.

### Running the pipeline runs every file

Already-loaded streaming tables simply report zero new rows. Incrementality is
handled by the pipeline — no watermark to manage, unlike the Auto Loader
notebook.

### Free edition: permission denied

A known bug. The workaround is to copy the code, create a **new** pipeline, and
paste it in. Not a code problem.

## The API

```python
from pyspark import pipelines as dp
```

`dp` = declarative pipelines. The older equivalent is `import dlt` with
`@dlt.table`. **The DE Associate exam uses `dlt`** — learn both spellings.

## Expectations

| Decorator | Failing record | Pipeline |
|---|---|---|
| `@dp.expect` | loaded anyway | continues |
| `@dp.expect_or_drop` | dropped | continues |
| `@dp.expect_or_fail` | — | **run fails immediately** |

Each has an `_all_` variant taking a dict of rules:
`expect_all`, `expect_all_or_drop`, `expect_all_or_fail`.

**Prefer individual rules over the grouped `_all_` form.** Grouped rules share
one action and report as a single metric; individual rules let each condition
have its own action and show up separately in the data quality panel.

**Expectations do not quarantine.** A dropped row is discarded, not routed to a
rejects table. Capturing failures for inspection needs a second table with the
inverse condition.

## What belongs in the silver layer

| Operation | Example from this project |
|---|---|
| Column pruning | Salesforce `Account` has hundreds of mostly-null standard fields; select only what is used |
| Renaming | Salesforce `PascalCase` → `snake_case`; `Name` → `customer_name` |
| Type casting | transaction timestamp string → `TIMESTAMP` via `to_timestamp(col, format)` |
| Null handling | `industry` null → `'Unknown'` |
| Standardisation | `trim`, `initcap`, rounding to 2dp |
| Filtering | drop inactive source records |
| Derived columns | `product_segment`, `inventory_status`, `deal_size`, `gross_amount` |
| Data quality | expectations, as above |

### Derived columns built here

| Column | Table | Logic |
|---|---|---|
| `product_segment` | product_catalog | `unit_price > 50000` → Premium; `> 10000` → Mid-range; else Budget |
| `inventory_status` | inventory | `stock_quantity < reorder_level` → Low stock; else Healthy stock |
| `deal_size` | opportunity | amount bands → Enterprise / Mid-market / Small |
| `gross_amount` | transactions | `quantity * selling_price` |

`product_segment` is not decoration — it is a column of `dim_product` in the
gold star schema, so it has to exist by section 8.

## SCD type 2 tables in silver

`product_catalog` and `account` arrive from bronze carrying `__START_AT` and
`__END_AT`. The pattern used:

- keep both columns
- derive `is_active = __END_AT IS NULL`
- the source's own `is_active` boolean is consumed as a **filter**, not carried
  through

Note the name collision: the output `is_active` means "current SCD version",
which is not what the source column meant.

**Consequence for section 8:** silver keeps the full history, so a product that
has changed appears more than once. Building `dim_product` without filtering
`is_active = true` produces duplicate `product_id` values and every downstream
aggregate double-counts.

## Observed results

| Table | Rows in | Written | Dropped | Notes |
|---|---|---|---|---|
| product_catalog | 24 | 23 | 1 | null `product_name`, `expect_or_drop` |
| inventory | 44 | 44 | 0 | 3 warnings, all `expect` |
| account | — | — | 0 | both expectations met |
| opportunity | — | — | 0 | stage and amount warnings |
| transactions | 1,100 | 1,100 | 0 | warnings only |

Counts differ from the tutorial's because the source data differs — the
PostgreSQL bad rows were rewritten to work with a primary key, and the
Salesforce data is the Developer Edition sample set.

## Points where this project diverges from the video

**Transactions casting may be unnecessary.** The tutorial's bronze transactions
table had every column typed as `STRING`, so it casts numerics and parses the
timestamp. This project set `cloudFiles.inferColumnTypes` in section 6 and
`DESCRIBE TABLE` confirmed correct types. Check before adding casts.

**Do not cast prices to INTEGER.** The video casts `selling_price` and
`discount_amount` to integer, which truncates the decimal part and silently
loses cents. Money belongs in `DECIMAL(10,2)` or `DOUBLE`.

**`stock_quantity > 0` flags a valid business state.** Zero stock means out of
stock, not bad data. `>= 0` is the correct test for validity; negative stock is
the real defect. Kept as a warning here so it does no harm.
