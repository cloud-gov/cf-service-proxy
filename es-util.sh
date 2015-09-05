###
# Vars
###

# Default variables.
PRINT_CREDS=0
SERVICE_NAME="service"
BACKUP_PATH="backup"
LIST_SNAPS=0
MODE="BACKUP"
_V=1

###
# Args
###

# Basic command line handling.
function help {
    echo "Usage: make-proxy.sh [OPTION]"
    echo "Create an ngnix proxy for Cloud Foundry service."
    echo " "
    echo "-a            name of application to check for service bindings"
    echo "-p            service proxy to use"
    echo "-s            name of the bucket service"
    echo "-c            create repo"
    echo "-r            restore mode"
    echo "-i            index to backup / restore"
    echo "-l            list snapshots"
    echo "-u            silent"
    echo "-c            repo name to create"
    echo "-b            create mode"
    echo "-d            delete snapshot"
}

while getopts 'p:s:n:i:luc:rbd:' flag

do
    case $flag in
        p) SVC_PROXY=$OPTARG;;
        s) SERVICE_NAME=$OPTARG;;
        n) SNAP_NAME=$OPTARG;;
        i) INDEX=$OPTARG;;
        l) LIST_SNAPS=1;;
        u) _V=0;;
        c) REPO_NAME=$OPTARG;;
        r) MODE="RESTORE";;
        b) MODE="BACKUP";;
        d) MODE="DELETE"
           SNAP_DELETE=$OPTARG;;
        h) help; exit 0;;
        \?) help; exit 2;;
    esac
done

###
# Logging
###

# Nice logging toogle from:
# http://stackoverflow.com/questions/8455991/elegant-way-for-verbose-mode-in-scripts
function log () {
    if [[ $_V -eq 1 ]]; then
        echo "$@"
    fi
}

###
# Snapshot status.
###
function backup_status () {
  while :
  do
    SNAP_STATUS=$(curl -k -s "${SVC_PROXY}/_snapshot/${REPO_NAME}/${SNAP_NAME}" \
      | jq -r .snapshots[].state)
    log "  - status: $SNAP_STATUS"
    if [ "$SNAP_STATUS" = "SUCCESS" ]
      then
      break
    fi
    sleep 1
  done
}

function restore_status () {
  while :
  do
    SNAP_STATUS=$(curl -k -s "${SVC_PROXY}/_recovery" \
       | jq -r '. | .["production-school-data"] | .shards[0].index.size.percent')
    log "  - status: $SNAP_STATUS"
    if [ "$SNAP_STATUS" = "100.0%" ]
      then
      break
    fi
    sleep 10
  done
}

###
# Check for jq.
###
log "Looking for jq."
JQ_PATH=$(which jq)
if [[ ! -n ${JQ_PATH} ]]
  then
    log "  - Installing jq."
    OS_TYPE=$(uname -a | uname -a | cut -f1 -d" ")
    if [ "$OS_TYPE" = "Darwin" ]
      then
      brew install jq
    else
      log "    Couldn't find jq and don't have a method to install it."
      log "    After adding https://stedolan.github.io/jq/ try again."
    fi
  else
    log "  - Found jq."
fi

log "Getting bindings for ${SERVICE_NAME}."

SVC_JSON=$(cf curl \
  "/v2/spaces/$(cat ~/.cf/config.json | jq -rc .SpaceFields.Guid)/service_instances?return_user_provided_service_instances=true&q=name%3A${SERVICE_NAME}&inline-relations-depth=1")

ACCESS_KEY=$(echo $SVC_JSON | jq -r '.resources[].entity.service_bindings[].entity.credentials.access_key | select(. != null)')
SECRET_KEY=$(echo $SVC_JSON | jq -r '.resources[].entity.service_bindings[].entity.credentials.secret_key | select(. != null)')
BUCKET=$(echo $SVC_JSON | jq -r '.resources[].entity.service_bindings[].entity.credentials.bucket | select(. != null)')

###
# Create a snapshot repo.
###
log "Attempting to create repo $REPO_NAME."
if [ -n "$REPO_NAME" ]
  then
  REPO_RESULT=$(curl -s -k -X PUT "${SVC_PROXY}/_snapshot/${REPO_NAME}" -d '{
      "type":"s3",
      "settings": {
          "access_key":"'"${ACCESS_KEY}"'",
          "secret_key":"'"${SECRET_KEY}"'",
          "bucket":"'"${BUCKET}"'",
          "base_path":"'"${BACKUP_PATH}"'",
          "region": "us-east"
      }
  }')

  log "  - result: $(echo $REPO_RESULT | jq -c .)"
fi

###
# List snapshots.
###

if [[ $LIST_SNAPS -eq 1 ]]
  then
  log ""
  log 'Snapshots:'
  SNAP_LIST=$(curl -k -s "${SVC_PROXY}/_snapshot/${REPO_NAME}/_all" | jq -r .snapshots[].snapshot)
  for SNAP in $SNAP_LIST
    do
      # Can probably do this better by requesting all snapshots as a list in one call.
      log "  - name: $SNAP"
      log "    - status: $(curl -k -s "${SVC_PROXY}/_snapshot/${REPO_NAME}/${SNAP}/_status" | jq .snapshots[0].state)"
    done
  exit 0
fi


###
# Snapshots
###

if [ $(echo "$REPO_RESULT" | jq .acknowledged) != "true" ]
  then
  log "No valid repo."
  exit 1
fi

case $MODE in
    BACKUP)
    if [ -z $SNAP_NAME ]
      then
      SNAP_NAME=$(date +%s)
    fi

    log "Attempting to create snap $SNAP_NAME."

    SNAP_RESULT=$(curl -k -s -XPUT "${SVC_PROXY}/_snapshot/${REPO_NAME}/${SNAP_NAME}")
    log "  - result: $(echo $SNAP_RESULT | jq -c .)"
    if [ $(echo "$SNAP_RESULT" | jq .accepted) = "true" ]
      then
      backup_status
    fi
    ;;

    RESTORE)
    if [ -z $SNAP_NAME ]
      then
      SNAP_NAME="latest"
    fi

    log "Attempting to restore snap $SNAP_NAME."

    INDEX_STATUS=$(curl -k -s "${SVC_PROXY}/_status" \
      | jq -r '.indices | .["production-school-data"] | .shards | .["0"] | .[].state')

    if [ "${INDEX_STATUS}" = "STARTED" ]
      then
      curl -k -XPOST "${SVC_PROXY}/${INDEX}/_close"
    fi

    SNAP_RESULT=$(curl -k -s -X POST "${SVC_PROXY}/_snapshot/${REPO_NAME}/${SNAP_NAME}/_restore" -d '{
        "indices":"'"$INDEX"'"}')
    log "  - result: $(echo $SNAP_RESULT | jq -c .)"
    if [ $(echo $SNAP_RESULT | jq .accepted) = "true" ]
      then
      restore_status
    fi
    ;;

    DELETE)

    log "Attempting to delete snap $SNAP_DELETE."

    DELETE_RESULT=$(curl -k -s -X DELETE "${SVC_PROXY}/_snapshot/${REPO_NAME}/${SNAP_DELETE}")
    log "  - result: $(echo $DELETE_RESULT | jq -c .)"
    if [ $(echo $DELETE_RESULT | jq .acknowledged) = "true" ]
      then
      log "Success."
    fi
esac
