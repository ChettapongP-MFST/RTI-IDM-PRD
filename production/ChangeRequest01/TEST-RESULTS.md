# CR01 - Live Validation Results

Date: **2026-11-18**. Target: `RTI-IDM-PRD`.

**For setup instructions:** use the [Fabric UI step-by-step guide](FABRIC-UI-GUIDE.md) and [UI activity reference](UI-ACTIVITY-REFERENCE.md). This page records runtime validation; it is not the authoring walkthrough.

**Production activation: BLOCKED.** The new controller schedule remains disabled; no real deposit records, production audit entries, original pipeline definitions, original schedules, or production threshold rows were replaced.

## Deployment

The three new production pipeline definitions were retrieved from Fabric and compared structurally with the delivered JSON: **all match**.

| New production pipeline | Live item ID |
| --- | --- |
| `pl_CR01_DepositMovement_24x7` | `87c40325-c483-43d9-8eb7-1b2617487def` |
| `pl_CR01_DepositMovement_Discover` | `8eb0f5ee-39f9-4c2b-839f-4656554657f3` |
| `pl_CR01_DepositMovement_OvernightRefresh` | `4149a248-7145-4776-8734-79c9c76bb305` |

The new schedule is every **30 minutes**, Bangkok time, all hours, **disabled**. See [deployment.json](deployment.json) for all production/test IDs and schedule expiry.

## Accepted checks

| Check | Result | Evidence |
| --- | --- | --- |
| Requested tenant authentication and workspace access | Passed | Workspace, KQL, and Warehouse accessed using the requested tenant identity |
| Actual manifest SQL: 30-minute feed | Passed | Exactly 10 expected filenames in `[previous 22:30, current 03:30)` |
| Actual manifest SQL: 15-minute feed | Passed | Exactly 20 expected filenames |
| Midnight / `2400`, January 1, leap day | Passed | Exact filename-set comparisons against live Warehouse query output |
| Actual due-date SQL | Passed | Before 03:30, exactly 03:30, delayed 04:00, oldest missed-date catch-up |
| Incomplete correction | Passed | Actual SQL throws error `51106`; normal processing is blocked |
| Global mutex primitive | Passed | Second create-only acquisition rejected; first owner remained unchanged; temporary lock removed |
| Original pipeline definitions | Passed | Both originals equal their pre-change snapshots |
| Original discovery schedule | Passed | Equal to its pre-change snapshot |
| New controller activation guard | Passed | Expected rejection before processing when disabled |
| New refresh finalization guard | Passed | Expected rejection before replacement without producer finalization |
| Isolated Warehouse control pipeline | Passed | 9 successful activities; 20 new successes, 1 superseded success, 1 archived entry, 1 completed checkpoint; test tables removed |
| Exact isolated backend replacement checks | Passed | 39 remaining KQL stages executed with synchronous mismatch-result assertions, including final counts and amounts |
| Full isolated Fabric data-plane pipeline | Passed | 85 successful activities; negative verifier and independent exact post-run checks passed |
| Runtime schema guards | Passed | All three actual KQL schema-check commands returned no mismatches |
| Staging mapping | Passed | Actual date-specific test table mapping contains 15 columns |
| New serving gates | Passed | Three functions compile and return no rows before readiness; production Bronze baseline remains 1,421 rows |
| Cleanup scope rejection | Passed | A manifest targeting original `dbo.ProcessedFiles` was rejected before authentication |
| PowerShell / JSON validation | Passed | All companion scripts parse; all delivered JSON parses |

The live-invariants suite contains **14 successful assertions**. Its temporary SQL/KQL objects are removed by the test.

### Isolated SQL control run

- Pipeline: `pl_CR01_SQLControlTest`.
- Job: `cbd02eb9-e5c5-4898-9cad-241567b1a3fc`.
- Status: **Completed**.
- UTC: `2026-11-18 09:07:43` to `09:09:52`.
- Exercises the actual Script activity parameter binding, manifest registration, SQL transaction/audit superseding, and verified commit logic against uniquely named test tables.

