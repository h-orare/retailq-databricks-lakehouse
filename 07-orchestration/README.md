# Section 13 — Orchestration with Databricks Jobs

A **Job** is the orchestrator. It runs multiple **tasks** in dependency order,
on a schedule, with retries and alerting. Create: Jobs & Pipelines → Job.

## The DAG: retailq_end_to_end

| #   | Task                 | Type                                  | Depends on |
| --- | -------------------- | ------------------------------------- | ---------- |
| 1   | postgres_to_bronze   | Ingestion pipeline (Lakeflow Connect) | —          |
| 2   | salesforce_to_bronze | Ingestion pipeline                    | task 1 \*  |
| 3   | blob_to_bronze       | Notebook (Auto Loader)                | task 2 \*  |
| 4   | silver_and_gold      | ETL pipeline (declarative)            | task 3     |
| 5   | dashboard_refresh    | Dashboard                             | task 4     |

\* **Serial only because of a free-edition limit** — one ingestion pipeline at a
time. The three bronze ingests are independent; in production they run in
**parallel**, all feeding `silver_and_gold`. Worth stating this in the summary:
the serial chain is a platform constraint, not the intended design.

Task types used: three of Databricks' task types appear here — **pipeline**
(Lakeflow Connect ingestion and the declarative ETL), **notebook** (Auto Loader),
and **dashboard** (refresh). Others exist: SQL, Python wheel, dbt, Spark submit,
another job, if/else conditions.

## Dependencies

A dependency ("depends on" + "run if upstream succeeded") is what makes it a DAG.
Remove it and tasks start together and run in parallel. The links can be set by
hand; Databricks also infers some automatically from what you select.

## What the job refreshes — and what it does NOT

This is the key conceptual payoff of the whole project:

| Object        | Kind               | Refreshed by the job?           |
| ------------- | ------------------ | ------------------------------- |
| bronze tables | streaming tables   | yes — the ingestion tasks       |
| silver tables | streaming / MV     | yes — the ETL task              |
| fact_sales    | materialised table | yes — the ETL task              |
| gold dim\_\*  | **views**          | no — computed at query time     |
| metric view   | **view**           | no — computed at query time     |
| Genie space   | reads views        | no — live                       |
| dashboard     | cached result      | **yes — explicit refresh task** |

Rule: **stored objects (tables) must be rebuilt; views are live and need no
refresh.** The dashboard is the one consumption object that caches its result,
so it needs its own refresh task — everything else downstream (metric view,
Genie) reads fresh at query time.

## Job settings

| Setting        | Notes                                                                |
| -------------- | -------------------------------------------------------------------- |
| Compute        | serverless here; a task can override                                 |
| Retries        | default 4 per task; configurable                                     |
| Trigger        | manual · scheduled (cron) · file arrival · table update · continuous |
| Job parameters | pass values in at run time (not used here)                           |
| Notifications  | email on start / success / failure / duration / stream backlog       |
| Git            | version the job definition + code                                    |

### Triggers in full

- **Scheduled** — fixed times; simple interval or a cron expression for advanced
  cadences ("every 3rd weekday at 06:00"). Most common.
- **File arrival** — run when a new file lands in a location (pairs naturally
  with Auto Loader).
- **Table update** — run when an upstream table changes.
- **Continuous** — one run starts as the last finishes. For near-real-time;
  expensive — avoid on the trial.

### Retries and idempotency

Default 4 retries is safe here **because every task is idempotent**:
declarative pipelines and Auto Loader use checkpoints, so a re-run never
double-loads. Confirm idempotency before trusting retries on any new task.

### Repair run (not shown in the tutorial, but examinable)

If a job fails partway, a **Repair run** re-executes only the FAILED and
downstream tasks, reusing the successful ones — not the whole DAG. This is the
standard recovery pattern and is DE Associate content.

## Cautions for the trial

1. **A schedule spends credits every run.** Run manually, or schedule → capture
   one clean successful run for the portfolio → then REMOVE the schedule. A
   daily job left running after you stop watching drains credits silently.
2. **Capture the run.** Screenshot the successful run DAG (green tasks) into
   `../06-serving/screenshots/` — it is the single most resume-worthy image in
   the project. Export the job definition (JSON / YAML) into this folder too.

## Exam relevance — heavy

- **Jobs / Workflows** orchestration, multi-task DAGs, task dependencies
- **Task types** (notebook, pipeline, SQL, dbt, another job)
- **Triggers** — scheduled (cron), file arrival, continuous
- **Retries**, **Repair run** (re-run only failed tasks)
- **Notifications** and failure handling
- **Job clusters vs all-purpose compute** (here: serverless)
