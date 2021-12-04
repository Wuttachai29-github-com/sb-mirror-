#!/bin/sh
URL=${MIRROR_URL:-"sponsor.ajay.app"} # download from main mirror if none specified
MIRROR_DIR=${MIRROR_DIR:-"/mirror"}
EXPORT_DIR=${EXPORT_DIR:-"/export"}
mkdir -p "${MIRROR_DIR}"/ "${EXPORT_DIR}"/

# helper function
validate_file() {
  FILENAME=$1
  COLS=$(head -n1 "$FILENAME" | awk 'BEGIN{FS=","}END{print NF}')
  awk -F, -v COLS="$COLS" 'NF==COLS {print > "tmp.csv"} NF<COLS {print >> "bad.csv"}' "$FILENAME"
  mv tmp.csv "$FILENAME"
}

download() {
  curl -sL https://git.io/sb-dbapi-license -o "$MIRROR_DIR"/licence.md
  echo "Downloading from $URL"
  if [ -n "$MIRROR_URL" ]; then rsync -rztvP --zc=lz4 --append --contimeout=10 rsync://"$URL"/sponsorblock "${MIRROR_DIR}"
  else # downloading from main mirror
    # get filenames
    curl -sL https://sponsor.ajay.app/database.json?generate=false -o response.json
    DUMP_DATE=$(jq .lastUpdated < response.json)
    # set $@ since posix doesn't have named variables
    set -- $(jq -r .links[].table < response.json)
    rm response.json

    for table in "$@"
    do
      echo "Downloading $table.csv"
      rsync -ztvP --zc=lz4 --append --contimeout=10 rsync://sponsor.ajay.app/sponsorblock/"${table}"_"${DUMP_DATE}".csv ${MIRROR_DIR}/${table}.csv ||
        curl -L https://sponsor.ajay.app/database/"${table}".csv -o ${MIRROR_DIR}/"${table}".csv # fallback to CURL if rsync times out
    done
    date -d@"$(echo "$DUMP_DATE" | cut -c 1-10)" +%F_%H-%M > "${MIRROR_DIR}"/lastUpdate.txt
  fi
}

validate() {
  echo "Validating Downloads"
  for file in "${MIRROR_DIR}"/*.csv
  do validate_file "$file"; done
}

convert_sqlite() {
  echo "Starting SQLite Conversion"
  rm -f -- "${EXPORT_DIR}"/SponsorTimes.db
  curl -sL https://sponsor.ajay.app/download/sponsorTimes.db -o "${EXPORT_DIR}"/SponsorTimesDB.db

  for file in "${MIRROR_DIR}"/*.csv; do
    filename=$(basename "$file" .csv)
    sqlite3 -separator ',' "${EXPORT_DIR}"/SponsorTimesDB.db ".import --skip 1 $file ${filename}" 
  done
}

download
# if NO_VALIDATE, skip validation
if [ -z "$NO_VALIDATE" ]; then validate; fi
# if SQLITE, merge all csvs into one .db file
if [ -n "$SQLITE" ]; then convert_sqlite; fi