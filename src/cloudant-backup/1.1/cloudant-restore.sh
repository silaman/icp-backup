#!/bin/bash
#
# Licensed Material - Property of IBM
# 5724-I63, 5724-H88, (C) Copyright IBM Corp. 2018 - All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
#
# DISCLAIMER:
# The following source code is sample code created by IBM Corporation.
# This sample code is provided to you solely for the purpose of assisting you
# in the  use of  the product. The code is provided 'AS IS', without warranty or
# condition of any kind. IBM shall not be liable for any damages arising out of 
# your use of the sample code, even if IBM has been advised of the possibility 
# of such damages.
#
# DESCRIPTION:
#   Restore ICP Cloudant databases 
#
# INPUTS:
#   1. Path to backup directory. (required) 
#      Each backup gets its own directory with a timestamp.
#
#   2. Host name (FQDN) or IP address of the Cloudant DB server. (optional)
#      Defaults to localhost. This needs to be one of the ICP master nodes
#      where the Cloudant database service is running.
#
#   3. Database names of databases to restore. (optional)
#      Defaults to all the databases that were backed up by the cloudant-backup.sh
#      script.  The dbnames.sh filein the backup directory is sourced.
#      The variable BACKED_UP_DBNAMES holds the list of database backups in the 
#      given backup directory.
#
# Assumptions:
#   1. The user has a current kubernetes context for the admin user.
#
#   2. User has read permission for the backups directory home.
#
#   3. If a Cloudant DB server host name is not provided it is assumed
#      this script is being run on the Cloudant DB server host as
#      localhost is used in the Cloudant DB URL.
#
#   4. The backup was created with the cloudant-backup.sh script that 
#      is included in the git repo with this script.  The content of 
#      the backup directory is expected to have a dbnames.sh script
#      that holds a list of databases that were backed up.
#
function usage {
  echo ""
  echo "Usage: cloudant-restore.sh [options]"
  echo "   --dbhost <hostname|ip_address>   - (optional) Host name or IP address of the Cloudant DB service provider"
  echo "                                      For example, one of the ICP master nodes."
  echo "                                      Defaults to cloudantdb."
  echo ""
  echo "   --backup-dir <path>              - (required) Path to a backup directory."
  echo "                                      A valid backup directory will have a time stamp in its name and"
  echo "                                      a file named dbnames.sh that is executable along with the backup"
  echo "                                      JSON files and backup log files."
  echo ""
  echo "   --dbnames <name_list>            - (optional) Space separated list of database names to restore."
  echo "                                      The dbnames list needs to be quoted."
  echo "                                      Defaults to all databases with backup files in the given backup directory."
  echo ""
  echo "   --help|-h                        - emit this usage information"
  echo ""
  echo " - and -- are accepted as keyword argument indicators"
  echo ""
  echo "Sample invocations:"
  echo "  ./cloudant-restore.sh --backup-dir ./backups/icp-cloudant-backup-2018-03-10-21-08-41"
  echo "  ./cloudant-restore.sh --dbhost master01.xxx.yyy --backup-home ./backups/icp-cloudant-backup-2018-03-10-21-08-41"
  echo ""
  echo " User is assumed to have read permission on backup home directory."
  echo " User is assumed to have a valid kubernetes context with admin credentials."
  echo ""
}


# import helper functions
. ./helperFunctions.sh

# MAIN

backupHome=""    # save this for an enhancement
backupDir=""
dbhost=""
dbnames=""

# process the input args
# For keyword-value arguments the arg gets the keyword and
# the case statement assigns the value to a script variable.
# If any "switch" args are added to the command line args,
# then it wouldn't need a shift after processing the switch
# keyword.  The script variable for a switch argument would
# be initialized to "false" or the empty string and if the
# switch is provided on the command line it would be assigned
# "true".
#
while (( $# > 0 )); do
  arg=$1
  case $arg in
    -h|--help ) usage; exit 0
                ;;

    -backup-dir|--backup-dir )  backupDir=$2; shift
                ;;

    -backup-home|--backup-home )  backupHome=$2; shift
                ;;

    -dbhost|--dbhost)  dbhost=$2; shift
                ;;                                                          

    -dbnames|--dbnames)  dbnames=$2; shift
                ;;                                                          

    * ) usage; info $LINENO "ERROR: Unknown option: $arg in command line."  
               exit 1
                ;;                          
  esac              
  # shift to next key-value pair
  shift             
