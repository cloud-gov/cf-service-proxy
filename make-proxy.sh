# set -x
###
# Vars
###

# Default variables.
PRINT_CREDS=0
APP_NAME="app"
SERVICE_NAME="service"
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
    echo "-p            print url and credentials to he console"
    echo "-s            name of service to proxy"
    echo "-u            only print the connection string - useful for scripts"

}

while getopts 'a:s:pu' flag

do
    case $flag in
        a) APP_NAME=$OPTARG;;
        p) PRINT_CREDS=1;;
        s) SERVICE_NAME=$OPTARG;;
        u) _V=0;;
        h) help; exit 0;;
        \?) help; exit 2;;
    esac
done

# Give the proxy a useful suffix.
SERVICE_ALIAS=$SERVICE_NAME
SERVICE_ALIAS=${SERVICE_ALIAS}-proxy

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
# Check for jq.
###

# Make sure jq is available.
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


###
# Create the service proxy.
###

# Get app status.
log "Getting status for ${SERVICE_ALIAS}."
SVC_APP_STATUS=$(cf curl \
  "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.Guid)/apps?q=name%3A${SERVICE_ALIAS}&inline-relations-depth=1" \
  | jq -r '.resources[0].entity.state')

log "  Status: ${SVC_APP_STATUS}"

# Only create the app if it doesn't exist.
if [ "$SVC_APP_STATUS" != "STARTED" ]
  then
  log "Creating ${SERVICE_ALIAS}..."
  # cd service-proxy
  cf push ${SERVICE_ALIAS} \
    --no-start \
    -p '' \
    -b https://github.com/cloudfoundry/staticfile-buildpack.git \
    -m 16m \
    -k 16m > /dev/null
  else
    log "    - Skipping creation."
fi

log ""

# Get elasticsearch service port and address for use by the service proxy.
log "Getting credentials for ${APP_NAME} service bindings."
SVC_PORT=$(cf curl \
  "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.Guid)/apps?q=name%3A${APP_NAME}&inline-relations-depth=1" \
  | jq -r '.resources[].entity.service_bindings[].entity.credentials.port | select(. != null)')

log "  Port: ${SVC_PORT}"

SVC_IP=$(cf curl \
  "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.Guid)/apps?q=name%3A${APP_NAME}&inline-relations-depth=1" \
  | jq -r '.resources[].entity.service_bindings[].entity.credentials.hostname | select(. != null)')

log "  IP: ${SVC_IP}"
log ""

PROXY_PORT=$(cf curl \
  "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.Guid)/apps?q=name%3A${SERVICE_ALIAS}&inline-relations-depth=1" \
  | jq -r '.resources[].entity.environment_json.PROXY_PORT')

PROXY_HOST=$(cf curl \
  "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.Guid)/apps?q=name%3A${SERVICE_ALIAS}&inline-relations-depth=1" \
  | jq -r '.resources[].entity.environment_json.PROXY_PORT')

if [ "$SVC_IP" != "$PROXY_HOST" ] && [ "$SVC_PORT" != "$PROXY_PORT" ]
  then

  # Bind proxy variables.
  log "- Injecting service credentials into ${SERVICE_ALIAS}."
  cf se ${SERVICE_ALIAS} PROXY_HOST $SVC_IP > /dev/null
  cf se ${SERVICE_ALIAS} PROXY_PORT $SVC_PORT > /dev/null

  # Restage the prxy app to pick up variables.
  if [ "$SVC_APP_STATUS" != "STARTED" ]
    then
    log "- Finishing start of ${SERVICE_ALIAS}."
    cf start ${SERVICE_ALIAS} > /dev/null
  else
    log "- Restaging ${SERVICE_ALIAS} to pick up variable changes."
    cf restage ${SERVICE_ALIAS} > /dev/null
  fi
fi

if [ "$PRINT_CREDS" = 1 ]
  then

  log "- Getting credentials for ${SERVICE_ALIAS}."
  SERVICE_USER=$(cf curl \
    "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.Guid)/service_instances?q=name%3A${SERVICE_NAME}&inline-relations-depth=1" \
    | jq -r '.resources[].entity.service_bindings[0].entity.credentials.username')

  SERVICE_PASS=$(cf curl \
    "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.Guid)/service_instances?q=name%3A${SERVICE_NAME}&inline-relations-depth=1" \
    | jq -r '.resources[].entity.service_bindings[0].entity.credentials.password')

  SERVICE_GUID=$(cf curl  \
    "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.Guid)/apps?q=name%3A${SERVICE_ALIAS}&inline-relations-depth=1" \
    | jq -r '.resources[].metadata.guid')

  SERVICE_DOMAIN=$(cf curl \
    "/v2/apps/${SERVICE_GUID}/stats" \
    | jq -r '."0".stats.uris[0]')

  log ""
  log "  - Access the the proxied service here:"
  log ""
  echo "https://${SERVICE_USER}:${SERVICE_PASS}@${SERVICE_DOMAIN}"
fi

log ""
log "- Finished."
log ""
