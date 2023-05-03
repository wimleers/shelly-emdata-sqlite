# `shelly-emdata-sqlite`
Sync Shelly [EMData](https://shelly-api-docs.shelly.cloud/gen2/ComponentsAndServices/EMData/#csv-file-download) to a SQLite DB for:

- **permanent storage** (due to storage limitations, Shelly devices only keep it for a limited time, e.g. [60 days for the Pro 3EM](https://www.shelly.cloud/en/products/shop/pro-3-em))
- **querying/understanding** (the built-in dashboard is rather limited)

And optionally upload it to [PVOutput](https://pvoutput.org).

## Download energy meter data from Shelly: `download_shelly_emdata_to_db.sh`

- Downloads `emdata` from the given Shelly device ID.
- Assumes mDNS is on.
- Keeps all downloaded CSV files in a `csv` directory (meaning the DB can be reconstructed later and there is a flat file format backup).
- Stores it in `emdata.sqlite`.
- Provides helpful views to simplify querying.

_Only tested with the Shelly Pro 3EM._

### Usage

```
SHELLY_DEVICE_ID=A8FA8FA8FA8F sh download_shelly_emdata_to_db.sh 
````

Expected output:

```
🤖 Updating DB.
📈 Existing rows: 19616 rows
⌚️ Last row: 2023-05-03 07:00:00.
📥 Downloading data since 1683097260 (2023-05-03 07:01:00) from ShellyPro3EM-A8FA8FA8FA8F.local…
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  261k    0  261k  100    28  62191      6  0:00:04  0:00:04 --:--:-- 65390
💾 Importing…
📈 806 rows imported, 20421 rows in total.
⌚️ Last row: 2023-05-03 20:25:00.
✅ Done.
````

## Upload energy meter data to PVOutput: `upload_emdata_db_to_pvoutput.sh` 

- Uploads EMData from the local `emdata.sqlite` DB's `PVOutput` view.
- Assumes each of the 3 phases must be uploaded to distinct PVOutput systems.

_Only tested with the Shelly Pro 3EM._

### Usage

```
$ PVO_APIKEY=foo PVO_SYSID_PHASE_A=1234 PVO_SYSID_PHASE_B=2345 sh upload_emdata_db_to_pvoutput.sh 
````

(Specify `BATCH_SIZE=100` [if you are a donator](https://pvoutput.org/help/donations.html#add-batch-status).)

Expected output:

```
$ PVO_APIKEY=foo PVO_SYSID_PHASE_A=1234 PVO_SYSID_PHASE_B=2345 sh upload_emdata_db_to_pvoutput.sh 
🤖 Uploading 30 rows to PVOutput, ranging from 2023-05-03 07:55:00 to 2023-05-03 10:20:00…
   A: 200
   B: 200
✅ Done.
````
