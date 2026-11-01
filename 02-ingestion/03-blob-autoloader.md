# Section 6 — Blob storage volume and Auto Loader

Third and final ingestion pattern: files. Code lives in `blob_to_bronze.py`.

## Why not Lakeflow Connect

Managed connectors rely on a source that has a fixed schema and a reliable
change-tracking column. A directory of files has neither — any format, any
structure, no watermark. There is no file connector, so Auto Loader is used
instead.

## Unity Catalog objects

| Object | Name | Purpose |
|---|---|---|
| Schema | `retailq.volumes` | Holds volumes, kept separate from table schemas |
| Volume | `retailq.volumes.blob_source` | Managed volume — governed file storage |
| Directory | `/transaction_source/` | Where source CSVs land |
| Schema | `retailq.blob_bronze` | Target schema for the ingested table |
| Table | `retailq.blob_bronze.transactions` | Target streaming table |

### Volumes

A volume is the Unity Catalog object for **non-tabular data** — the file
equivalent of a table. Same governance model: `catalog.schema.volume`, with
grants, lineage and audit.

- **Managed volume** — storage provided by Unity Catalog. Used here.
- **External volume** — points at a real S3 / ADLS / GCS location.

Once created, both behave identically in code. Swapping managed for external
later requires no change to the notebook.

## Auto Loader

Invoked by `.format("cloudFiles")` on a Structured Streaming read. Streaming is
used for the bookkeeping, not for low latency: the stream is what remembers
which files have already been seen.

### The two sidecar folders

| Option | Holds | Consequence of deleting it |
|---|---|---|
| `checkpointLocation` | Which files have been processed | Next run reloads every file, duplicating rows |
| `cloudFiles.schemaLocation` | The inferred schema | Schema is re-inferred; evolution history lost |

Both are created automatically next to the data.

### Trigger modes

| Trigger | Behaviour |
|---|---|
| none (default) | Micro-batches forever; cell never exits, compute never releases |
| `availableNow=True` | Process everything available now, then stop — **used here** |
| `processingTime='5 minutes'` | Wake on an interval, run indefinitely |

`availableNow` is correct for this project: the pipeline is triggered by a
Databricks Job in section 13, not left running.

### `awaitTermination()`

`writeStream.start()` / `.toTable()` returns immediately with a handle while the
stream runs in the background, so the notebook cell appears to hang. Assigning
the handle to a variable and calling `query.awaitTermination()` blocks until the
batch finishes, then exits cleanly. Required for the cell to be usable as a job
step.

This is what the tutorial hit mid-section and had the assistant fix.

### `_rescued_data`

Auto Loader adds this column automatically. Any value that does not fit the
inferred schema is captured here rather than failing the run or being silently
dropped. Check it after ingestion:

```sql
SELECT COUNT(*) FROM retailq.blob_bronze.transactions
WHERE _rescued_data IS NOT NULL;
```

## Column type inference — verify this

For CSV and JSON, Auto Loader infers **all columns as STRING** unless
`cloudFiles.inferColumnTypes` is set to `true`. The CSV reader option
`inferSchema` is not the equivalent option for Auto Loader.

Run `DESCRIBE TABLE retailq.blob_bronze.transactions`. If `quantity`,
`selling_price` and `discount_amount` are strings, they must be cast in the
silver layer — otherwise arithmetic in the gold layer fails or, worse, produces
string concatenation.

Because the schema is cached in the schema location, changing the option alone
does not fix an already-inferred schema. Clear the schema and checkpoint folders
and reload the table.

## Incremental behaviour observed

| Run | Files present | Rows in target |
|---|---|---|
| 1 | `transactions_history.csv` (1,000) | 1,000 |
| 2 | + `transactions_new.csv` (100) | 1,100 |

The first file was not re-read. The checkpoint is what makes this work.

## AWS parallel

Auto Loader's default mode lists the directory to find new files. At scale it
can switch to file-notification mode, which is conceptually the same design as
S3 event notifications feeding a queue that a consumer drains. A Unity Catalog
external volume plays the role of a governed, permissioned mount over an S3
bucket.

## Note on the AI-generated code

The assistant produced working Auto Loader code from a plain-language prompt,
but the first version did not exit. Generated pipeline code needs the same
review as hand-written code — particularly trigger mode, checkpoint location and
schema options, which are exactly the settings that look fine and behave badly.
