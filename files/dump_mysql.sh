#!/bin/bash
# fail explicitly on various errors
#  from https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -Eeuo pipefail

# From https://stackoverflow.com/a/25515370/788155
yell() { echo "$0: $*" >&2; }
die() { yell "$*"; exit 111; }
try() { "$@" || die "cannot $*"; }

# print self and arguments, if any
ARGS=""
if [[ $# -gt 0 ]] ; then ARGS="with arguments '${@}'"; fi
echo "Starting '${0}' ${ARGS}"

#- dumpdb.sh 0.92.1
## Usage: dumpdb.sh [-d directory] [-f] [-c] [-e] [-h] [-v] [-debug]
##
##       -d <dir> Set dump directory
##       -f       Force regardless of date
##       -c       Compress while dumping (uses less disk at the cost of more CPU/RAM)
##       -e       Enable Extended Insert for large tables (over ${EXTENDED_INSERT_MIN_SIZE} MB)
##       -h       Show help options.
##       -v       Print version info.
##       -debug   Enable debug.
##
## Example:
##
##      dumpdb.sh -cd dump_destination_folder
##
##

# This dump script will create hostname.database.table.sql.gz files which are compressed with
# pigz rsyncable compression. Innodb tables are dumped using --single-transaction.
# There will be server-side configuration files which will allow setting a
# specific database or a database.table to be skipped.
# This was ported from:
# http://stackoverflow.com/questions/10867520/mysqldump-with-db-in-a-separate-file/26292371#26292371
# with some changes to fit our requirements
#

#################################
# Variables, custom and static  #
#################################

# Set variables
DBDUMP_HOME_FOLDER="/var/local/backups"               # This will be set by the config file, and indicates where your db dump control files (and by default, the dumps as well) will live
MINIMUM_AGE_IN_MINUTES=540          # 540 mins = nine hours
EXTENDED_INSERT_MIN_SIZE=200        # in Megabytes before compression
DEBUG=

#################################
# Read configuration file       #
#################################

# the config file needs to set the variable DBDUMP_HOME_FOLDER as indicated above.
# an example would be:
# DBDUMP_HOME_FOLDER="/home/my_backup_home"

source $HOME/.config/dumpdb.sh.config

# Static vars
HOSTNAME="$(hostname -s)"
CURRENT_TIME=""
FILE_TIME=""
MINIMUM_AGE_IN_SECONDS=""
MATCH_TIME=""
MYSQL_DUMP_SWITCHES=" --skip-dump-date --max-allowed-packet=512M "
MYSQL_PUMP_SWITCHES=" --max-allowed-packet=512M "
INNODB_TABLE_DETECTED=""
MYSQL_DUMP_FOLDER="${DBDUMP_HOME_FOLDER}/mysql"
MYSQL_TMP_FOLDER="/mnt/resource/mysql_tmp"
MYSQL_DUMP_SKIP_DATABASES="${DBDUMP_HOME_FOLDER}/dumpdb_excluded_databases.txt"
MYSQL_DUMP_SKIP_TABLES="${DBDUMP_HOME_FOLDER}/dumpdb_excluded_tables"   # .databasename.txt needs to be appended to this
MYSQL_DUMP_BIG_TABLES="${DBDUMP_HOME_FOLDER}/dumpdb_big_tables"         # .databasename.txt needs to be appended to this
ENABLE_EXTENDED_INSERT="false"
COMPRESS_CMD="pigz --rsyncable"
FORCE_IGNORE_TIME="false"
COMPRESS_WHILE_DUMPING="false"
EXCLUDED_DATABASES=()
EXCLUDED_TABLES=()

PRECHECK_DUMP=""
STRUCTURE_DUMP=""
DATA_DUMP=""
COMPRESS_ROUTINE=""
COMPARE_ROUTINE=""

#################################
# Options and help functions    #
#################################

help=$(grep "^## " "${BASH_SOURCE[0]}" | cut -c 4-)
version=$(grep "^#- "  "${BASH_SOURCE[0]}" | cut -c 4-)

opt_debug() {
  DEBUG=1
}

opt_h() {
  echo "$help"
  exit 0
}

opt_v() {
  echo "$version"
  exit 0
}

opt_d() {
  MYSQL_DUMP_FOLDER="${OPTARG}"
}

opt_f() {
  FORCE_IGNORE_TIME="true"
}

opt_c() {
  COMPRESS_WHILE_DUMPING="true"
}

opt_e() {
  ENABLE_EXTENDED_INSERT="true"
}

while getopts "debug:hvd:fce" opt; do
  eval "opt_$opt"
done

if [ -f ${HOME}/.my.cnf ] # if file exists
then
  MYSQL_LOGIN_INFO="${HOME}/.my.cnf"
  MYSQL_DEFAULTS=""
elif [ -f ${HOME}/.mylogin.cnf ] # if file exists
then
  MYSQL_LOGIN_INFO="${HOME}/.mylogin.cnf"
  MYSQL_DEFAULTS=""
else
  MYSQL_LOGIN_INFO="/root/.mylogin.cnf"
  MYSQL_DEFAULTS=" --defaults-extra-file=${MYSQL_LOGIN_INFO}"
fi
# Show source for creds and dump defaults
echo "-- Using login credentials from: ${MYSQL_LOGIN_INFO}"
if [[ ! -z ${MYSQL_DEFAULTS} ]] ; then echo "MYSQL_DEFAULTS = ${MYSQL_DEFAULTS}"; fi

################
# Functions    #
################

# Pipe and concat the head/end with the stoutput of mysqlump ( '-' cat argument)
DUMP_STRUCTURE(){
  if [[ ${COMPRESS_WHILE_DUMPING} == true ]]
  then
    try cat /tmp/sqlhead.sql | ${COMPRESS_CMD} >> "${TEMP_SAVEd_TABLE}.tmp.gz"
    try mysqldump ${MYSQL_DEFAULTS} ${MYSQL_DUMP_SWITCHES} ${BIG_TABLE_SWITCH} ${THIS_DATABASE} ${THIS_TABLE} --no-data | ${COMPRESS_CMD} >> "${TEMP_SAVEd_TABLE}.tmp.gz"
  else
    try cat /tmp/sqlhead.sql > "${TEMP_SAVEd_TABLE}.tmp"
    try mysqldump ${MYSQL_DEFAULTS} ${MYSQL_DUMP_SWITCHES} ${BIG_TABLE_SWITCH} ${THIS_DATABASE} ${THIS_TABLE} --no-data >> "${TEMP_SAVEd_TABLE}.tmp"

  fi
  #try mysqlpump ${MYSQL_DEFAULTS} ${MYSQL_PUMP_SWITCHES} ${THIS_DATABASE} ${THIS_TABLE} --skip-dump-rows | ${COMPRESS_CMD} >> "${TEMP_SAVEd_TABLE}.tmp.gz"
  #try mysqldump ${MYSQL_DEFAULTS} ${MYSQL_DUMP_SWITCHES} --skip-extended-insert ${THIS_DATABASE} ${THIS_TABLE} --no-data | ${COMPRESS_CMD} >> "${TEMP_SAVEd_TABLE}.tmp.gz"
}
DUMP_DATA(){
  if [[ ${COMPRESS_WHILE_DUMPING} == true ]]
  then
    try mysqldump ${MYSQL_DEFAULTS} ${MYSQL_DUMP_SWITCHES} ${BIG_TABLE_SWITCH} ${INNODB_TABLE_DETECTED} ${THIS_DATABASE} ${THIS_TABLE} --no-create-info | ${COMPRESS_CMD} >> "${TEMP_SAVEd_TABLE}.tmp.gz"
    try cat /tmp/sqlend.sql | ${COMPRESS_CMD}>> "${TEMP_SAVEd_TABLE}.tmp.gz"
  else
    #try mysqlpump ${MYSQL_DEFAULTS} ${MYSQL_PUMP_SWITCHES} ${THIS_DATABASE} ${THIS_TABLE} --no-create-info | ${COMPRESS_CMD} >> "${TEMP_SAVEd_TABLE}.tmp.gz"
    #try mysqldump ${MYSQL_DEFAULTS} ${MYSQL_DUMP_SWITCHES} --skip-extended-insert ${THIS_DATABASE} ${THIS_TABLE} --no-create-info | ${COMPRESS_CMD} >> "${TEMP_SAVEd_TABLE}.tmp.gz"
    try mysqldump ${MYSQL_DEFAULTS} ${MYSQL_DUMP_SWITCHES} ${BIG_TABLE_SWITCH} ${INNODB_TABLE_DETECTED} ${THIS_DATABASE} ${THIS_TABLE} --no-create-info >> "${TEMP_SAVEd_TABLE}.tmp"
    try cat /tmp/sqlend.sql >> "${TEMP_SAVEd_TABLE}.tmp"
  fi
}
COMPRESS_DUMP(){
if [[ ${COMPRESS_WHILE_DUMPING} == true ]]
then
  echo "--skipping compress since option '-c' was provided"
else
  try ${COMPRESS_CMD} "${TEMP_SAVEd_TABLE}.tmp"
fi
}
COMPARE_FILES(){
  if [[ -f "${SAVED_TABLE}.sql.gz" ]]
  then
    if ( zcmp "${TEMP_SAVEd_TABLE}.tmp.gz" "${SAVED_TABLE}.sql.gz" )
    then
      echo "-- Identical to previous table dump. Removing temporary file."
      try rm -f "${TEMP_SAVEd_TABLE}.tmp.gz"
    else
      echo "-- Differences found. Overwriting previous table dump."
      try mv -f "${TEMP_SAVEd_TABLE}.tmp.gz" "${SAVED_TABLE}.sql.gz"
    fi
  else
    echo "-- No previous file to compare. Removing tmp extension."
    try mv -f "${TEMP_SAVEd_TABLE}.tmp.gz" "${SAVED_TABLE}.sql.gz"
  fi
}
################
# Begin MAIN   #
################

# Build skip databases array
if [ -f "${MYSQL_DUMP_SKIP_DATABASES}" ] # if file exists
then
  # Read non-whitespace and non-commented lines into array
  IFS=$'\r\n' GLOBIGNORE='*' command eval 'EXCLUDED_DATABASES=($(cat ${MYSQL_DUMP_SKIP_DATABASES} | egrep -v "^[[:space:]]" | awk "!/^ *#/ && NF" ))'
  if (( ${#EXCLUDED_DATABASES[@]} ))    # if not empty
  then
    echo "-- EXCLUDED_DATABASES[@]: ${EXCLUDED_DATABASES[@]}"
  else                                  # if empty
    IGNORED_DATABASES=''
    EXCLUDED_DATABASES=''
  fi
else
  echo "-- File not found: \"${MYSQL_DUMP_SKIP_DATABASES}\""
    IGNORED_DATABASES=''
    EXCLUDED_DATABASES=''
fi

echo "-- STARTING DATABASE DUMP --"

# Ensure dump path exists
if [ ! -d "${MYSQL_DUMP_FOLDER}" ]; then
  printf "\-- Dump folder not found. Attempting to create %s\n" "${MYSQL_DUMP_FOLDER}"
  try mkdir -p "${MYSQL_DUMP_FOLDER}"
  if [ $? -ne 0 ]
  then
    printf "Error: The user launching this script, ${USER}, is unable to create \"${MYSQL_DUMP_FOLDER}\""
    PRECHECK_DUMP="ERROR"
    exit 1
  else
    echo "-- Successfully created folder \"${MYSQL_DUMP_FOLDER}\""
  fi
fi

# Set tmp folder
if [ -d "/mnt/resource" ]; then
  printf "\-- /mnt/resource folder was found. Attempting to create %s\n" "${MYSQL_TMP_FOLDER}"
    mkdir -p "${MYSQL_TMP_FOLDER}"
    if [ $? -ne 0 ]
    then
      printf "Error: The user launching this script, ${USER}, is unable to create \"${MYSQL_TMP_FOLDER}\""
      MYSQL_TMP_FOLDER="${MYSQL_DUMP_FOLDER}"
    else
      # clean stale data
      try rm -rf ${MYSQL_TMP_FOLDER}/*
      ls -lh "${MYSQL_TMP_FOLDER}"
      echo "-- Successfully created and cleaned out folder \"${MYSQL_TMP_FOLDER}\""
    fi
else
  printf "\-- /mnt/resource not found. Using \"${MYSQL_DUMP_FOLDER}\""
  MYSQL_TMP_FOLDER="${MYSQL_DUMP_FOLDER}"
fi

# Test database access or throw error
mysql ${MYSQL_DEFAULTS} -e 'show databases' > /dev/null || \
  {
    printf "Error: cannot read database! %s\n";  \
    PRECHECK_DUMP="ERROR"; exit 1
  }

# Set SQLend string:
echo "SET autocommit=1;SET unique_checks=1;SET foreign_key_checks=1;" > /tmp/sqlend.sql
if [ ! -f /tmp/sqlend.sql ]; then
  printf "Error: The user launching this script, ${USER}, is unable to create /tmp/sqlend.sql. Does it already exist?"
  PRECHECK_DUMP="ERROR"
  exit 1
fi
################################
# Begin loop through databases #
################################
echo "-- Dumping all DB ..."
for THIS_DATABASE in $(mysql ${MYSQL_DEFAULTS} -e 'show databases' -s --skip-column-names);
do
  [ -z "$DEBUG" ] || echo "info: THIS_DATABASE=$THIS_DATABASE"
  # Skip schema & other DBs
  for EXCLUDE_THIS_DATABASE in information_schema mysql phpmyadmin performance_schema sys
  do
    if [ "${THIS_DATABASE}" = "${EXCLUDE_THIS_DATABASE}" ]
    then
      echo "-- Skip - Matches hard-coded exclude list: \"${THIS_DATABASE}\""
      continue 2    # jump back two 'for loops'
    fi
  done
  # Skip specifically excluded DBs
  for EXCLUDE_THAT_DATABASE in "${EXCLUDED_DATABASES[@]}"
  do
    if [ "${THIS_DATABASE}" = "${EXCLUDE_THAT_DATABASE}" ]
    then
      echo "-- Skip - Match found within \"${MYSQL_DUMP_SKIP_DATABASES}\": \"${THIS_DATABASE}\""
    continue 2    # jump back two 'for loops'
    fi
  done

  # Verify exists or create subfolder for database
  if [ ! -d "${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}" ]
  then
    try mkdir -p "${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}"
  fi
  if [ "${MYSQL_DUMP_FOLDER}" != "${MYSQL_TMP_FOLDER}" ]
  then
    try mkdir -p "${MYSQL_TMP_FOLDER}/${THIS_DATABASE}"
  fi

  # Build skip tables array
  if [ -f "${MYSQL_DUMP_SKIP_TABLES}.${THIS_DATABASE}.txt" ] # if file exists
  then
    # Read non-whitespace and non-commented lines into array
    IFS=$'\r\n' GLOBIGNORE='*' command eval  'EXCLUDED_TABLES=($(cat "${MYSQL_DUMP_SKIP_TABLES}.${THIS_DATABASE}.txt" | egrep -v "^[[:space:]]" | awk "!/^ *#/ && NF" ))'
    IGNORED_DATABASE_TABLES=''
    echo "-- EXCLUDED_TABLES array = \"${EXCLUDED_TABLES[@]}\""
    for IGNORE_THIS_TABLE in "${EXCLUDED_TABLES[@]}"
    do :
      IGNORED_DATABASE_TABLES+="${THIS_DATABASE}.${IGNORE_THIS_TABLE} "
    done
    echo "-- IGNORED_DATABASE_TABLES[@] = \"${IGNORED_DATABASE_TABLES}\""
  else                                  # if empty
    IGNORED_DATABASE_TABLES=''
  fi
  [ -z "$DEBUG" ] || echo "info: IGNORED_DATABASE_TABLES=$IGNORED_DATABASE_TABLES"
  # Build big tables array
  if [ -f "${MYSQL_DUMP_BIG_TABLES}.${THIS_DATABASE}.txt" ] # if file exists
  then
    # Read non-whitespace and non-commented lines into array
    IFS=$'\r\n' GLOBIGNORE='*' command eval  'BIG_TABLES=($(cat "${MYSQL_DUMP_BIG_TABLES}.${THIS_DATABASE}.txt" | egrep -v "^[[:space:]]" | awk "!/^ *#/ && NF" ))'
    BIG_DATABASE_TABLES=''
    echo "-- BIG_TABLES array = \"${BIG_TABLES[@]}\""
    for THIS_BIG_TABLE in "${BIG_TABLES[@]}"
    do :
      BIG_DATABASE_TABLES+="${THIS_DATABASE}.${THIS_BIG_TABLE} "
    done
    echo "-- BIG_DATABASE_TABLES[@] = \"${BIG_DATABASE_TABLES}\""
  else                                  # if empty
    BIG_DATABASE_TABLES=''
  fi
  [ -z "$DEBUG" ] || echo "info: BIG_DATABASE_TABLES=$BIG_DATABASE_TABLES"
  ########################
  # Clean up old dumps   #
  ########################
  # Remove old full database dumps
  for extension in "sql.gz" "sql"; do
    if [ -f "${MYSQL_DUMP_FOLDER}/${HOSTNAME}.${THIS_DATABASE}.${extension}" ]
    then
      rm -f "${MYSQL_DUMP_FOLDER}/${HOSTNAME}.${THIS_DATABASE}.${extension}"
      echo "-- deleted \"${MYSQL_DUMP_FOLDER}/${HOSTNAME}.${THIS_DATABASE}.${extension}\""
    fi
  done

  # Set SQLhead string while in loop
  echo "USE ${THIS_DATABASE};SET autocommit=0;SET unique_checks=0;SET foreign_key_checks=0;" > /tmp/sqlhead.sql
  if [ ! -f /tmp/sqlhead.sql ]; then
    printf "Error: The user launching this script, ${USER}, is unable to create /tmp/sqlhead.sql. Does it already exist?"
    exit 1
    PRECHECK_DUMP="ERROR"
  fi

  #############################
  # Begin loop through tables #
  #############################

  # this for loop forces BASE TABLEs to be dumped first followed by VIEWs
  for BASE_OR_VIEW in 'VIEW' 'BASE TABLE'
  do
    [ -z "$DEBUG" ] || echo "mysql ${MYSQL_DEFAULTS} -NBA -D ${THIS_DATABASE} -e \"SHOW FULL TABLES where TABLE_TYPE like '${BASE_OR_VIEW}'\""
  for THIS_TABLE in $(mysql ${MYSQL_DEFAULTS} -NBA -D ${THIS_DATABASE} -e "SHOW FULL TABLES where TABLE_TYPE like '${BASE_OR_VIEW}'"|awk '{print $1}')
  do
    [ -z "$DEBUG" ] || echo "info: THIS_DATABASE.THIS_TABLE=${THIS_DATABASE}.${THIS_TABLE}"
    if [[ ! " ${IGNORED_DATABASE_TABLES[@]} " =~ " ${THIS_DATABASE}.${THIS_TABLE} " ]]
    then
      ############################################
      # Skip if recent dump exists unless forced #
      ############################################
      CURRENT_TIME=$(date +%s)
      if [ -f "${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}.sql.gz" ]
      then
        echo "-- database.table: ${THIS_DATABASE}.${THIS_TABLE}"
        echo "-- about to stat ${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}.sql.gz"
        #ls -lht "${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/"
        ls -l "${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/" | grep "${THIS_TABLE}.sql"
        FILE_TIME=$(stat --format='%Y' "${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}.sql.gz")
      else
        FILE_TIME=0
      fi
      MINIMUM_AGE_IN_SECONDS=$( expr ${MINIMUM_AGE_IN_MINUTES} \* 60 )
      MATCH_TIME=$( expr ${CURRENT_TIME} - ${MINIMUM_AGE_IN_SECONDS} )
      #if [ find ${MYSQL_DUMP_FOLDER}/${THIS_DATABASE} -name ${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}.sql.gz -mmin -${MINIMUM_AGE_IN_MINUTES} |& /dev/null ] && [ "${FORCE_IGNORE_TIME}" = "false" ]
      if [[ ${FILE_TIME} -gt ${MATCH_TIME} ]] && [[ "${FORCE_IGNORE_TIME}" = "false" ]]
      then
        echo "-- Skip - Last dump of \"${THIS_DATABASE}.${THIS_TABLE}\" is newer than ${MINIMUM_AGE_IN_MINUTES} minutes."
        continue
      fi

      #############################################
      # Delete previous and partial table dumps   #
      #############################################
      for extension in "sql" "sql.tmp.gz" "sql.tmp"; do
        if [ -f "${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}.${extension}" ]
        then
          rm -f "${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}.${extension}"
          echo "-- deleted \"${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}.${extension}\""
        fi
      done

      ##############################################
      # Set temp and existing table dump filenames #
      ##############################################
      TEMP_SAVEd_TABLE=${MYSQL_TMP_FOLDER}/${THIS_DATABASE}/${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}
      SAVED_TABLE=${MYSQL_DUMP_FOLDER}/${THIS_DATABASE}/${HOSTNAME}.${THIS_DATABASE}.${THIS_TABLE}

      ############################
      # Set big table parameters #
      ############################

      if [[ " ${BIG_DATABASE_TABLES[@]} " =~ " ${THIS_DATABASE}.${THIS_TABLE} " ]] && ${ENABLE_EXTENDED_INSERT} == true
      then
        echo "-- BIG BIG Table. Using Extended Insert for this dump"
        BIG_TABLE_SWITCH=""
      else
        BIG_TABLE_SWITCH=" --skip-extended-insert "
      fi

      ##########################
      # Identify Innodb tables #
      ##########################
      TABLE_TYPE="$(mysql ${MYSQL_DEFAULTS} -NBA -e "SELECT ENGINE
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_NAME='${THIS_TABLE}'
      AND   TABLE_SCHEMA='${THIS_DATABASE}';")"
      #echo "--Table type: $TABLE_TYPE"

      if [[ $TABLE_TYPE == InnoDB ]]
      then
        echo "-- Innodb table detected"
        INNODB_TABLE_DETECTED=" --single-transaction"
      else
        INNODB_TABLE_DETECTED=""
      fi

      ###################################
      # Call functions, perform dumps   #
      ###################################
      echo "-- `date +%T` -- BEGIN dumping structure for: \"${THIS_DATABASE}.${THIS_TABLE}\""
      DUMP_STRUCTURE
      if [ $? -ne 0 ]
      then
        echo "-- Error returned from function for dumping structure"
        STRUCTURE_DUMP="ERROR"
      exit 1
      else
        echo "-- END dumping structure for: \"${THIS_DATABASE}.${THIS_TABLE}\""
      fi

      echo "-- `date +%T` -- BEGIN dumping data for: \"${THIS_DATABASE}.${THIS_TABLE}\""
      DUMP_DATA
      if [ $? -ne 0 ]
      then
        echo "-- Error returned from function for dumping data"
        DATA_DUMP="ERROR"
        exit 1
      else
        echo "-- END dumping data for: \"${THIS_DATABASE}.${THIS_TABLE}\""
      fi

      ##############################################
      # Check for huge tables; append to txt file  #
      ##############################################
      if [[ $(find "${TEMP_SAVEd_TABLE}.tmp" -type f -size +${EXTENDED_INSERT_MIN_SIZE}M 2>/dev/null) ]]
      then # we have a BIG_BIG_TABLE. Search for or append to MYSQL_DUMP_BIG_TABLES.database.txt file
        touch "${MYSQL_DUMP_BIG_TABLES}.${THIS_DATABASE}.txt"
        grep -qxF "${THIS_TABLE}" "${MYSQL_DUMP_BIG_TABLES}.${THIS_DATABASE}.txt" || echo "${THIS_TABLE}" >> "${MYSQL_DUMP_BIG_TABLES}.${THIS_DATABASE}.txt"
      fi

      echo "-- `date +%T` -- BEGIN compress: \"${THIS_DATABASE}.${THIS_TABLE}.sql\""
      COMPRESS_DUMP
      if [ $? -ne 0 ]
      then
        echo "-- Error returned from function for compressing dump"
        COMPRESS_ROUTINE="ERROR"
        exit 1
      else
        echo "-- END compress: \"${THIS_DATABASE}.${THIS_TABLE}.sql\""
      fi

      echo "-- `date +%T` -- Begin compare files from previous dump"
      COMPARE_FILES
      if [ $? -ne 0 ]
      then
        echo "-- Error returned from function for comparing files"
        COMPARE_ROUTINE="ERROR"
        exit 1
      else
        echo "-- `date +%T` -- END compare: \"${THIS_DATABASE}.${THIS_TABLE}.sql.gz\""
      fi
    else
      echo "-- Skip - Match found within \"${MYSQL_DUMP_SKIP_TABLES}.${THIS_DATABASE}.txt\": ${THIS_TABLE}"
    fi
  done
done
done

#####################################
# Clean up files and report errors  #
#####################################
# remove tmp files
try rm -f /tmp/sqlhead.sql /tmp/sqlend.sql
# clean stale data from temp folder
echo "MYSQL_DUMP_FOLDER = ${MYSQL_DUMP_FOLDER}"
echo "MYSQL_TMP_FOLDER = ${MYSQL_TMP_FOLDER}"
if [ "${MYSQL_DUMP_FOLDER}" != "${MYSQL_TMP_FOLDER}" ]
then
  echo "trying to empty ${MYSQL_TMP_FOLDER}"
  try rm -rf ${MYSQL_TMP_FOLDER}/*
fi

# check for errors
if [ -z "${PRECHECK_DUMP}" ] ; then
  echo "-- Precheck passed"
else
  echo "-- ***ERROR ENCOUNTERED*** - Check above for details"
  echo "PRECHECK_DUMP = ${PRECHECK_DUMP}"
  exit 111
fi
if [ -z "${STRUCTURE_DUMP}" ] ; then
  echo "-- Structure passed"
else
  echo "-- ***ERROR ENCOUNTERED*** - Check above for details"
  echo "STRUCTURE_DUMP = ${STRUCTURE_DUMP}"
  exit 111
fi
if [ -z "${DATA_DUMP}" ] ; then
  echo "-- Data passed"
else
  echo "-- ***ERROR ENCOUNTERED*** - Check above for details"
  echo "DATA_DUMP = ${DATA_DUMP}"
  exit 111
fi
if [ -z "${COMPRESS_ROUTINE}" ] ; then
  echo "-- Compress passed"
else
  echo "-- ***ERROR ENCOUNTERED*** - Check above for details"
  echo "COMPRESS_ROUTINE = ${COMPRESS_ROUTINE}"
  exit 111
fi
if [ -z "${COMPARE_ROUTINE}" ] ; then
  echo "-- Compare passed"
else
  echo "-- ***ERROR ENCOUNTERED*** - Check above for details"
  echo "COMPARE_ROUTINE = ${COMPARE_ROUTINE}"
  exit 111
fi

echo "-- FINISH DATABASE DUMP --"
