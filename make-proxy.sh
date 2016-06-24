#!/bin/bash
# set -x
###
# Default Vars
###

# Default variables.
PRINT_CREDS=0
s_flag=0;
a_flag=0;
z_flag=0;
g_flag=0;
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
    echo "-p            print url and credentials to the console"
    echo "-s            name of service to proxy"
    echo "-u            only print the connection string - useful for scripts"
    echo "-d            proxy route domain"
    echo "-z            custom port to proxy"
    echo "-n            proxy app name"
    echo "-g            use nginx-auth"
}

while getopts 'ad:s:puz:n:g:' flag

do
    case $flag in
        a) APP_NAME=1; a_flag=1;;
        d) APP_DOMAIN=$OPTARG;;
        p) PRINT_CREDS=1;;
        s) SERVICE_NAME=$OPTARG; s_flag=1;;
        n) PROXY_NAME=$OPTARG;;
        g) NGINX_DIR=$OPTARG; g_flag=1;;
        u) _V=0;;
        z) CUSTOM_PORT=$OPTARG; z_flag=1;;
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

function bail () {
      echo "$@"
      exit 1
}

###
# Warning.
###
if [ "$a_flag" -eq 1 ]; then
  log ""
  log "##########"
  log "NOTE: The -a switch is no longer necessary and will be removed."
  log "##########"
  log ""
fi

###
# Check for jq.
###

# Make sure jq is available.
log "Looking for jq."
JQ_PATH=$(which jq)
if [[ -n ${JQ_PATH} ]]; then
  JQ_VERSION=$($JQ_PATH --version)
  if [ "$JQ_VERSION" != "jq-1.5" ]; then
    log "  - Upgrading jq."
    brew upgrade jq
    else
      log "  - Found jq."
    fi
  else
    log "  - Installing jq."
    OS_TYPE=$(uname -a | uname -a | cut -f1 -d" ")
    if [ "$OS_TYPE" = "Darwin" ]
      then
      brew install jq
    else
      log "    Couldn't find jq and don't have a method to install it."
      log "    After adding https://stedolan.github.io/jq/ try again."
    fi
fi

###
# Functions.
###

function make_tmp_app () {
  UUID=$(uuidgen)
  TMP_APP=placeholder-${UUID}
  TMP_DIR="/tmp"
  TMP_PATH=${TMP_DIR}/${TMP_APP}
  mkdir -p $TMP_PATH
  touch $TMP_PATH/Staticfile

  # Create the temp app.
  log "Creating temp app: $TMP_APP"
  cf push $TMP_APP \
    --no-route \
    -m 5m \
    -k 5m \
    -p $TMP_PATH \
    --no-start \
    -b https://github.com/cloudfoundry/staticfile-buildpack.git > /dev/null
  if [ $? -ne 0 ]; then
    echo "Failed to create temp app: $TMP_APP"
  fi

  #Bind service.
  log "Binding service to temp app: $TMP_APP"
  cf bs $TMP_APP $SERVICE_NAME > /dev/null
  if [ $? -ne 0 ]; then
    echo "Failed bind service $TMP_APP to $SERVICE_NAME."
  fi

  # Check that bindings are good.
  if ! get_svc_bindings; then

    # Delete temp app.
    log "Deleting: $TMP_APP"
    cf delete -f $TMP_APP > /dev/null
    if [ $? -ne 0 ]; then
      echo "Failed to delete $TMP_APP."
    fi

    # Clean up local artifacts.
    log "Cleaning up: $TMP_PATH"
    rm $TMP_PATH/Staticfile
    rmdir $TMP_PATH
    return 0
  else
    echo "Failed to make app."
  fi
}

# Get app service bindings.
function get_svc_bindings () {
  log "  - Checking service bindings for $SERVICE_NAME."
  SVC_STATUS=$(cf curl \
    "/v2/spaces/${SPACE_GUID}/service_instances?return_user_provided_service_instances=true&q=name%3A${SERVICE_NAME}&inline-relations-depth=1")

  jq -er '.total_results > 0' <(echo $SVC_STATUS) > /dev/null \
    || bail "  - Service not found: $SERVICE_NAME";

  jq -er '.resources[0].entity.service_bindings != []' <(echo $SVC_STATUS) > /dev/null \
    && return 1

  return 0
}

# Get app service bindings.
function get_svc_credentials () {
  log "Getting service credentials for $SERVICE_NAME."

  SVC_CREDENTIALS=$(jq '.resources[0].entity.service_bindings[0].entity.credentials' <(echo $SVC_STATUS))

  return 0
}

# Get app service bindings.
function get_proxy_env () {
  log "Getting app environment for $SERVICE_APP."

  PROXY_STATUS=$(cf curl \
    "/v2/spaces/$(cat ~/.cf/config.json | jq -r .SpaceFields.GUID)/apps?q=name%3A${SERVICE_APP}&inline-relations-depth=1")

  PROXY_ENV=$(jq -er '.resources[].entity.environment_json' <(echo $PROXY_STATUS))

  return 0
}

function get_app_status () {
  log "Checking status for $1."

  APP_STATUS=$(cf curl \
    "/v2/spaces/${SPACE_GUID}/apps?q=name%3A${1}&inline-relations-depth=1")

  jq -er '.total_results > 0' <(echo $APP_STATUS) > /dev/null \
    || return 1

  jq -er '.resources[0].entity.state' <(echo $APP_STATUS) > /dev/null \
    && APP_STATE=$(jq -er '.resources[0].entity.state' <(echo $APP_STATUS)) \
    && return 0
}

