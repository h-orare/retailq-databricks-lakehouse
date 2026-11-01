# Section 5 — Salesforce ingestion with Lakeflow Connect

Ingests `Account` and `Opportunity` from a Salesforce Developer Edition org into
the bronze layer. Same wizard as PostgreSQL, four meaningful differences.

## Unity Catalog objects

| Object | Name |
|---|---|
| Connection | `salesforce_retail` |
| Catalog | `retailq` (reused) |
| Schema | `salesforce_bronze` (new) |
| Pipeline | `salesforce_to_bronze` |

Catalog is shared across sources; each source gets its own bronze schema.

## Per-table configuration

| Object | Cursor column | History tracking | Pattern |
|---|---|---|---|
| `Account` | not required | ON | SCD type 2 |
| `Opportunity` | not required | OFF | SCD type 1 |

Schedule: delete the default 6-hourly run. Keep failure notifications.

## Differences from the PostgreSQL connector

### 1. Authentication is OAuth, not host and password

"Authenticate and create connection" opens a Salesforce login, then an allow
prompt. No host, port or database is entered — the instance URL is resolved from
the username.

Log in with the **Salesforce username**, not the signup email. The username looks
like an email address but is a separate identity, issued in the activation email.

### 2. No cursor column to choose

Salesforce maintains `SystemModstamp` on every object automatically, and the
connector knows to use it. Nothing to configure.

Contrast with PostgreSQL, where `updated_at` had to be nominated by hand and the
pipeline is only as correct as the application's discipline in maintaining it.

### 3. No table creation

Every Salesforce org has the same standard object schema, created implicitly.
The source picker therefore lists hundreds of objects, nearly all empty. This is
expected, not a misconfiguration.

Contrast with PostgreSQL, where DDL was authored before anything could be
ingested.

### 4. Column selection, with two mandatory fields

The column list is editable, but `Id` and `IsDeleted` cannot be deselected.

`IsDeleted` matters: Salesforce soft-deletes records rather than removing them,
so a deletion arrives as a flag change rather than a disappearing row. The
PostgreSQL watermark approach cannot see deletes at all. Downstream logic should
filter `IsDeleted = false`.

`Include future columns` enables schema evolution — fields added in Salesforce
later flow through without reconfiguring the pipeline.

## Observed behaviour on re-run

| Object | Source change | Effect in target |
|---|---|---|
| `Account` (SCD 2) | phone number edited | old row stamped `__END_AT`, new row inserted with `__END_AT` null |
| `Opportunity` (SCD 1) | stage → Closed Won | row updated in place; `LastStageChangeDate` updated by Salesforce |

Identical SCD semantics to the PostgreSQL pipeline — the behaviour comes from the
history tracking toggle, not from the source system.

## Notes

- Many columns in the target are null. Standard Salesforce objects carry a large
  number of fields; only those populated in the CSV hold values. Normal.
- Salesforce record IDs are platform-generated 18-character keys, not the
  natural keys used in the PostgreSQL tables.
- List views default to "Recently Viewed" and can appear empty. Switch to
  "All Opportunities" to see the full set.
- Row counts here depend on how much data was loaded; this project used the
  Developer Edition sample opportunities rather than an imported CSV, so counts
  differ from the tutorial.
