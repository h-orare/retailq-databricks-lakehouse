# Extension ideas

Deliberately out of scope for the build. Collected as we go, to be worked
through independently after the tutorial is complete.

## 1. `fact_inventory` — a second fact table
The Postgres `inventory` table is ingested but not modelled. Stock level per
product per store per day is a **periodic snapshot fact**, not a dimension.
Building it would:
- close the gap between the stated business problem ("insight into sales,
  customers, products and inventory") and the delivered star schema
- demonstrate **conformed dimensions** — two fact tables sharing `dim_product`
  and `dim_calendar`, which is what makes a set of stars a warehouse

## 2. Metadata-driven ingestion framework
Replace one notebook per file source with a single parameterised notebook plus
a config table of `source_path`, `format`, `target_table`, `trigger`. Adding a
source becomes an insert rather than a code change. Parameters passed via job
parameters or `dbutils.widgets`.

Answers the interview question "how would this scale to twenty sources?"

## 3. `fact_opportunity`
Salesforce `Opportunity` is ingested but not modelled. Pipeline data has a
different grain and lifecycle from completed sales — properly an
**accumulating snapshot fact** tracking a deal through its stages.
