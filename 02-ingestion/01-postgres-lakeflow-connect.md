# Section 4 — PostgreSQL ingestion with Lakeflow Connect

Ingests `product_catalog` and `inventory` from Neon PostgreSQL into the bronze
layer. No code is written: the whole pipeline is configured through the UI.

## Where it lives in the workspace

`Jobs & Pipelines` → `Ingestion pipeline`. "Ingestion pipeline" in the UI and
"Lakeflow Connect" in the documentation are the same feature. The PostgreSQL
connector is in Preview.

## Unity Catalog objects created

| Object | Name | Notes |
|---|---|---|
| Connection | `neon_retailq_pg` | A UC securable holding host/user/password |
| Catalog | `retailq` | Top level of the three-level namespace |
| Schema | `postgres_bronze` | Target for both ingested tables |

Full table names: `retailq.postgres_bronze.product_catalog`,
`retailq.postgres_bronze.inventory`.

The connection is a governed object, not a notebook variable. Credentials are
held by Unity Catalog and granted to principals — they never appear in code.

## Wizard configuration

**1. Connection** — connection type PostgreSQL, then host, port, user, password.
Host must be the Neon **direct** endpoint (no `-pooler` in the hostname).
Database name is supplied later, at the source step.

**2. Pipeline** — name `postgres_to_bronze`; destination catalog `retailq`,
schema `postgres_bronze`.

**3. Source** — enter the database name (`neondb`), expand schema `public`,
select both tables, then per table:

| Table | Cursor column | History tracking | Resulting pattern |
|---|---|---|---|
| `product_catalog` | `updated_at` | ON | SCD type 2 |
| `inventory` | `last_stock_update` | OFF | SCD type 1 |

The split is deliberate — it makes the two behaviours directly comparable.

**4. Destination** — `retailq` / `postgres_bronze` (pre-filled from step 2).

**5. Schedule & notifications** — remove the default hourly schedule. The
pipeline will be triggered by a Databricks Job in section 13. Keep the
failure-notification email.

## What the cursor column does

The connector records the highest value it has seen in the cursor column. On the
next run it reads only rows above that watermark. Leaving the cursor column
unset makes every run a full reload.

This is **watermark-based incremental extraction**, not log-based CDC. Two
consequences to be aware of:

- **Deletes are not captured.** A row deleted in PostgreSQL stays in bronze,
  because a deleted row has no timestamp to detect.
- **It depends on the source updating the timestamp.** A row updated without
  bumping `updated_at` is invisible to the pipeline.

Both limitations are normal and acceptable for this project; they are worth
stating explicitly in the summary document as a known trade-off.

## Target tables

Targets are **streaming tables** — Delta tables with an attached streaming query
that processes each source row exactly once. The pipeline builds a lineage graph
showing source → target per table.

With history tracking ON, two columns are added automatically:

- `__START_AT` — when this version became current
- `__END_AT` — when it stopped being current; `NULL` means current

## Observed behaviour on re-run

Source changes made, then the pipeline re-run:

| Table | Source change | Records written | Effect |
|---|---|---|---|
| `inventory` (SCD 1) | `INV0040` qty 24 → 25 | 1 updated | Row overwritten in place |
| `product_catalog` (SCD 2) | `P0020` price 9999 → 10000 | 2 upserted | Old row expired, new row inserted |

## Querying rules

```sql
-- current state of an SCD type 2 table
SELECT * FROM retailq.postgres_bronze.product_catalog
WHERE __END_AT IS NULL;

-- state as at a given moment
SELECT * FROM retailq.postgres_bronze.product_catalog
WHERE DATE('2026-06-01') BETWEEN __START_AT
      AND COALESCE(__END_AT, DATE('9999-12-31'));
```

Forgetting the `__END_AT IS NULL` filter is the most common SCD type 2 bug: every
aggregate silently double-counts products that have ever changed.

## Trade-off noted for the summary document

History tracking is applied at the **bronze** layer rather than in the silver or
gold transformation. Bronze is therefore not a pure raw landing copy — it already
carries dimensional history. This is what the managed connector offers, and it is
internally consistent, but it differs from the textbook medallion pattern where
bronze is append-only raw and SCD handling happens downstream.

## Debugging note

During the demo the first `inventory` change did not appear in the target. The
cause was that the edit was never committed in the Neon console. When a change
does not propagate, verify the source row first before investigating the pipeline.
