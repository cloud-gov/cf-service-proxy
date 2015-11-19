#!/bin/bash
#
# Provision an ELK instance for cloud.gov
#
# set -x

# some console niceties
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function bail () {
  echo "$@"
  exit 1
}

function help {
  echo "Usage: make-elk-service.sh [OPTIONS]"
  echo "Provision ELK instance for Cloud Foundry service."
  echo " "
  echo "-h                 print this help message"
  echo "-a appname         name of your application"
  echo "-s elkname         name of ELK service"
  echo "-u username        username for Kibana proxy"
  echo "-d domain          Kibana proxy domain"
}

function parse_options () {
  a_flag=0;
  d_flag=0;
  s_flag=0;
  u_flag=0;

  while getopts 'ha:d:s:u:' flag; do
    echo "flag==$flag"
    case $flag in
      a) APP_NAME=$OPTARG; a_flag=1;;
      d) APP_DOMAIN=$OPTARG; d_flag=1;;
      s) SERVICE_NAME=$OPTARG; s_flag=1;;
      u) USER_NAME=$OPTARG; u_flag=1;;
      h) help; exit 0;;
      \?) help; exit 2;;
      :  ) echo "Missing option argument for -$OPTARG" >&2; exit 1;;
    esac
  done

  echo "d_flag == $d_flag"

  # some options are required
  if [ $d_flag == 0 ]; then bail "-d domain is required; try -h for usage"; fi
  if [ $a_flag == 0 ]; then bail "-a appname is required; try -h for usage"; fi
  if [ $u_flag == 0 ]; then bail "-u username is required; try -h for usage"; fi

  # create default service name
  if [ -z $SERVICE_NAME ]; then
    SERVICE_NAME="${APP_NAME}-elk"
  fi
}

function create_service () {
  echo -e "Creating service ${BLUE}$SERVICE_NAME${NC}"
  cf cs elk free $SERVICE_NAME || bail "service creation failed"
}

function bind_service () {
  echo -e "Binding ${BLUE}$SERVICE_NAME${NC} to ${BLUE}$APP_NAME${NC}"
  cf bs $APP_NAME $SERVICE_NAME || bail "service binding failed"
  echo -e "You should add ${BLUE}$SERVICE_NAME${NC} to the ${BLUE}$APP_NAME${NC} ${RED}services${NC} section of your ${RED}manifest.yml${NC} file"
}

function create_proxy () {
  echo "Creating Kibana proxy"
  PW=`openssl rand -base64 32`
  echo $PW | htpasswd -ic nginx-auth/Staticfile.auth $USER_NAME

  # the perl line strips out the incorrect credentials to avoid confusion
  (./make-proxy.sh -p -s $SERVICE_NAME -n ${SERVICE_NAME}-kibana -d $APP_DOMAIN -g "./nginx-auth" | perl -n -e 's/https:.+@/https:\/\//; print') || bail "Kibana proxy creation failed"
  echo "Your Kibana proxy credentials:"
  echo "Username: $USER_NAME"
  echo "Password: $PW"
}

#############################
# run script
parse_options $@
create_service
bind_service
echo ""
create_proxy
echo "Done"

