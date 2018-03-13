#!/usr/bin/env bash

# Exit immediately on non-zero return codes.
set -e

#################################################################################
# Declare Variables
#################################################################################
CONFIG="/data/backup.yml"
REGION=
ACCESS_KEY_ID=
SECRET_KEY=
MODE=
TIMESTAMP=
LOCAL=/data/
REMOTE=
OWNER=1000
GROUP=1000
EXTRA=

usage(){
(
cat <<EOL
Usage: [OPTIONS]...

Options:
    --config <path>
    		Path to read or write configuration file .
    		Default: $CONFIG

    --region <string>
    		The AWS region to use.

    --access-key <string>
    		AWS Access Key

    --secret-key <string>
    		AWS Secret Key

    --mode <string>
    		restore - reads the $CONFIG file and executes a restore
    		backup - reads the $CONFIG file and executes a save

    --local <string>
    		Path to the local directory to backup.
    		Default: $LOCAL

    --remote <string>
    		S3 bucket and path to use. Must start with the s3:// prefix.

    --owner <string>
    		The owner name or id to change restored files to.
    		Default: $OWNER

    --group <string>
    		The group  name or id to change restored files to.
    		Default: $GROUP

    --timestamp <string>
    		When performing a restore. Specify a timestamp to restore

    -- <string>
    		Additional arguments to pass to the AWS cli. Common use cases are --include, --exclude and --storage-class
EOL
) >&2
}


#################################################################################
# PARSE OPTIONS
#################################################################################

parseOptions() {
	# Parses command arguments and assigns values to global variables
	# Input: parseOptions $@ - pass in the options used on the main script
	# Output: None
	TEMP=`getopt  -o h: --longoptions config:,region:,access-key:,secret-key:,timestamp:,local:,remote:,owner:,group:,mode: -n 'docker-entrypoint.sh' -- "$@"`

	if [ $? != 0 ] ; then usage; exit 1 ; fi

	# Note the quotes around `$TEMP': they are essential!
	eval set -- "$TEMP"

	while true; do
		case "$1" in
			--config ) CONFIG=$2; shift 2;;
			--region ) REGION=$2; shift 2;;
			--access-key ) ACCESS_KEY_ID=$2; shift 2;;
			--secret-key ) SECRET_KEY="$2"; shift 2;;
			--timestamp ) TIMESTAMP="$2"; shift 2;;
			--mode ) MODE="$2"; shift 2;;
			--local ) LOCAL=$2; shift 2;;
			--remote ) REMOTE="$2"; shift 2;;
			--owner) OWNER="$2"; shift 2;;
			--group ) GROUP="$2"; shift 2;;
			-- ) shift; EXTRA="$@"; break ;;
			* ) usage; break ;;
		esac
	done
}

validateOptions() {
	# Checks if global variables are set
	# Input: None
	# Output: None

	if [ -z "$CONFIG" ]; then echo "--config missing" >&2; usage; exit 1; fi
	if [ -z "$REGION" ]; then echo "--region missing" >&2; usage; exit 1; fi
 	if [ -z "$ACCESS_KEY_ID" ]; then echo "--aws-access-key-id missing" >&2; usage; exit 1; fi
 	if [ -z "$SECRET_KEY" ]; then echo "--aws-secret-key missing" >&2; usage; exit 1; fi
	if [ -z "$MODE" ]; then echo "--mode missing" >&2; usage; exit 1; fi
	if [ -z "$LOCAL" ]; then echo "--local missing" >&2; usage; exit 1; fi
	if [ -z "$REMOTE" ]; then echo "--remote missing" >&2; usage; exit 1; fi
	if [ -z "$OWNER" ]; then echo "--owner missing" >&2; usage; exit 1; fi
	if [ -z "$GROUP" ]; then echo "--group missing" >&2; usage; exit 1; fi
}

configureAWS() {
	# Creates the configuration files for AWS CLI
	# Input: None
	# Output: None

	mkdir -p /root/.aws
		(
		cat <<EOP
[default]
region = $REGION
EOP
		) > /root/.aws/config
		chmod 600 /root/.aws/config

		(
		cat <<EOP
[default]
aws_secret_access_key = $SECRET_KEY
aws_access_key_id = $ACCESS_KEY_ID
EOP
		) > /root/.aws/credentials
		chmod 600 /root/.aws/credentials
}

doBackup() {
	# Performs a backup.
  # Reads the backup.yml file from the CONFIG variables.
  # Copies the previous backup to a new folder. Then sync the current local directory with that directory
  # Saves a state file in the local directory as .backup-last
	# Input: None
	# Output: None

  if [ ! -d "$LOCAL" ]; then echo "\$local: \"$LOCAL\" doesn't exist or isn't a directory" >&2; exit 1; fi

  # The first braces expand to $V and the coln if V is set already otherwise do nothing
  local src=${LOCAL/+${LOCAL}/}
  local dst=${REMOTE/+${REMOTE}/}

  local dateStamp=$(date -u +%Y%m%d%H%M%S/)
  local stateFile="$src/.backup-last"

  local latest=$(aws s3 ls "$dst" | awk '{ print $2 }' | tail -n1)

  if [ ! -z "$latest" ]
  then
    aws s3 cp $EXTRA --recursive "$REMOTE$latest" "$dst$dateStamp"
  fi

  set +e
  while true
  do
    aws s3 sync $EXTRA --delete "$src" "$dst$dateStamp"
    if [ "$?" == "0" ]; then break; fi
    sleep 1
  done
  set -e
}

doRestore() {
	# Performs a restore.
  # Reads the backup.yml file from the CONFIG variables.
  # Restores the date stamp from the command line argument.
  # If TIMESTAMP is blank restore the last backup.
  # Changes the owner and group of files restored
	# Input: None
	# Output: None

  local src=${REMOTE/+${REMOTE}/}
  local dst=${LOCAL/+${LOCAL}/}
  if [ ! -d "$dst" ]; then echo "\local: \"$dst\" doesn't exist or isn't a directory" >&2; exit 1; fi

  if [ ! -z "$TIMESTAMP" ]
	then
    local TIMESTAMP=${TIMESTAMP/+${TIMESTAMP}/}
    local src=$src$TIMESTAMP
	else
    local latest=$(aws s3 ls "$src" | awk '{ print $2 }' | tail -n1)
    local src=$src$latest
  fi

  set +e
  while true
  do
    aws s3 sync $EXTRA "$src" "$dst"
    if [ "$?" == "0" ]; then break; fi
    sleep 1
  done
  set -e

  if [ ! -z "$OWNER" ]; then chown -R "$OWNER" $dst; fi
  if [ ! -z "$GROUP" ]; then chgrp -R "$GROUP" $dst; fi
}

################################################################################
# Execute the script
################################################################################
parseOptions "$@"
validateOptions

case "$MODE" in
	backup )
		configureAWS
		doBackup
    exit 0
		;;
	restore )
		configureAWS
		doRestore
    exit 0
		;;
	* )
		usage
		exit 1
		;;
esac
