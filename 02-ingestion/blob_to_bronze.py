# Databricks notebook source
# MAGIC %md
# MAGIC # Blob to bronze — transactions via Auto Loader
# MAGIC
# MAGIC RetailQ, section 6. Ingests CSV files from a Unity Catalog volume into a
# MAGIC bronze streaming table using Auto Loader.
# MAGIC
# MAGIC | | |
# MAGIC |---|---|
# MAGIC | Source | `/Volumes/retail_q/volume_schema/blob_source/transactions_source` |
# MAGIC | Target | `retail_q.blob_bronze.transactions` |
# MAGIC
# MAGIC **How to use**
# MAGIC 1. Run **1. DISCOVERY** — confirms the paths exist and shows what is there.
# MAGIC 2. Run **2. RESET** — once only. Wipes the table and Auto Loader state.
# MAGIC 3. Run **3. INGEST** then **4. VERIFY** — this is the initial load.
# MAGIC 4. For incremental loads: upload a new CSV, then run INGEST and VERIFY again.
# MAGIC    Never run RESET a second time.

# COMMAND ----------

# MAGIC %md
# MAGIC ## 0. CONFIG

# COMMAND ----------

CATALOG       = "retail_q"
VOLUME_SCHEMA = "volume_schema"
VOLUME        = "blob_source"
SOURCE_SUBDIR = "transactions_source"

TARGET_SCHEMA = "blob_bronze"
TARGET_NAME   = "transactions"

# --- derived, no need to edit ---
VOLUME_ROOT     = f"/Volumes/{CATALOG}/{VOLUME_SCHEMA}/{VOLUME}"
SOURCE_PATH     = f"{VOLUME_ROOT}/{SOURCE_SUBDIR}"
SCHEMA_PATH     = f"{VOLUME_ROOT}/_schema"
CHECKPOINT_PATH = f"{VOLUME_ROOT}/_checkpoint"
TARGET_TABLE    = f"{CATALOG}.{TARGET_SCHEMA}.{TARGET_NAME}"

# State must never live inside the directory Auto Loader scans, or it will
# try to parse its own metadata files as source data.
assert SCHEMA_PATH != SOURCE_PATH and not SCHEMA_PATH.startswith(SOURCE_PATH + "/")
assert CHECKPOINT_PATH != SOURCE_PATH and not CHECKPOINT_PATH.startswith(SOURCE_PATH + "/")

print(f"source     : {SOURCE_PATH}")
print(f"schema     : {SCHEMA_PATH}")
print(f"checkpoint : {CHECKPOINT_PATH}")
print(f"target     : {TARGET_TABLE}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. DISCOVERY
# MAGIC
# MAGIC The source directory should contain **only CSV files**. If any `_schema`
# MAGIC or `_checkpoint` directory appears inside it, that is left over from the
# MAGIC earlier notebook and is the cause of the incremental failure — the RESET
# MAGIC cell below removes it.

# COMMAND ----------

print(f"=== VOLUME ROOT: {VOLUME_ROOT} ===")
for f in dbutils.fs.ls(VOLUME_ROOT):
    print(f"  {'DIR ' if f.isDir() else 'FILE'}  {f.name}")

print(f"\n=== SOURCE DIRECTORY: {SOURCE_PATH} ===")
for f in dbutils.fs.ls(SOURCE_PATH):
    size = "" if f.isDir() else f"  ({f.size:,} bytes)"
    print(f"  {'DIR ' if f.isDir() else 'FILE'}  {f.name}{size}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. RESET — destructive, run once
# MAGIC
# MAGIC Drops the target table **and** deletes Auto Loader's state together.
# MAGIC
# MAGIC They must go together:
# MAGIC - table dropped, checkpoint kept → empty table that never refills
# MAGIC - checkpoint cleared, table kept → every row loaded twice
# MAGIC
# MAGIC Your CSV files are not touched.

# COMMAND ----------

spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{TARGET_SCHEMA}")
spark.sql(f"DROP TABLE IF EXISTS {TARGET_TABLE}")
print(f"dropped  {TARGET_TABLE}")

# Remove state wherever a previous notebook may have put it.
_candidates = ["_schema", "_checkpoint", "schema", "checkpoint",
               "_schemas", "_checkpoints", "schemaLocation"]

for parent in [VOLUME_ROOT, SOURCE_PATH]:
    for name in _candidates:
        path = f"{parent}/{name}"
        try:
            if dbutils.fs.rm(path, True):
                print(f"removed  {path}")
        except Exception:
            pass

print(f"\nsource directory now contains:")
for f in dbutils.fs.ls(SOURCE_PATH):
    print(f"  {'DIR ' if f.isDir() else 'FILE'}  {f.name}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. INGEST
# MAGIC Run for the initial load and for every incremental load afterwards.

# COMMAND ----------

bronze_df = (
    spark.readStream
        .format("cloudFiles")
        .option("cloudFiles.format", "csv")
        .option("cloudFiles.schemaLocation", SCHEMA_PATH)
        # Without this, every CSV column is typed as STRING.
        .option("cloudFiles.inferColumnTypes", "true")
        # New columns in later files are added to the table rather than
        # being dropped into _rescued_data.
        .option("cloudFiles.schemaEvolutionMode", "addNewColumns")
        .option("header", "true")
        .load(SOURCE_PATH)
)

# COMMAND ----------

query = (
    bronze_df.writeStream
        .format("delta")
        .outputMode("append")
        .option("checkpointLocation", CHECKPOINT_PATH)
        # Process every file available right now, then stop.
        # Omit this and the stream runs forever and the cell never exits.
        .trigger(availableNow=True)
        .toTable(TARGET_TABLE)
)

# Block until the batch completes so the cell exits cleanly.
# Without this the cell appears to hang, whichever trigger is used.
query.awaitTermination()

print("ingestion complete")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. VERIFY

# COMMAND ----------

display(spark.sql(f"SELECT COUNT(*) AS row_count FROM {TARGET_TABLE}"))

# COMMAND ----------

display(spark.sql(f"DESCRIBE TABLE {TARGET_TABLE}"))

# COMMAND ----------

# Values that did not fit the inferred schema are captured here rather than
# failing the run. A non-zero count means malformed source records.
display(spark.sql(f"""
    SELECT COUNT(*) AS rescued_rows
    FROM {TARGET_TABLE}
    WHERE _rescued_data IS NOT NULL
"""))

# COMMAND ----------

display(spark.sql(f"SELECT * FROM {TARGET_TABLE} LIMIT 20"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Incremental load procedure
# MAGIC
# MAGIC 1. Upload a new CSV into `transactions_source`.
# MAGIC 2. Run **3. INGEST**, then **4. VERIFY**.
# MAGIC 3. The row count rises by exactly that file's row count.
# MAGIC
# MAGIC Do not run RESET again. Do not re-upload an already-processed file under a
# MAGIC new name — Auto Loader tracks files by path, so a renamed copy is treated
# MAGIC as new data and its rows are inserted a second time.
