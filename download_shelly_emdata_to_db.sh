#!/usr/bin/env bash
set -e

# NAME
#     download_shelly_emdata_to_db.sh - Download energy meter data from Shelly.
#
# SYNOPSIS
#     Downloads EMData from the given Shelly device ID. Assumes mDNS is on.
#     Keeps all downloaded CSV files in a "csv" directory (meaning the DB
#     can be reconstructed later and there is a flat file format backup).
#     Provides helpful views to simplify querying.
#
# DESCRIPTION
#     Only tested with the Shelly Pro 3EM.

if [[ -z "${SHELLY_DEVICE_ID}" ]]; then
  echo "The SHELLY_DEVICE_ID environment variable must be set."
  exit 1
else
  DEVICE_ID="${SHELLY_DEVICE_ID}"
fi

MDNS_NAME="ShellyPro3EM-$DEVICE_ID"

if [[ -f "emdata.sqlite" ]]
then
  echo "🤖 Updating DB."
  ROW_COUNT_BEFORE=$(sqlite3 emdata.sqlite "SELECT COUNT(*) FROM emdata;")
  LAST_ROW_BEFORE=$(sqlite3 emdata.sqlite "SELECT datetime(MAX(timestamp), 'unixepoch') FROM emdata;")
  LAST_ROW_BEFORE_TIMESTAMP=$(sqlite3 emdata.sqlite "SELECT MAX(timestamp) FROM emdata;")
  LAST_ROW_BEFORE_DATETIME=$(sqlite3 emdata.sqlite "SELECT datetime(MAX(timestamp), 'unixepoch') FROM emdata;")
  echo "📈 Existing rows: $ROW_COUNT_BEFORE rows"
  echo "⌚️ Last row: $LAST_ROW_BEFORE_DATETIME."
  FIRST_NEXT_ROW_TIMESTAMP=$(sqlite3 emdata.sqlite "SELECT MAX(timestamp)+60 FROM emdata;")
  FIRST_NEXT_ROW_DATETIME=$(sqlite3 emdata.sqlite "SELECT datetime(MAX(timestamp)+60, 'unixepoch') FROM emdata;")
  echo "📥 Downloading data since $FIRST_NEXT_ROW_TIMESTAMP ($FIRST_NEXT_ROW_DATETIME) from $MDNS_NAME.local…"
  # Download only once, keep CSV files around, allowing to recreate this!
  if [[ ! -f "csv/emdata_${DEVICE_ID}_${FIRST_NEXT_ROW_TIMESTAMP}.csv" ]]
  then
    curl -OJ -X POST -d "add_keys=false&ts=$FIRST_NEXT_ROW_TIMESTAMP" http://$MDNS_NAME.local/emdata/0/data.csv
    mv "emdata_${DEVICE_ID}_${FIRST_NEXT_ROW_TIMESTAMP}.csv" csv/
  else
    echo "   (already downloaded!)"
  fi
  if [[ -f "csv/emdata_${DEVICE_ID}_${FIRST_NEXT_ROW_TIMESTAMP}.csv" ]]
  then
    echo "💾 Importing…"
    sqlite3 emdata.sqlite <<SQL
.mode csv
.import csv/emdata_${DEVICE_ID}_${FIRST_NEXT_ROW_TIMESTAMP}.csv emdata_raw
INSERT INTO emdata (timestamp, a_total_act_energy, b_total_act_energy, c_total_act_energy) SELECT timestamp, a_total_act_energy, b_total_act_energy, c_total_act_energy FROM emdata_raw;
DELETE FROM emdata_raw;
SQL
    ROW_COUNT_AFTER=$(sqlite3 emdata.sqlite "SELECT COUNT(*) FROM emdata;")
    NET_NEW_ROWS=$(sqlite3 emdata.sqlite "SELECT COUNT(*) FROM emdata WHERE timestamp >=$LAST_ROW_BEFORE_TIMESTAMP;")
    LAST_ROW_AFTER_DATETIME=$(sqlite3 emdata.sqlite "SELECT datetime(MAX(timestamp), 'unixepoch') FROM emdata;")
    echo "📈 $NET_NEW_ROWS rows imported, $ROW_COUNT_AFTER rows in total."
    echo "⌚️ Last row: $LAST_ROW_AFTER_DATETIME."
    echo "✅ Done."
  else
    echo "⚠️  FAILED to download emdata_${DEVICE_ID}_${FIRST_NEXT_ROW_TIMESTAMP}.csv."
    exit 1
  fi
else
  echo "🤖 Creating DB"
  sqlite3 emdata.sqlite <<SQL
