# Section 11 — Databricks Genie Space

## What it is

Genie is a natural-language interface over your data. A user asks in plain
English; Genie generates SQL, runs it, and returns the answer plus the SQL it
wrote. No dashboard, no query authoring — just questions.

Setup: Genie → New → pick the tables / views / metric views to expose → Create.

## The choice that matters: what you point it at

The tutorial feeds Genie the **raw gold tables** (fact_sales + the dim views),
explicitly "to show its capabilities" — i.e. to watch it generate SQL from
scratch. That is instructive, but it is the harder, weaker setup:

- Genie must **guess** which tables to join, on which keys, what "revenue" means,
  and which words map to which columns — every time.
- To make it reliable, the tutor then hand-builds, inside the Genie config:
  - **Joins** tab — the join conditions ("in production-ready Genie spaces we
    always specify the joining condition")
  - **SQL expressions** — measures and dimensions with synonyms
  - **Instructions** — plain-English rules
  - **Example queries** — canned SQL for common questions

That is the metric view, rebuilt by hand inside Genie.

### Recommended for this project: point Genie at the METRIC VIEW

Genie can be built on `retail_q.retail_semantic.retail_metrics` directly. Then
it **inherits** the joins, the single definition of revenue, and the synonyms
already declared in section 9 — nothing to guess, little to configure.

Two reasons it is the better choice here:

1. The modelling work is already done; don't redo it in a second place.
2. The metric view already **excludes** the null customer fields, so Genie
   cannot be handed a dead question about customers.

The transferable principle: **Genie's answer quality equals the quality of the
knowledge layer beneath it.** A good semantic model makes natural-language
querying trustworthy for free; raw tables make Genie improvise.

## The Genie config tabs

| Tab              | Purpose                                                      |
| ---------------- | ------------------------------------------------------------ |
| Description      | what the space is (AI-drafted, editable)                     |
| Sample questions | the starter questions users see on first open                |
| Data             | the tables / views / metric views exposed                    |
| Instructions     | plain-English guidance: tone, abbreviations, business rules  |
| Joins            | explicit join conditions (always set these for raw tables)   |
| SQL expressions  | reusable measures/dimensions + synonyms (a mini metric view) |
| Example SQL      | question → SQL shortcuts for frequent asks                   |
| Monitoring       | history of questions asked                                   |
| Benchmarking     | question → expected answer/SQL, to TEST the space's accuracy |

## Benchmarking — the part worth noting

Benchmarking turns Genie from a demo into something you can evaluate: you supply
a question and the expected SQL/answer, and test whether the space gets it right.
This is how a natural-language layer is QA'd — the same way you would test any
other interface. Worth a mention in the summary as evidence you think about
correctness, not just capability.

## For THIS project — ask what the data supports

Good questions (real data behind them):

- Which category / brand makes the most revenue?
- How has revenue trended by month?
- Which payment mode or sales channel drives the most sales?
- Average transaction value by product segment?

Avoid (null opportunity columns):

- Which customer buys the most? / revenue by country / by industry
- Breakdown by opportunity stage
  These read the empty opportunity-side columns and return nothing useful.

## Databricks One / Databricks Genie (section 12)

A simplified, business-user UI that surfaces dashboards and Genie spaces without
the full workspace. Same underlying objects, cleaner front door for non-technical
consumers. Nothing new to build.
