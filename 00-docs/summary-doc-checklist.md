# Summary document — running checklist

Points to make sure the final project summary covers. Added as they come up
during the build.

## Concepts to explain, with the diagrams already produced

- **Lakeflow taxonomy** — Lakeflow is the umbrella; Connect (ingestion),
  Declarative Pipelines (ETL, formerly DLT) and Jobs (orchestration, formerly
  Workflows) are its three components. Auto Loader is *not* a Lakeflow
  component — it is a Spark data source (`cloudFiles`) written in code and run
  inside a notebook or an ETL pipeline. Connect and Auto Loader are
  alternatives for the ingestion step, chosen by source type, not layers.
  → `lakeflow-taxonomy.png`

- **Three ingestion patterns, deliberately chosen** — managed CDC connector
  (PostgreSQL), managed SaaS connector (Salesforce), file ingestion
  (Auto Loader). These are the three archetypes found in real platforms.
  → `architecture.png`

- **Attribute vs measure** — why `unit_price` sits on `dim_product` while
  `selling_price` sits on `fact_sales`, and the three-question test that
  decides it. → `attribute-vs-measure.png`

- **SCD type 1 vs type 2** — same source change, two target behaviours,
  decided by one toggle. Includes the `__END_AT IS NULL` querying rule.
  → `scd-type1-vs-type2.png`

- **Auto Loader mechanics** — checkpoint and schema sidecar folders hold all
  state; trigger modes; `_rescued_data`; why `awaitTermination()` is needed.
  → `autoloader-mechanics.png`

- **Gold star schema** — grain, keys, source lineage.
  → `gold-star-schema.png`

## Trade-offs and decisions to state explicitly

- **Watermark-based incremental extraction, not log-based CDC.** Deletes in
  PostgreSQL are not propagated, and rows updated without bumping the cursor
  column are missed. Salesforce avoids this via `IsDeleted` soft deletes.

- **SCD type 2 applied at the bronze layer** rather than downstream. This is
  what the managed connector offers and is internally consistent, but it means
  bronze is not a pure raw landing copy. Differs from the textbook medallion
  pattern.

- **Natural keys used as dimension primary keys** rather than surrogate keys.
  Common in lakehouse models; differs from classic Kimball.

- **Scope boundary: Salesforce `Opportunity` and PostgreSQL `inventory` are
  ingested but not modelled.** Opportunity has a different grain and lifecycle
  from a completed sale; inventory is properly a periodic snapshot fact, not a
  dimension. Stated as a deliberate decision, with both listed as planned
  extensions.

- **AI-assisted development was reviewed, not trusted.** Generated Auto Loader
  code was functional but did not terminate, and the settings most likely to be
  wrong are the ones that look fine and behave badly — trigger mode, checkpoint
  location, schema options.

## Fixes made to the tutorial's own artifacts

- Source `INSERT` statements used positional inserts with no column list,
  placing a timestamp in a boolean column and integers in `VARCHAR` primary
  keys. Rewritten with explicit column lists and defects relocated to non-key
  columns so the data-quality test rows can actually exist alongside a primary
  key — which the managed connector requires for change tracking.

## Data quality — how the rules were arrived at

Worth making explicitly in the summary, because it is a judgement point rather
than a mechanic.

- **Structural vs semantic rules.** An AI reading a schema can propose
  structural rules (not null, length, positive value, enum membership). It
  cannot infer semantic rules — a Closed Won opportunity must have a close date
  in the past, discount may not exceed a threshold without approval, a
  transaction must reference a product active on that date. Those come from the
  business.

- **The action is always a business decision.** `expect` vs `expect_or_drop` vs
  `expect_or_fail` encodes organisational tolerance for bad data. An AI has no
  basis to choose, so an AI-chosen action is ungrounded even when it is
  plausible.

- **AI-generated rules are descriptive, not prescriptive.** They describe the
  data that happens to be present rather than what the business requires. A
  rule derived from a requirement exists before the bad data does, which is the
  point of having it.

- **Order used:** profile with AI to surface anomalies → validate with the data
  owner, who assigns the action for each rule → generate the implementation →
  review every line before running. AI is used twice and decides nothing.

- **Artifact to include: a data quality register** — table, column, rule,
  action, owner, rationale. Makes expectations auditable: when someone asks why
  records are being dropped, the answer is a row with a name against it.
