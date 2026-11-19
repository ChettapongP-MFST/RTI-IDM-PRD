# Production 08 — Sample Data

> **Status:** ✅ Ready

Production-format sample CSV files for end-to-end pipeline testing — pipe-delimited, **no header**, 15-minute intervals, fixed-width amounts, `INTRADAY_SUMMARY_YYYYMMDD_HHMM_HHMM.CSV` naming (uppercase `.CSV`). Drop these into ADLS Gen2 to exercise the **event trigger** ([Production 06](../06-event-trigger/)) and the **interval scheduler** ([Production 07](../07-interval-scheduler/)).

**Prerequisite:** [Production 07 — Interval Scheduler](../07-interval-scheduler/)

| Setting | Value |
|---|---|
| Generator | `scripts/generate_sample_data.py` |
| Output folder | `resources/prd_datasets/` |
| Storage account | `mockadlsidimdprd001` |
| Container | `inflowoutflow` |
| Upload folder | `inbound/statement/` |
| Default generator sample range | **2026-07-01 .. 2026-07-10** (90 files, 9 intervals/day) |
| Interval window | `09:45` → `12:00` (15-min) |
| File-name time zone | **Bangkok / ICT (UTC+7)** |

---

## Additional mock set - November 19-20, 2026

Full-day **30-minute** production-format CSVs are available in [resources/prd_datasets](../../resources/prd_datasets/). This matches the latest overnight-refresh filename examples; it does not change the existing 15-minute generators or older samples.

Download/extract the [November 19-20 half-hour CSV bundle](../../resources/INTRADAY_SUMMARY_20261119_20261120_30min.zip), or select the `INTRADAY_SUMMARY_20261119_*.CSV` and `INTRADAY_SUMMARY_20261120_*.CSV` files from the local data folder.

| Date (Bangkok / ICT) | Files | Data rows | Coverage |
| --- | --- | --- | --- |
| 2026-11-19 | 48 | 612 | `00:00-00:30` through `23:30-24:00` |
| 2026-11-20 | 48 | 568 | `00:00-00:30` through `23:30-24:00` |
| **Total** | **96** | **1,180** | Two complete days |

These files use the exact [Bronze ingestion column order](../01-eventhouse-kql-tables/kql/01-create-DepositMovement.kql):

```text
Date|Time|Product|Channel|Channel_Group|Credit_Amount|Debit_Amount|Net_Amount|Credit_Transaction|Debit_Transaction|Total_Transaction
```

The line above describes the schema only: the actual CSV files have **no header**, use pipe separators, and contain **11 fields** per row. The ingestion pipeline adds the four system/lineage columns.

- Amounts are width-18, right-aligned, with two decimal places. Channels are space-padded to four characters.
- `Net_Amount = Credit_Amount - Debit_Amount` exactly, including negative net outflows.
- `Total_Transaction = Credit_Transaction + Debit_Transaction`.
- Rows are sorted by Product and Channel, with one row per active combination per half-hour.
- The set reuses the date-seeded production mock model in [generate_prd_mock.py](../../resources/datasets/generate_prd_mock.py), combining adjacent 15-minute buckets and recomputing net from cent-rounded credit/debit amounts.
- These are synthetic baseline files, not adjusted before/after variants or a guarantee of any particular Activator alert level.

### Files for the November 20 02:30 refresh test

The bundle includes each of the six selected files exactly once:

```text
INTRADAY_SUMMARY_20261119_2300_2330.CSV
INTRADAY_SUMMARY_20261119_2330_2400.CSV
INTRADAY_SUMMARY_20261120_0000_0030.CSV
INTRADAY_SUMMARY_20261120_0030_0100.CSV
INTRADAY_SUMMARY_20261120_0100_0130.CSV
INTRADAY_SUMMARY_20261120_0130_0200.CSV
```

The separate `0200_0230` and `0230_0300` files also exist for normal ingestion testing; they are not added to the six-file replacement scope.

See the [02:30 refresh guide](../ChangeRequest01/05-data-pipeline/README.md) for controlled testing. Upload **extracted CSVs**, not the ZIP, through the approved storage connection. To simulate arrival timing, upload only the intervals due at that point rather than all future-day files at once. Generation did not upload or ingest anything.

