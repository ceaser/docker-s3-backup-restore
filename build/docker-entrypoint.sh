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
    		init - create the empty configuration file in the /data/backup.json path
    		restore - reads the $CONFIG file and executes a restore
    		backup - reads the $CONFIG file and executes a save

    --timestamp <string>
    		When performing a restore. Specify a timestamp to restore
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
	TEMP=`getopt  -o h: --longoptions config:,region:,access-key:,secret-key:,timestamp:,mode: -n 'docker-entrypoint.sh' -- "$@"`

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
			-- ) shift; break ;;
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
}


parseYaml() {
	# Checks if global variables are set
	# Input: parseYaml <path-to-file> <prefix> - path is a yaml file and prefix is for the env variable
	# Output: None
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
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

doInit() {
	# Creates the configuration file if it doesn't exist
	# Input: None
	# Output: None

	if [ ! -f "$CONFIG" ]
	then
( cat <<EOL
default:
	local: /data/
	remote: s3://replace-bucket/replace-path/
	owner: 1000
	group: 1000
	extra: "--dry-run"
EOL
) > $CONFIG
fi
}

doBackup() {
	# Performs a backup.
  # Reads the backup.yml file from the CONFIG variables.
  # Copies the previous backup to a new folder. Then sync the current local directory with that directory
  # Saves a state file in the local directory as .backup-last
	# Input: None
	# Output: None

  eval $(parseYaml $CONFIG "config_")

  if [ ! -d "$config_default_local" ]; then echo "\$local: \"$config_default_local\" doesn't exist or isn't a directory" >&2; exit 1; fi

  # The first braces expand to $V and the coln if V is set already otherwise do nothing
  local src=${config_default_local/+${config_default_local}/}
  local dateStamp=$(date -u +%Y%m%d%H%M%S)
  local stateFile="$src/.backup-last"

  #	# The first braces expand to $V and the coln if V is set already otherwise do nothing
  local dst=${config_default_remote/+${config_default_remote}/}$dateStamp/

  # TODO: Remove the local state file. Just ls the previous backups. Then copy the latest
  if [ -f "$stateFile" ]
  then
    local lastDateStamp=$(cat $stateFile)
    # The first braces expand to $V and the coln if V is set already otherwise do nothing
    local src=${config_default_remote/+${config_default_remote}/}$lastDateStamp/

    set +e
    while true
    do
      aws s3 cp $config_default_extra --recursive "$src" "$dst"
      if [ "$?" == "0" ]; then break; fi
      sleep 1
    done
    set -e
  fi

  # The first braces expand to $V and the coln if V is set already otherwise do nothing
  local src=${config_default_local/+${config_default_local}/}

  set +e
  while true
  do
    aws s3 sync $config_default_extra --delete "$src" "$dst"
    if [ "$?" == "0" ]; then break; fi
    sleep 1
  done
  set -e

  echo "$dateStamp" > "$stateFile"
}

doRestore() {
	# Performs a restore.
  # Reads the backup.yml file from the CONFIG variables.
  # Restores the date stamp from the command line argument.
  # If TIMESTAMP is blank restore the last backup.
  # Changes the owner and group of files restored
	# Input: None
	# Output: None
	eval $(parseYaml $CONFIG "config_")

  local dst=${config_default_local/+${config_default_local}/}
  if [ ! -d "$dst" ]; then echo "\local: \"$dst\" doesn't exist or isn't a directory" >&2; exit 1; fi

  local stateFile="$src/.backup-last"

  if [ ! -z "$TIMESTAMP" ]
	then
    local src=${config_default_remote/+${config_default_remote}/}$TIMESTAMP/
	else
    local src=${config_default_remote/+${config_default_remote}/}
    local latest=$(aws s3 ls "$src" | awk '{ print $2 }' | tail -n1)
    local src=${config_default_remote/+${config_default_remote}/}$latest
  fi

  set +e
  while true
  do
    aws s3 sync $config_default_extra "$src" "$dst"
    if [ "$?" == "0" ]; then break; fi
    sleep 1
  done
  set -e

  if [ ! -z "$config_default_owner" ]; then chown -R "$config_default_owner" $dst; fi
  if [ ! -z "$config_default_group" ]; then chgrp -R "$config_default_group" $dst; fi
}

################################################################################
# Execute the script
################################################################################
parseOptions "$@"
validateOptions

case "$MODE" in
	init )
		doInit
    exit 0
		;;
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