function get_domains () {
  log "Getting domains for $ORG_NAME."

  SHARED_DOMAINS=$(cf curl \
    "/v2/shared_domains")

  jq -er '.resources[0].entity.name' <(echo $SHARED_DOMAINS) > /dev/null \
    || bail "No domains found!"

  APP_DOMAIN=$(jq -er '.resources[0].entity.name' <(echo $SHARED_DOMAINS))

  return 0
}

function app_start_or_restage () {
  get_app_status $1
  if [ ! -z $2 ] && [ "$APP_STATE" = "$2" ];then
    return 0
  fi
  case $APP_STATE in
    STOPPED)
      log "- Finishing start of ${SERVICE_APP}."
      cf start ${SERVICE_APP} > /dev/null
      ;;
    STARTED)
      log "- Restaging ${SERVICE_APP} to pick up variable changes."
      cf restage ${SERVICE_APP} > /dev/null
      ;;
    esac
}

function bind_env_var () {
  log "  + Binding $1 to $2 in $3."
  cf se ${1} ${2} ${3} > /dev/null
  if [ $? -ne 0 ]; then
    bail "Failed bind variable $1 to $2 in $3."
  fi
}

###
# Vars.
###

# GUID of the currently targeted space.
CF_CONFIG=$(jq -rc . ~/.cf/config.json)
SPACE_GUID=$(jq -r .SpaceFields.GUID <(echo $CF_CONFIG))
SPACE_NAME=$(jq -r .SpaceFields.Name <(echo $CF_CONFIG))
ORG_GUIDE=$(jq -r .OrganizationFields.GUID <(echo $CF_CONFIG))
ORG_NAME=$(jq -r .OrganizationFields.Name <(echo $CF_CONFIG))

# Give the proxy a useful suffix.
if [ -z $PROXY_NAME ];then
  SERVICE_APP=${SERVICE_NAME}-proxy
  SERVICE_ALIAS=${ORG_NAME}-${SPACE_NAME}-${SERVICE_NAME}-proxy
else
  SERVICE_APP=${PROXY_NAME}-proxy
  SERVICE_ALIAS=${ORG_NAME}-${SPACE_NAME}-${PROXY_NAME}-proxy
fi

# Domain.
if [ -z "$APP_DOMAIN" ]; then
  get_domains
fi

###
# Create the service proxy.
###

# Let them know what we're doing.
log "Getting status for ${SERVICE_NAME}."

# Get information about named service. Create a temporary app in order to get
# bindings of none exist.
if ! get_svc_bindings; then
  log "    - Found bindings."
else
  make_tmp_app
fi

if [ "$g_flag" -eq 1 ];then
  PUSH_DIR=$NGINX_DIR
else
  PUSH_DIR="."
fi

if ! get_app_status $SERVICE_APP; then
  log "Creating ${SERVICE_APP}..."
  cf push ${SERVICE_APP} \
    --no-start \
    -p $PUSH_DIR \
    -d $APP_DOMAIN \
    -n $SERVICE_ALIAS \
    -b https://github.com/cloudfoundry/staticfile-buildpack.git \
    -m 16m \
    -k 16m > /dev/null
  else
    log "    - Skipping creation."
fi

log ""

get_svc_credentials

# Get elasticsearch service port and address for use by the service proxy.
if [ $z_flag -eq 1 ]; then
    SVC_PORT=$(jq -er --arg PORT "$CUSTOM_PORT" '.ports | .[$PORT]' <(echo $SVC_CREDENTIALS))
  else
    SVC_PORT=$(jq -er '.port' <(echo $SVC_CREDENTIALS))
fi

log "  Port: ${SVC_PORT}"

SVC_IP=$(jq -er '.hostname' <(echo $SVC_CREDENTIALS))

log "  IP: ${SVC_IP}"
log ""

get_proxy_env

PROXY_PORT=$(jq -r '.PROXY_PORT' <(echo $PROXY_ENV))

PROXY_HOST=$(jq -r '.PROXY_HOST' <(echo $PROXY_ENV))

if [ "$SVC_IP" != "$PROXY_HOST" ] || [ "$SVC_PORT" != "$PROXY_PORT" ]; then
  log "! Proxy vars don't match."

  # Bind proxy variables.
  log "+ Injecting service credentials into ${SERVICE_APP}."
  bind_env_var ${SERVICE_APP} "PROXY_HOST" $SVC_IP
  bind_env_var ${SERVICE_APP} "PROXY_PORT" $SVC_PORT

  # Restage the prxy app to pick up variables.
  app_start_or_restage $SERVICE_APP
fi

if [ "$PRINT_CREDS" = 1 ]
  then

  log "  - Getting credentials for ${SERVICE_APP}."
  SERVICE_USER=$(jq -er '.username' <(echo $SVC_CREDENTIALS))

  SERVICE_PASS=$(jq -er '.password' <(echo $SVC_CREDENTIALS))

  app_start_or_restage $SERVICE_APP "STARTED"

  SERVICE_GUID=$(jq -r '.resources[].metadata.guid' <(echo $APP_STATUS))

  SERVICE_DOMAIN=$(cf curl \
    "/v2/apps/${SERVICE_GUID}/stats" \
    | jq -r '."0".stats.uris[0]')

  log ""
  log "Access the the proxied service here:"
  log ""
  echo "https://${SERVICE_USER}:${SERVICE_PASS}@${SERVICE_DOMAIN}"
fi

log "Done."
