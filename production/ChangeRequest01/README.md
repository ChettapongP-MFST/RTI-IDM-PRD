# Change Request 01 - 24/7 Ingestion and Overnight Correction

## Customer start here - modify the existing solution

Follow these **two existing customer documents in order**. They modify the existing solution, add one 02:30 correction child, and reuse normal discovery/ingestion unchanged.

| Order | Instructions |
| --- | --- |
| 1 | [05 - Prepare required objects and create the six-file refresh child](05-data-pipeline/README.md) |
| 2 | [07 - Modify the existing scheduler, configure 24/7, test, and activate](07-interval-scheduler/README.md) |

No EWI deployment, `pl_CR01_*` controller, CLI commands, or old test artifacts are prerequisites for this customer path. Keep scheduling disabled until the complete change is accepted.

## Earlier 03:30 design - engineering reference only

> **Deployment distinction:** This page and its original generated pipeline definitions describe the earlier 03:30 design in `RTI-IDM-PRD`, including stored EWI. For the current `RTI-IDM-PRD2` deployment, whose inspected database has no EWI objects and only the summary MV, use the [revised 02:30 guide](05-data-pipeline/README.md). Do not import the old EWI-dependent pipeline unchanged or create optional EWI objects merely to satisfy its dependencies.

**Current scheduler instructions:** [Document 07](07-interval-scheduler/README.md) now contains the final 24/7 and daily-correction routing; it replaces the previous scheduling-only walkthrough.

**Revised daily correction requirement:** [Create `pl_refresh_DepositMovement_0230`](05-data-pipeline/README.md) for the six specified overnight files. This is separate from the older 03:30 correction design below.

**Flow comparison:** [Original vs CR01 diagram](FLOW-COMPARISON.md) ([SVG](FLOW-COMPARISON.svg)).

> **Earlier design only:** the [older Fabric UI guide](FABRIC-UI-GUIDE.md) and [activity reference](UI-ACTIVITY-REFERENCE.md) describe all-new 03:30 CR01 pipelines, not the current existing-scheduler customer change.
>
> This page remains the technical design/recovery runbook. Its automation section is an optional engineering alternative, not a prerequisite for UI authoring.

> **Historical deployment:** Separate CR01 pipelines were created in `RTI-IDM-PRD`.
> **Recorded historical blockers:** that workspace's source returned ADLS `Forbidden` and its EWI reference contained duplicate keys. Its CR01 activation remained disabled; do not assume these findings describe `RTI-IDM-PRD2`.
> Existing pipeline definitions, schedules, deposit records, and audit entries are not changed by deployment.
> See [live validation evidence](TEST-RESULTS.md) for what was actually tested and what remains blocked.

## 1. Business contract

This technical runbook is for the Fabric engineer/operator implementing CR01.

| Requirement | CR01 behavior |
| --- | --- |
| Normal ingestion | Every **30 minutes, 24/7**, Bangkok / ICT (UTC+7) |
| Correction cycle | The first successful controller cycle at or after **03:30 ICT** |
| Replacement scope | Filename business intervals in **[previous day 22:30, current day 03:30)** |
| Filename date | The actual calendar date of the interval, not the following morning's batch date |
| Selection basis | Business interval in the filename, **not** `load_ts` or storage last-modified time |
| Concurrency | Serialize correction and normal dispatch; no competing event/manual/EWI writer |
| Following correction | Reconcile all outputs, then run normal discovery and resume normal ingestion |
| Source finalization | The producer must have finalized the overnight files before replacement is approved |

**30-minute scheduling does not change the source-file interval.** The deployed parameters default to the existing **15-minute feed** (20 overnight files). Set the source interval to `30` only if the producer confirms a 30-minute feed (10 overnight files), as illustrated by the supplied screenshot. Mixed/overlapping interval conventions require investigation, not automatic acceptance.

### Example: correction associated with 2026-11-18 03:30 ICT

| Filename interval | Treatment |
| --- | --- |
| `20261117_2200_2230` | Outside correction |
| `20261117_2230_2300` | Included for a 30-minute feed |
| `20261117_2330_2400` | Included; `2400` is midnight at the end of November 17 |
| `20261118_0000_0030` | Included |
| `20261118_0300_0330` | Included |
| `20261118_0330_0400` | Normal ingestion, not overnight replacement |

