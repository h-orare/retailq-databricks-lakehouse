# Review of the tutor's actual gold artifacts

Tutor files are in this folder. My alternative `fact_sales.py` and
`gold_views.sql` are one level up. Deltas between what the slide showed, what I
assumed, and what the tutor actually built:

## fact_sales.py — tutor's real version

### Good
- Join key is `upper(trim(opportunity_name)) = upper(trim(name))` — case and
  whitespace normalised. Better than a raw equality join.
- `transaction_date = CAST(transaction_timestamp AS DATE)` keys the calendar
  join on a DATE, matching the calendar's `date` column. No integer surrogate.
- `customer_id = o.account_id` — the bridge resolves the customer, as expected.

### Flag A — no deduplication of opportunity  (fan-out risk, live)
Nothing collapses opportunity to one row per name before the join. If two
opportunities share a name, matching transactions fan out and measures
multi-count. The case-normalised key makes MORE names collide, not fewer.
Run the fan-out check in `../gold_views.sql` after building. My version
deduplicates with a row_number window; the tutor's does not.

### Flag B — o.amount is a mixed-grain measure  (the important one)
`o.amount` is the OPPORTUNITY's total deal value, carried onto a
TRANSACTION-grain fact. One opportunity usually has many transactions, so its
amount is repeated on every transaction row.

Consequence: `SUM(fact_sales.amount)` multi-counts the deal value by the number
of transactions per opportunity. `amount` is non-additive at this grain.

The transaction-grain measures (`quantity`, `selling_price`, `discount_amount`,
and `quantity * selling_price`) are additive and safe to sum. `amount` is not.

Options: drop it from the fact; or keep it but never SUM it — treat it as a
reference attribute. This is exactly the kind of distinction the semantic layer
(section 9, metric views) exists to encode: declaring which measures are
additive and how each aggregates.

### Flag C — redundant columns
Both `opportunity_name` (from t) and `name` (from o) are kept — the same value
twice after the join. Drop one.

### Note — slide vs build
The section-3 slide showed `fact_sales` with `net_sales_amount` and a tidy FK
list. The real build computes no `net_sales_amount` and carries extra
opportunity columns (`stage_name`, `owner_id`, `amount`). Net sales is left to
be computed downstream. Not wrong — just be aware the delivered fact is wider
and rawer than the diagram.

## Gold views — tutor's real version

### Good catch by the tutor: inventory is named `fact_inventory`, not a dim.
He correctly treats inventory as a fact table, matching the section-3
assessment. My own notes earlier called it `dim_inventory`; his naming is the
correct one. (It is still a view over silver, exposed for dashboards, outside
the star.)

- `dim_customer`: `WHERE is_deleted = false AND is_active = true` — correct;
  fixes the soft-delete and SCD2-duplicate gaps from section 7.
- `dim_product`: `WHERE is_active = true` — correct. Still subject to Flag 2
  from section 8 (current-version-only → SCD2 consumed as type 1).

## Calendar — tutor's real version

- Parameterised on `:start_date` / `:end_date` — good, reusable.
- Keyed on the raw `date` (DATE) column, so `fact_sales.transaction_date` joins
  to `calendar.date`. No integer date_key. (My `gold_views.sql` used an integer
  yyyyMMdd key — ignore that; the tutor's date-keyed design is internally
  consistent and is the one in use.)
- `dayofweek` returns 1=Sunday … 7=Saturday, so `IN (1,7)` = weekend is correct.
- Very rich (year_quarter, is_first/last_day_of_month, etc.) — more than needed,
  harmless. Renamed to `dim_calendar` in the UI afterwards.