done  


if [ -z "$backupHome" ]; then
  backupHome="${PWD}/backups"
fi
#info $LINENO "Backup directory will be created in: $backupHome"


if [ -z "$backupDir" ]; then
  info $LINENO "ERROR: The backup directory must be provided."
  exit 1
fi

if [ ! -d "$backupDir" ]; then
  info $LINENO "ERROR: The backup directory does not exist or is not a directory: $backupDir"
  exit 2
fi

dbnamesScriptPath="$backupDir/dbnames.sh"
if [ ! -f "$dbnamesScriptPath" ]; then
  info $LINENO "ERROR: The backup directory is missing the dbnames.sh script and is invalid: $backupDir"
  exit 3
fi

source $dbnamesScriptPath
# ALL_DBS and BACKED_UP_DBNAMES are exported in dbnames.

if [ -z "$BACKED_UP_DBNAMES" ]; then
  info $LINENO "ERROR: The backup directory does not appear to have any databases that were backed up. BACKED_UP_DBNAMES is empty."
  info $LINENO "Backup directory: $backupDIr"
  info $LINENO "dbnames.sh content:"
  cat "$dbnamesScriptPath"
  exit 4
else:
  info $LINENO "ICP Cloudant database backups for: \"$BACKED_UP_DBNAMES\" in: $backupDir"
fi


if [ -z "$dbhost" ]; then
  dbhost=cloudantdb
fi
info $LINENO "Cloudant DB host: $dbhost"


port=$(getCloudantNodePort)
password=$(getCloudantPassword)

if [ -z "$port" ]; then
  info $LINENO "ERROR: port must be defined. Check getCloudantNodePort helper function."
  exit 1
fi

if [ -z "$password" ]; then 
  info $LINENO "ERROR: password must not be empty. Check getCloudantPassword helper function."
  exit 2
fi

info $LINENO "Cloudant NodePort: $port"

if [ -z "$dbnames" ]; then
  # If dbnames was not provided on commmand line then restore all that have a backup
  # in the backup directory.
  dbnames="$BACKED_UP_DBNAMES"
else
  # Make sure all user provided dbnames are valid for the given backup directory. 
  ERROR=""
  for name in $dbnames; do
    isvalid=$(echo "$BACKED_UP_DBNAMES" | grep $name) 
    if [ -z "$isvalid" ]; then
      info $LINENO "ERROR: The backup directory does not hold a backup for database name: \"$name\""
      ERROR="true"
    fi
  done
  if [ -n "$ERROR" ]; then
    info $LINENO "Valid ICP Cloudant database names:"
    echo "\"$ALL_DBS\"" 
    info $LINENO "Backup directory: $backupDir holds backups for databases:" 
    echo "\"$BACKED_UP_DBNAMES\""
    exit 6
  fi
fi

info $LINENO "Databases to be restored: $dbnames"
info $LINENO "Backups will be restored from: $backupDir"

# In a restore scenario the Cloudant database may not be defined.
currentDBs=$(getCloudantDatabaseNames $dbhost)

# Make sure the database exists in the ICP Cloudant instance.
for name in $dbnames; do
  dbexists=$(echo "$currentDBs" | grep $name) 
  if [ -z "$dbexists" ]; then
    info $LINENO "Creating database: $name on Cloudant instance host: $dbhost"
    createDatabase $dbhost $name
  else
    info $LINENO "Database: $name already exists on Cloudant instance host: $dbhost"
  fi
done


for dbname in $dbnames; do
  backupFilePath=$(makeBackupFilePath $backupDir $dbname)
  if [ ! -f "$backupFilePath" ]; then
    info $LINENO "ERROR: Backup file: $backupFilePath does not exist for database: $dbname"
  else
    couchrestore --url "http://admin:$password@$dbhost:$port" --db $dbname < "$backupFilePath"
  fi
done