CREATE TABLE IF NOT EXISTS "emdata_raw"(
  "timestamp" TEXT, "a_total_act_energy" TEXT, "a_fund_act_energy" TEXT, "a_total_act_ret_energy" TEXT,
  "a_fund_act_ret_energy" TEXT, "a_lag_react_energy" TEXT, "a_lead_react_energy" TEXT, "a_max_act_power" TEXT,
  "a_min_act_power" TEXT, "a_max_aprt_power" TEXT, "a_min_aprt_power" TEXT, "a_max_voltage" TEXT,
  "a_min_voltage" TEXT, "a_avg_voltage" TEXT, "a_max_current" TEXT, "a_min_current" TEXT,
  "a_avg_current" TEXT, "b_total_act_energy" TEXT, "b_fund_act_energy" TEXT, "b_total_act_ret_energy" TEXT,
  "b_fund_act_ret_energy" TEXT, "b_lag_react_energy" TEXT, "b_lead_react_energy" TEXT, "b_max_act_power" TEXT,
  "b_min_act_power" TEXT, "b_max_aprt_power" TEXT, "b_min_aprt_power" TEXT, "b_max_voltage" TEXT,
  "b_min_voltage" TEXT, "b_avg_voltage" TEXT, "b_max_current" TEXT, "b_min_current" TEXT,
  "b_avg_current" TEXT, "c_total_act_energy" TEXT, "c_fund_act_energy" TEXT, "c_total_act_ret_energy" TEXT,
  "c_fund_act_ret_energy" TEXT, "c_lag_react_energy" TEXT, "c_lead_react_energy" TEXT, "c_max_act_power" TEXT,
  "c_min_act_power" TEXT, "c_max_aprt_power" TEXT, "c_min_aprt_power" TEXT, "c_max_voltage" TEXT,
  "c_min_voltage" TEXT, "c_avg_voltage" TEXT, "c_max_current" TEXT, "c_min_current" TEXT,
  "c_avg_current" TEXT, "n_max_current" TEXT, "n_min_current" TEXT,
  "n_avg_current" TEXT
)
SQL
  sqlite3 emdata.sqlite <<SQL
-- Tracking only the 4 pieces of relevant information, to keep DB size small.
CREATE TABLE IF NOT EXISTS emdata (
  timestamp datetime,
  --- 999.999 Wh is the largest value this allows, which is enough for nearly 60 kWh … in a single minute.
  a_total_act_energy DECIMAL(7,4),
  b_total_act_energy DECIMAL(7,4),
  c_total_act_energy DECIMAL(7,4),
  --- … plus tracking whether it's been uploaded to PVOutput.
  PVOutput int(1) DEFAULT 0,
  PRIMARY KEY (timestamp)
);

-- This is equivalent to what /rpc/EMData.GetStatus?id=0 generates, but reconstructed as if it was queried non-stop, precisely at each 5-minute mark.
CREATE VIEW IF NOT EXISTS pvoutput AS
SELECT
  timestamp,
  strftime("%Y%m%d", timestamp, 'unixepoch') date,
  time(timestamp, 'unixepoch') time,
  a_total_act_energy,
  b_total_act_energy,
  c_total_act_energy,
  total_act,
  PVOutput
FROM (
  SELECT
    timestamp,
    SUM(a_total_act_energy) OVER(ORDER BY timestamp) AS a_total_act_energy,
    SUM(b_total_act_energy) OVER(ORDER BY timestamp) AS b_total_act_energy,
    SUM(c_total_act_energy) OVER(ORDER BY timestamp) AS c_total_act_energy,
    SUM(a_total_act_energy + b_total_act_energy + c_total_act_energy) OVER(ORDER BY timestamp) AS total_act,
    PVOutput
  FROM emdata
  ORDER BY timestamp ASC
)
-- The maximum supported resolution by PVOutput is 5 minutes.
WHERE timestamp % 300 = 0;
SQL
  if [ ! -d "csv" ]; then
    mkdir csv
  fi
  echo "📥 Downloading ALL available data from $MDNS_NAME.local…"
  # Download only once, keep CSV files around, allowing to recreate this!
  if [[ ! -f "csv/emdata_${DEVICE_ID}.csv" ]]
  then
    # Download as much as possible.
    curl -OJ -X POST -d "add_keys=false" http://$MDNS_NAME.local/emdata/0/data.csv
    mv "emdata_${DEVICE_ID}.csv" csv/
  else
    echo "   (already downloaded!)"
  fi
  echo "💾 Importing…"
  sqlite3 emdata.sqlite <<SQL
.mode csv
.import csv/emdata_$DEVICE_ID.csv emdata_raw
INSERT INTO emdata (timestamp, a_total_act_energy, b_total_act_energy, c_total_act_energy) SELECT timestamp, a_total_act_energy, b_total_act_energy, c_total_act_energy FROM emdata_raw;
DELETE FROM emdata_raw;
SQL
  ROW_COUNT=$(sqlite3 emdata.sqlite "SELECT COUNT(*) FROM emdata;")
  LAST_ROW_DATETIME=$(sqlite3 emdata.sqlite "SELECT datetime(MAX(timestamp), 'unixepoch') FROM emdata;")
  echo "📈 $ROW_COUNT rows imported."
  echo "⌚️ Last row: $LAST_ROW_DATETIME."
  echo "✅ Done."
fi