---

## P8.0 — File format

Each file holds the rows for **one 15-minute interval**. Pipe-delimited, no header, one row per `(Product, Channel)` that had activity in that window, sorted by `(Product, Channel)`.

```
2026-07-01|09:45-10:00|C|BC  |Online|        3524282.67|        2305657.80|        1218624.87|183|89|272
```

| # | Column | Example | Notes |
|---|---|---|---|
| 1 | Date | `2026-07-01` | `yyyy-MM-dd` |
| 2 | Interval | `09:45-10:00` | `HH:mm-HH:mm`, 15-min window (ICT) |
| 3 | Product | `C` | Single-letter product code (`C`, `L`, `S`) |
| 4 | Channel | `BC  ` | 4-char code, **left-justified, space-padded** |
| 5 | Status | `Online` | Derived from channel (`ATM`/`POS`/`TELL` → `Offline`, else `Online`) |
| 6 | TotalAmt | `        3524282.67` | THB, **width-18 right-aligned**, `= InflowAmt + OutflowAmt` |
| 7 | InflowAmt | `        2305657.80` | Credit amount (the larger share) |
| 8 | OutflowAmt | `        1218624.87` | Debit amount |
| 9 | InflowCnt | `183` | Credit transaction count |
| 10 | OutflowCnt | `89` | Debit transaction count |
| 11 | TotalCnt | `272` | `= InflowCnt + OutflowCnt` |

**Invariants** (must hold for every row): `TotalAmt = InflowAmt + OutflowAmt` and `TotalCnt = InflowCnt + OutflowCnt`.

---

## P8.1 — Generate the data

```powershell
python "production/08-sample-data/scripts/generate_sample_data.py"
```

The run is **seeded** (`SEED = 20260701`), so output is reproducible. To change the date range or interval window, edit the constants at the top of the script (`START_DATE`, `END_DATE`, `DAY_START_HHMM`, `DAY_END_HHMM`, `ROWS_MIN`, `ROWS_MAX`).

Output (written to `resources/prd_datasets/`):

```
INTRADAY_SUMMARY_20260701_0945_1000.CSV
INTRADAY_SUMMARY_20260701_1000_1015.CSV
...
INTRADAY_SUMMARY_20260710_1145_1200.CSV
```

The generator derives its **product → channel universe** and per-channel amount magnitudes from the existing `2026-06-15` / `2026-06-30` samples, so new files are statistically consistent with the originals.

---

## P8.2 — Upload to ADLS Gen2 (drive a test)

Upload the files into `inflowoutflow/inbound/statement/` to trigger ingestion. The scheduler matches on **today's** date, so use a date that matches `convertFromUtc(utcNow(), 'SE Asia Standard Time', 'yyyyMMdd')` if you want the interval scheduler to pick them up; the event trigger fires on **any** new blob regardless of date.

```powershell
$acct = "mockadlsidimdprd001"
$container = "inflowoutflow"
$prefix = "inbound/statement"
$src = "resources/prd_datasets"
$day = "20260701"   # change to the day you want to replay

$key = az storage account keys list -n $acct --query "[0].value" -o tsv
Get-ChildItem "$src/INTRADAY_SUMMARY_${day}_*.CSV" | ForEach-Object {
    az storage blob upload `
        --account-name $acct --account-key $key `
        --container-name $container `
        --name "$prefix/$($_.Name)" `
        --file $_.FullName --overwrite true | Out-Null
    Write-Host "uploaded $($_.Name)"
}
```

> Prefer **managed identity / `--auth-mode login`** over account keys where your environment allows it.

---

## Exit criteria

- [x] `scripts/generate_sample_data.py` produces valid production-format CSVs.
- [x] 90 files for `2026-07-01 .. 2026-07-10` exist in `resources/prd_datasets/`.
- [ ] Files uploaded to `inbound/statement/` are ingested by the event trigger / scheduler.
- [ ] `dbo.ProcessedFiles` shows one `Success` row per uploaded file; re-uploads log `Skipped-Duplicate`.

---

**Prerequisite:** [Production 07 — Interval Scheduler](../07-interval-scheduler/) · **Next:** [Production 09 — Data Activator Alerts](../09-activator-alerts/) · **Back to:** [Production overview](../)