### Isolated correction fixture and exact acceptance values

- Two corrected overnight files across November 17/18, plus an unrelated daytime row.
- A unique `CR01Test_*` namespace; no writes to original deposit tables.
- Reference snapshot uses the **288 distinct full rows** from the existing reference. Production reference duplicates are not removed.
- Expected Bronze/Silver: **3 / 3 rows**.
- Expected total net: **195 Baht**.
- Expected persisted EWI: **72 rows**, unique by object/bucket.
- Expected last total-bank cumulative values: **0.000085 MB** and **0.000110 MB**; tolerance `1e-12 MB`.
- Unrelated source-row multisets, both reconstructed MVs, classification, and persisted EWI are checked.
- A deliberate nonempty mismatch verifies that the check mechanism detects a failure. Correctness gates use synchronous command results, **not lagging table row statistics**.

### Accepted full data-plane run

- Pipeline: `pl_CR01_IsolatedRefreshTest`.
- Job: `0f5d0472-dc26-4551-8959-35095ae9216d`.
- Status: **Completed**, **85 successful activities**, no failed activities.
- UTC: `2026-11-18 09:48:58` to `09:58:54`.
- The deliberate mismatch emitted nonempty command output; the final acceptance query emitted **no mismatch rows**.
- An independent query after completion confirmed **3 Bronze rows, 3 Silver rows, 195 Baht net, 72 stored EWI rows, 288 isolated threshold rows, and zero duplicate EWI object/bucket keys**.

Preliminary completed statuses were not accepted as proof. Exact post-run checks exposed lagging table statistics and the pre-existing production threshold duplication. The verifier was corrected, the reference fixture was isolated, and the fresh full run above passed both pipeline and independent data checks.

### Cleanup

The exact isolated KQL objects and SQL fixture tables were removed using their saved namespace manifests. Cleanup verified that dropped objects were absent. The reusable test pipelines and their run histories remain available; their next run should be generated/published with a fresh test namespace.

## Production blockers - not bypassed

### 1. Source storage access

- Fabric preflight job `010f5325-0156-422c-8529-b0b41047798f` failed on ADLS listing with `AuthorizationFailure` / `Forbidden`.
- The Warehouse and KQL preflight activities succeeded.
- Storage public network access is **Disabled**. The inspected resource-instance rules do not include this workspace; the existing source connection uses OAuth2.
- No firewall, network-access, credentials, or RBAC settings were changed.

An approved source connection/private-access configuration must pass the real Fabric preflight before production Copy or cutover.

### 2. Threshold reference cardinality

Read-only production checks found:

| Measure | Actual | Required |
| --- | --- | --- |
| Reference rows | 864 | 288 unique business keys |
| Distinct full rows | 288 | 288 reviewed rows |
| Duplicated business keys | 288 | 0 |

The actual controller reference-check predicate returns **288 invalid keys**. Three identical reference copies multiply EWI output threefold. Production reference data remains unchanged; the owner must review/back up/correct it before activation.

## Production baseline preserved

| Object | Before | Verified after scoped testing |
| --- | --- | --- |
| Bronze deposit rows | 1,421 | 1,421 |
| Silver classified rows | 1,421 | 1,421 |
| Persisted production EWI rows | 0 | 0 |
| Production threshold rows | 864 | 864 |
| Original successful audit entries | 165 | 165 |
| Original skipped-duplicate audit entries | 1 | 1 |

## Not claimed as tested or activated

- Real-CSV Copy/staging through the blocked source network path.
- Replacement of an actual production overnight batch.
- Production-volume backfill/fingerprint SLA or a continuously running 24/7 service.
- Integrated post-deletion crash recovery/rollback or real alert delivery.
- Final consumer/old-writer cutover and annual-reference compatibility approval.

Use the [runbook](README.md) for the remaining acceptance gates, recovery procedure, and activation steps.
