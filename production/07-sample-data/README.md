# Production 07 — Sample Data

> **Status:** ✅ Ready

Production-format sample CSV files for end-to-end pipeline testing — pipe-delimited, **no header**, 15-minute intervals, fixed-width amounts, `INTRADAY_SUMMARY_YYYYMMDD_HHMM_HHMM.CSV` naming (uppercase `.CSV`). Drop these into ADLS Gen2 to exercise the **event trigger** ([Production 05](../05-event-trigger/)) and the **interval scheduler** ([Production 06](../06-interval-scheduler/)).

**Prerequisite:** [Production 06 — Interval Scheduler](../06-interval-scheduler/)

| Setting | Value |
|---|---|
| Generator | `scripts/generate_sample_data.py` |
| Output folder | `resources/prd_datasets/` |
| Storage account | `mockadlsidimdprd001` |
| Container | `inflowoutflow` |
| Upload folder | `inbound/statement/` |
| Current sample range | **2026-07-01 .. 2026-07-10** (90 files, 9 intervals/day) |
| Interval window | `09:45` → `12:00` (15-min) |
| File-name time zone | **Bangkok / ICT (UTC+7)** |

---

## P7.0 — File format

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

## P7.1 — Generate the data

```powershell
python "production/07-sample-data/scripts/generate_sample_data.py"
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

## P7.2 — Upload to ADLS Gen2 (drive a test)

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

**Prerequisite:** [Production 06 — Interval Scheduler](../06-interval-scheduler/) · **Back to:** [Production overview](../)
