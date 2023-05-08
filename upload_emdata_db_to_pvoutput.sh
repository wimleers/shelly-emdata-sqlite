#!/usr/bin/env bash
set -e

# NAME
#     upload_emdata_db_to_pvoutput.sh - Upload energy meter data to PVOutput.
#
# SYNOPSIS
#     Uploads EMData from the local emdata.sqlite DB's PVOutput view.
#     Assumes each of the 3 phases must be uploaded to distinct PVOutput
#     systems.
#
# DESCRIPTION
#     Only tested with the Shelly Pro 3EM.


if [ $# -eq 0 ]
  then
    echo "No arguments supplied"
fi

if [[ -z "${PVO_APIKEY}" ]]; then
  echo "The PVO_APIKEY environment variable must be set."
  exit 1
else
  KEY="${PVO_APIKEY}"
fi

if [[ -z "${PVO_SID_PHASE_A}" ]]; then
  echo "The PVO_SID_PHASE_A environment variable must be set."
  exit 1
else
  SID_A="${PVO_SID_PHASE_A}"
fi

if [[ -z "${PVO_SID_PHASE_B}" ]]; then
  echo "The PVO_SID_PHASE_B environment variable must be set."
  exit 1
else
  SID_B="${PVO_SID_PHASE_B}"
fi

# TODO C

# Default: 30 — if donator, you can increase this to 100.
BATCH_SIZE="${PVO_BATCH_SIZE:-30}"

UPLOAD_ROW_COUNT=$(sqlite3 emdata.sqlite "SELECT MIN(COUNT(*), $BATCH_SIZE) FROM pvoutput WHERE PVOutput = 0 LIMIT $BATCH_SIZE;")
FIRST_UPLOAD_ROW_DATETIME=$(sqlite3 emdata.sqlite "SELECT datetime(MIN(timestamp), 'unixepoch', 'localtime') FROM (SELECT * FROM pvoutput WHERE PVOutput = 0 ORDER BY timestamp ASC LIMIT $BATCH_SIZE)")
LAST_UPLOAD_ROW_DATETIME=$(sqlite3 emdata.sqlite "SELECT datetime(MAX(timestamp), 'unixepoch', 'localtime') FROM (SELECT * FROM pvoutput WHERE PVOutput = 0 ORDER BY timestamp ASC LIMIT $BATCH_SIZE)")
echo "🤖 Uploading $UPLOAD_ROW_COUNT rows to PVOutput, ranging from ${FIRST_UPLOAD_ROW_DATETIME} to ${LAST_UPLOAD_ROW_DATETIME}…"

if [[ $UPLOAD_ROW_COUNT -eq 0 ]]
then
  echo "😴 Nothing to do."
  exit 0
fi

# Upload next batch for phase A (total energy on "A") to PVOutput.
# @see https://pvoutput.org/help/api_specification.html#add-batch-status-service
NEXT_BATCH_A=$(sqlite3 emdata.sqlite "SELECT date,time,a_total_act_energy FROM pvoutput WHERE PVOutput = 0 ORDER BY timestamp ASC LIMIT $BATCH_SIZE;" | awk -F '|' '{printf "%s,%s,,,%s;", $1, $2, $3}')
curl --silent \
  --include \
  --header "X-Pvoutput-Apikey: $KEY" \
  --header "X-Pvoutput-SystemId: $SID_A" \
  --data "c1=1&data=$NEXT_BATCH_A" \
  https://pvoutput.org/service/r2/addbatchstatus.jsp \
  -o /dev/null -w '   A: %{http_code}\n' -s
# Upload next batch for phase B to PVOutput.
NEXT_BATCH_B=$(sqlite3 emdata.sqlite "SELECT date,time,b_total_act_energy FROM pvoutput WHERE PVOutput = 0 ORDER BY timestamp ASC LIMIT $BATCH_SIZE;" | awk -F '|' '{printf "%s,%s,,,%s;", $1, $2, $3}')
curl --silent \
  --include \
  --header "X-Pvoutput-Apikey: $KEY" \
  --header "X-Pvoutput-SystemId: $SID_B" \
  --data "c1=1&data=$NEXT_BATCH_B" \
  https://pvoutput.org/service/r2/addbatchstatus.jsp \
  -o /dev/null -w '   B: %{http_code}\n' -s
# Mark this batch as done.
sqlite3 emdata.sqlite "UPDATE emdata SET PVoutput = 1 FROM (SELECT timestamp FROM pvoutput WHERE PVOutput = 0 ORDER BY timestamp ASC LIMIT $BATCH_SIZE) AS v WHERE emdata.timestamp = v.timestamp;"
echo "✅ Done."