For a 15-minute feed, the same five-hour window ends with `20261118_0315_0330`. Do not select all records from both dates: daytime records must remain unchanged.

## 2. New pipelines and reuse

All changes are separate CR01 artifacts. [deployment.json](deployment.json) records their live IDs and the disabled schedule.

| Pipeline | Purpose |
| --- | --- |
| [pl_CR01_DepositMovement_24x7](pipeline/pl_CR01_DepositMovement_24x7.json) | New 30-minute controller; global serialization, due-date recovery, correction first, normal dispatch second |
| [pl_CR01_DepositMovement_Discover](pipeline/pl_CR01_DepositMovement_Discover.json) | New discovery wrapper for today's and yesterday's files |
| [pl_CR01_DepositMovement_OvernightRefresh](pipeline/pl_CR01_DepositMovement_OvernightRefresh.json) | New controlled staging/replacement/reconciliation workflow |
| [pl_CR01_Preflight](pipeline/pl_CR01_Preflight.json) | Read-only checks of source listing, Warehouse audit access, and KQL schema access |
| [Isolated refresh test](pipeline/pl_CR01_IsolatedRefreshTest.json) | Synthetic-data validation in a unique `CR01Test_*` namespace; not a production ingestion entry point |
| [Isolated SQL control test](pipeline/pl_CR01_SQLControlTest.json) | Native Fabric Script/Lookup validation of owner binding, manifest creation, audit superseding, and commit using test-only Warehouse tables |

**Reused without modification:**

- `pl_ingest_DepositMovement` remains the single-file child for **normal** ingestion.
- Its existing ADLS connection, CSV format, ordinal mapping, lineage-column conventions, and Warehouse/KQL bindings are reused.
- The new discovery wrapper passes both the basename and the complete event `Subject`, avoiding reliance on empty-string/null fallback behavior.
- The existing discovery pipeline is **not modified or used as the new controller**. Its live definition scans today only, so invoking it unchanged would not provide the required previous-date catch-up.
- Existing Silver/Gold function definitions are not changed.

The overnight refresh cannot simply invoke the old child again: a current `Success` audit entry would skip an adjusted file. Instead, it reuses the Copy configuration in a **new staging activity**, then promotes that frozen version after scoped deletion. It preserves old audit entries as `Superseded-CR01`.

```text
New 24/7 controller - every 30 minutes, no operating-hours gate
    |
    +-- acquire one create-only KQL controller lock
    |
    +-- finish due daily corrections, oldest first
    |      source files -> frozen KQL staging -> validate/backup
    |      -> replace manifest-selected Bronze/Silver rows
    |      -> rebuild both dependent MVs -> recalculate both EWI dates
    |
    +-- new today+yesterday discovery
    |      -> existing single-file ingestion pipeline, unchanged
    |
    +-- append normal EWI buckets -> publish readiness -> release lock
```

Only the controller is scheduled. Do not schedule the internal discovery or correction pipelines separately.

## 3. Preflight and no-go conditions

Before any production activation:

1. Open the [live workspace](https://app.fabric.microsoft.com/groups/f0cb703b-2ceb-4a73-a302-813057c06412/list?experience=fabric-developer).
2. Verify the three production CR01 pipelines and their IDs against [deployment.json](deployment.json).
3. Keep the controller schedule **disabled** and both activation parameters **false**.
4. Run `pl_CR01_Preflight`. All three activities must succeed.
5. Confirm the source interval, filename date convention, and producer finalization SLA.
6. Confirm all required overnight files exist, including explicit zero-row files where that is the producer's contract.
7. Freeze schema, reference-data, and function changes during replacement.
8. Confirm KQL database-admin permissions for scoped deletion and MV reconstruction, Warehouse DML/DDL permissions, and source access through the approved network path.
9. Estimate staging, backup, unrelated-row fingerprint, and full-MV-backfill cost on production volume.

### Current storage blocker

The live preflight was run **inside Fabric**, using the same source connection as the existing pipeline, and failed with ADLS `AuthorizationFailure` / `Forbidden`.

Read-only inspection found:

- Storage public network access: **Disabled**.
- The existing source connection uses **OAuth2**.
- The inspected resource-instance rules do not contain this Fabric workspace.

Authentication to Fabric is working; this is a source connectivity/authorization blocker. A network/storage owner must provide an approved private-access path or an approved connection/network configuration, then rerun the preflight. **Do not enable public access, widen firewall rules, or replace existing connection credentials merely to make a test pass.** No such changes are included here.

### Other mandatory no-go conditions

- Duplicate/missing threshold reference keys. The live table currently has **864 rows, 288 distinct rows, and 288 duplicated business keys**. Each expected `Scope x IndicatorKey x WindowCode x DayType` must have exactly one row. Both controller and refresh validate this before processing.
- An earlier correction is incomplete, a controller lock already exists, or an old writer is still running.
- A required source file is missing or changes size/last-modified time during staging.
- A filename/date/time/typed-measure check fails.
- A source/output schema, Silver transformation, or reviewed Gold definition/policy has changed.
- Preview classification is not row-preserving or disagrees with the holiday reference.
- A required holiday-reference year is absent. In particular, test the December/January boundary: the existing Silver function's execution-year calendar assumptions must not silently misclassify the prior year's overnight rows.
- Any row, amount, classification, unrelated-data, Gold, or persisted-EWI reconciliation fails.

These are explicit failures. They must not be converted into a successful empty batch.

### Current EWI reference blocker

The three copies per threshold key multiply every EWI row three times. This pre-existing production reference data has **not** been changed by CR01.

The reference owner must back up the table, review the 288 distinct rows against the approved calibration, and perform an approved reference reload. Do not select an arbitrary winner for conflicting threshold values or delete reference data as part of a pipeline test. Rerun the cardinality check before cutover:

```kql
EWI_AlertThreshold
| summarize Copies=count() by Scope,IndicatorKey,WindowCode,DayType
| where Copies!=1
```

The expected full reference domain is 288 unique keys. A zero-row result from this query alone does not detect missing keys; the pipeline additionally checks the full expected domain.

## 4. Optional engineering automation

For browser-based creation, follow [the Fabric UI guide](FABRIC-UI-GUIDE.md) instead of this section.

PowerShell 7 and Azure CLI are used by the companion scripts. No packages need installing.

### 4.1 Sign in without changing another session's Azure cache

Use a private, approved local directory outside the repository:

```powershell
$auth = Join-Path $env:LOCALAPPDATA 'CR01-AzureCli'
$env:AZURE_CONFIG_DIR = $auth
az login --tenant MngEnvMCAP545530.onmicrosoft.com --use-device-code
```

Use the approved tenant identity and complete MFA. Do not save tokens, passwords, or Azure CLI cache files in Git.

### 4.2 Generate definitions from read-only live metadata

From the repository root:

```powershell
& '.\production\ChangeRequest01\scripts\New-CR01PipelineDefinitions.ps1' `
    -AzureConfigDirectory $auth
```

The generator reads the existing definitions and live schemas. It creates **local CR01 JSON definitions only**; it never updates an existing Fabric item.

It also captures the [reviewed MV baseline](pipeline/CR01-materialized-view-baseline.json). It stops on unsupported MV options/custom policies rather than silently losing them during reconstruction.

### 4.3 Create the new child pipelines

```powershell
& '.\production\ChangeRequest01\scripts\Deploy-CR01Pipeline.ps1' `
    -DefinitionPath '.\production\ChangeRequest01\pipeline\pl_CR01_DepositMovement_Discover.json' `
    -AzureConfigDirectory $auth

& '.\production\ChangeRequest01\scripts\Deploy-CR01Pipeline.ps1' `
    -DefinitionPath '.\production\ChangeRequest01\pipeline\pl_CR01_DepositMovement_OvernightRefresh.json' `
    -AzureConfigDirectory $auth
```

Record the returned IDs. The create-only deployment script refuses to overwrite an existing pipeline, including an existing CR01 pipeline.

### 4.4 Generate and create the controller

```powershell
& '.\production\ChangeRequest01\scripts\New-CR01PipelineDefinitions.ps1' `
    -AzureConfigDirectory $auth `
    -RefreshPipelineId '<new-refresh-pipeline-id>' `
    -DiscoveryPipelineId '<new-discovery-pipeline-id>'

& '.\production\ChangeRequest01\scripts\Deploy-CR01Pipeline.ps1' `
    -DefinitionPath '.\production\ChangeRequest01\pipeline\pl_CR01_DepositMovement_24x7.json' `
    -AzureConfigDirectory $auth
```

For the already-created live CR01 items, do not repeat create operations. Their IDs are in [deployment.json](deployment.json). A reviewed definition can be imported into **that new CR01 item only**. Never import it over either original pipeline.

### 4.5 Prepare consumer gating

Run the two commands in [01-create-CR01-serving-gates.kql](kql/01-create-CR01-serving-gates.kql) separately. They create the readiness table and summary gate without requiring EWI. Only deployments that already use the corresponding EWI objects also run [the stored-table gate](kql/02-create-CR01-stored-serving-gate.kql) or [the query-function gate](kql/03-create-CR01-function-serving-gate.kql). Skip both optional scripts in PRD2.

Before cutover, move relevant consumers to the appropriate gate:

| Consumer | New source |
| --- | --- |
| Function-based EWI alerts/digest, only if deployed | `CR01_EarlyWarning_Latest()` from the optional script |
| Persisted-table EWI alerts/digest, only if deployed | `CR01_EarlyWarning_StoredLatest()` from the optional script |
| Product/channel summary requiring a maintenance-safe query | `CR01_Summary_Product_Channel_Alert()` |

The controller publishes readiness only after successful correction, normal ingestion, and EWI persistence. EWI gates return **only the latest closed 30-minute bucket**, including the previous date's last bucket at midnight. Recalculating history must not replay old alerts/digests.

The summary gate aggregates Bronze directly so its name binding does not fail while the old MV is temporarily absent. This has a query-cost trade-off. Consumers that remain bound directly to a dropped MV can see temporary query failures; do not claim zero-downtime MV availability.

## 5. Production cutover

Do this only after the storage preflight and acceptance tests pass and the maintenance change is approved.

1. Disable old scheduled/event-driven dispatch and independent EWI append jobs **at their trigger/schedule level**. This does not require modifying either old pipeline definition.
2. Drain existing ingestion and EWI jobs through Fabric Monitor. Include already-submitted queued ingestion; a momentarily stable row count is not proof of quiescence.
3. Restrict operational/manual ingestion to the new controller. Direct runs of the unchanged old child bypass the CR01 mutex and are not safe during correction.
4. Complete consumer gating/notification maintenance arrangements.
5. Verify the transactional Silver update policy is enabled and sourced from Bronze. The existing policy script disables Bronze streaming ingestion; query-visible completion must be verified, not assumed from Copy success.
6. Review controller parameters:

   | Parameter | Deployment default | Cutover setting |
   | --- | --- | --- |
   | `pEnableProcessing` | `false` | `true` only after approval |
   | `pCutoverConfirmed` | `false` | `true` only after old writers/consumers are coordinated |
   | `pFirstRefreshDate` | Empty | First approved correction date, `yyyy-MM-dd` |
   | `pSourceFinalized` | `false` | `true` only under the confirmed producer finalization contract |
   | `pSourceIntervalMinutes` | `15` | `15` or `30`, matching the feed |

7. Persist these approved defaults on the **new controller**, or configure equivalent execution parameters. A schedule uses the configured defaults; enabling a schedule while defaults remain disabled cannot start ingestion.
8. Run one supervised controller cycle. Inspect every correction/discovery/child run and all verification stages.
9. Enable the **new controller's** 30-minute schedule, Bangkok time, for all hours and all days.
10. Record the schedule end date and its renewal owner. The disabled schedule created for this deployment expires on **2027-11-18**; provider schedule expiry is an operational renewal requirement, not a business-hours restriction.

If existing old dispatch cannot be disabled/coordinated, stop here. A new mutex cannot protect against an old writer that does not acquire it.

## 6. What the 03:30 correction does

### 6.1 Select the due date and hold exclusive ownership

The controller freezes ICT time once, acquires the create-only KQL table `CR01_ControllerLock`, and records an owner in the new Warehouse control tables.

- Before 03:30, the latest due correction date is yesterday.
- At/after 03:30, today's correction becomes due.
- Start from the first approved correction date, then process every uncompleted date in order.
- A delayed 03:30 run therefore catches up at 04:00 or later.
- An incomplete correction is never silently skipped so that normal ingestion can continue.

The lock is **not** a `ProcessedFiles` lookup or an unenforced Warehouse primary key. A second `.set` of the same KQL lock table is rejected. It has no automatic expiry: failures remain locked until recovery is explicitly completed.

### 6.2 Generate a durable, complete filename manifest

The new SQL control schema is in [01-create-CR01-control.sql](sql/01-create-CR01-control.sql).

The refresh creates exactly 20 filenames for 15-minute input, or 10 for 30-minute input. It stores the manifest in `dbo.CR01RefreshManifest` and validates already-loaded overnight files against it.

Missing expected files, duplicate/mixed interval conventions, or ambiguous legacy filenames are not a reason to delete a smaller, rediscovered subset.

### 6.3 Freeze the corrected source version before deleting data

For each manifest file, in parallel batches of up to 10:

1. Read source size and last-modified time.
2. Copy the file to the date-specific `CR01_Stage_yyyyMMdd` KQL table.
3. Use the existing pipe/no-header/15-column mapping convention.
4. Capture Copy row counts and source metadata in the manifest.
5. Wait until all staged rows are query-visible and match each file's expected count.
6. Validate typed measures and filename/business date/time agreement.
7. Preview the existing Silver transformation using a **new tabular-input CR01 preview function**; validate row preservation, classification status, reference years, and holiday flags.
8. Recheck source size/last-modified time. A changed source fails before deletion.

The subsequent promotion reads **the frozen staged KQL rows**, not the mutable source blobs again. Size/last-modified checks are not a substitute for the producer finalization contract or a cryptographic source-version manifest.

The new staging Copy has no automatic retry. A partial failed stage must not be blindly appended again.

### 6.4 Back up and replace the exact scope

Before destructive work, the refresh:

- Validates the reviewed definitions/policies of **both** dependent MVs.
- Creates date-specific backups of target Bronze and Silver rows.
- Backs up persisted EWI rows for both complete business dates.
- Captures multiset fingerprints of unrelated Bronze and Silver records.
- Holds serving readiness false.

It then:

1. Drops both dependent MVs:
   - `mv_Summary_Product_Channel_Alert`, sourced from Bronze.
   - `mv_EarlyWarning_Base`, sourced from Silver; this additional live MV still exists even though the latest EWI function reads Silver directly.
2. Deletes Bronze and Silver rows using **literal, manifest-selected filenames**. Kusto's restricted delete-query syntax is why this step does not use a query-derived `let`/`mv-expand` predicate.
3. Verifies the replacement scope is empty.
4. Copies old successful audit entries to `dbo.CR01AuditBefore`, then marks them `Superseded-CR01`; no audit history is erased.
5. Promotes the frozen staging snapshot into Bronze.
6. Lets the existing transactional update policy produce new Silver rows.
7. Waits for Bronze and Silver to match the staged **business-row multiset**, not merely their total row counts.

Correctness gates inspect the **synchronous ingest-from-query command results** for nonempty mismatch output. They do not use `.show table` row statistics, which can lag behind newly ingested check rows.

Lineage belongs to the new correction pipeline/run. The source filename remains unchanged.

### 6.5 Rebuild all derived results and commit

The refresh:

1. Verifies that unrelated Bronze/Silver multisets are unchanged and target Silver rows are classified.
2. Recreates both MVs with the reviewed definitions and restores the supported explicit cache policy.
3. Reconciles every MV result against its corrected source and checks MV health.
4. Replaces persisted EWI results for **both complete business dates**, because cumulative/velocity/share-jump values can change beyond the replaced buckets.
5. Compares stored EWI output with recomputed values, ignoring only evaluation timestamp `Alert_Time`.
6. Writes one new `Success` audit entry per manifest file and marks the correction `Completed` only after verification.

**Observed live EWI schema difference:** the existing physical table has an `int` alert rank and fewer columns than the function output. The new pipelines explicitly project to the existing physical schema and safely convert the validated L0-L3 rank to `int`. They do not alter the existing function/table or silently assume the latest README schema is already deployed.

Finally, the controller runs ordinary discovery, appends normal EWI buckets, publishes readiness, completes its owner record, and releases the lock.

## 7. Failure recovery and rollback

### Always do this first

1. Keep the new schedule disabled/suspended.
2. Keep competing writers stopped and consumer gating in place.
3. Inspect the failed activity, `dbo.CR01RefreshRun`, `dbo.CR01RefreshManifest`, owner record, retained lock, and date-specific KQL objects.
4. Preserve the original manifest and frozen stage. Do not create a new correction identity against partially replaced data.
5. Never delete the controller lock just to make the next scheduled run green.

### Recovery choices

| Failure point | Required action |
| --- | --- |
| Before any deposit deletion | Fix the precondition; verify production rows/audits remain unchanged. Review/archive partial CR01 objects before an explicitly approved restart. |
| After deletion or partial promotion | Keep serving blocked. Use the frozen stage/backups to establish exactly one version of every manifest file; clean partial replacement rows before a retry. |
| After source replacement, during MV/EWI rebuilding | Do not re-copy source data. Complete the failed derived-data stage from corrected Bronze/Silver, then repeat all reconciliations. |
| During SQL audit/commit | Inspect the transaction and exact audit identities. Do not assume failure means no insert occurred. Retain prior audit history. |
| Missing/changed source | Do not shrink the manifest or resume normal dispatch. Obtain an approved finalized source version or restore the original state. |

### Restoring the previous version

Under exclusive ownership and an approved maintenance operation:

1. Confirm all required backups are readable and record the exact original update policy/MV definitions before changing anything.
2. Keep/drop the affected MVs as appropriate for restoration.
3. Temporarily disable the Silver update policy **using its captured original definition with `IsEnabled=false`**.
4. Remove only manifest-selected partial replacement rows from Bronze and Silver.
5. Restore the exact Bronze and Silver backups. Disabling the policy prevents a second derived copy of Silver during restoration.
6. Restore the original update policy and validate it.
7. Rebuild the MVs and restore the backed-up EWI rows for the affected dates, removing partial corrected-date snapshots first.
8. Preserve new failed/rolled-back audit history; reverse superseding only for audit identities captured in `CR01AuditBefore`.
9. Verify all source and derived multisets/amounts, and explicitly reconcile the Warehouse checkpoint before releasing the lock or restoring readiness.

There is **no** one-click automatic rollback across KQL, Warehouse, and Fabric Copy. Retention/recoverability alone is not a backup or an undo command for this procedure. Automated blind retries are deliberately not enabled.

## 8. Validation and operator checks

### Scoped live invariants

```powershell
& '.\production\ChangeRequest01\scripts\Test-CR01LiveInvariants.ps1' `
    -AzureConfigDirectory $auth `
    -EvidencePath (Join-Path $env:TEMP 'cr01-invariants.json')
```

This executes the **actual manifest SQL** against the Warehouse for 15-/30-minute feeds, midnight, year change, and leap day. It checks the actual due-date/catch-up SQL and incomplete-refresh guard against one uniquely named temporary SQL table, and tests the create-only lock on one temporary KQL table. Both temporary objects are removed. Optional original snapshots can also prove the old pipeline definitions are unchanged. Production data is not changed.

### Isolated live data-plane test

```powershell
$testManifest = Join-Path $env:TEMP 'cr01-isolated-manifest.json'
& '.\production\ChangeRequest01\scripts\New-CR01IsolatedTest.ps1' `
    -AzureConfigDirectory $auth -ManifestPath $testManifest
```

Create the new test pipeline once with the create-only deployer, then use [Invoke-CR01PipelineTest.ps1](scripts/Invoke-CR01PipelineTest.ps1) to publish/run **that CR01 test item only** and record its activity evidence.

The synthetic fixture changes two overnight files across midnight while retaining an unrelated daytime row. It uses an isolated threshold snapshot with **identical full-row duplicates removed**; production reference data remains untouched, and conflicting keys still fail validation. It exercises a deliberate negative-verifier case, classification, scoped deletes, frozen replay, both MVs, and persisted EWI. Expected results include:

- Bronze and Silver: **3 rows each**, corrected total net **195 Baht**.
- Both Gold MVs: reconcile with corrected source and are healthy.
- Stored EWI: **72 rows**, matching recomputed values.
- Latest total-bank cumulative EWI: **0.000085 MB** for the prior date and **0.000110 MB** for the current date, within `1e-12 MB` numerical tolerance.
- Unrelated source-row multisets unchanged.

The fixture uses November 17-18, 2026 and the corresponding reference data. Update/review the fixture and reference coverage before using it as a different-year regression suite.

Clean up the exact test objects from the saved manifest:

```powershell
& '.\production\ChangeRequest01\scripts\Remove-CR01IsolatedTestObjects.ps1' `
    -ManifestPath $testManifest -AzureConfigDirectory $auth -WhatIf
# Review the exact namespace, then repeat without -WhatIf and confirm.
```

This does not delete the reusable test pipeline or touch production data.

### Isolated Warehouse control test

Use [New-CR01SqlTest.ps1](scripts/New-CR01SqlTest.ps1) to generate a test-only SQL namespace and save its cleanup manifest. Create/publish the corresponding `pl_CR01_SQLControlTest`, then run it with [Invoke-CR01PipelineTest.ps1](scripts/Invoke-CR01PipelineTest.ps1).

It reuses the actual refresh SQL and linked service, tests bound owner parameters, generates the full filename manifest, preserves/supersedes a previous success, and commits the replacement audit/checkpoint. The success path removes its own test tables. On failure, review the saved manifest and use the same scoped cleanup helper. It never writes to the original `dbo.ProcessedFiles`.

Warehouse source timestamps use `DATETIME2(6)` and six fractional digits, matching Fabric Warehouse's supported storage precision.

### Remaining production acceptance gates

- [ ] Source preflight passes through the approved private/network path.
- [ ] The reference owner has corrected duplicate threshold keys and the complete 288-key contract passes.
- [ ] A supervised real-CSV staging/Copy run passes with the confirmed feed interval.
- [ ] Old dispatch and independent EWI writers are coordinated; no overlapping submitted jobs remain.
- [ ] Consumer gates prevent historical notification replay and tolerate maintenance visibility.
- [ ] A delayed/missed 03:30 run and incomplete-run recovery are exercised in the approved environment.
- [ ] Failure injection covers partial Copy, post-deletion interruption, and audit-write failure.
- [ ] Production-volume MV reconstruction and fingerprints fit the approved SLA/capacity budget.
- [ ] Source/reference changes and December/January classification behavior are approved.
- [ ] The final production cutover and first correction date are approved.

### Daily checks after activation

- Verify each due correction has exactly one `Completed` record and no overdue/incomplete date.
- Verify no stale controller lock/owner exists after a successful cycle.
- Monitor preflight/access failures, new files versus successful audit entries, source freshness, and queued ingestion.
- Verify Silver classification exceptions and Bronze/Silver reconciliation.
- Check both MVs, persisted-EWI reconciliation, publish readiness, and latest closed-bucket alert freshness.
- Retain backups, manifests, definitions, and logs for the approved rollback period. Cleanup must name the exact completed-run objects; do not use database-wide clears or broad deletion.
- Assign an owner to schedule renewal and CR01 backup/table-metadata housekeeping.

## 9. References

- [Existing ingestion design](../05-data-pipeline/README.md)
- [Existing scheduler documentation](../07-interval-scheduler/README.md)
- [Silver update policy](../03-silver-deposit-movement-classified/kql/03-enable-update-policy.kql)
- [Fabric pipeline REST API and activity monitoring](https://learn.microsoft.com/fabric/data-factory/pipeline-rest-api)
- [Fabric pipeline activity/resource limits](https://learn.microsoft.com/fabric/data-factory/data-factory-limitations)
- [KQL activity](https://learn.microsoft.com/fabric/data-factory/kql-activity)
