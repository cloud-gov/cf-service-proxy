# cf-service-proxy
Create a proxy for Clound Foundry service instances.

This app assumes you have a credential providing service bound to an existing application. It creates and nginx proxy to access the backing service remote.

**Note:**

This script does not add authentication. Have a look at [basic authentication](https://github.com/cloudfoundry/staticfile-buildpack#basic-authentication) for the staticfile buildpack (the foundation of this hack) if you need auth in addition or lieu of what your service offers.

## Usage:

Create a service proxy.

    make-proxy.sh -a APP_NAME -s SERVICE_NAME

Create and print the resulting connection string.

    make-proxy.sh -a APP_NAME -s SERVICE_NAME -p

Create and **only** print the resulting connection string.

    make-proxy.sh -a APP_NAME -s SERVICE_NAME -up

## es-util.sh

A script to assist with creating, restoring and deleting Elasticsearch snapshots and repositories on S3 via the [cloud-aws plugin](https://github.com/elastic/elasticsearch-cloud-aws).

### Proxy Setup

Run `make-proxy.sh` to obtain credentials for `es-util.sh`.

    Looking for jq.
      - Found jq.
    Getting status for eservice-proxy.
      Status: STARTED
        - Skipping creation.

    Getting credentials for APP_NAME service bindings.
      Port: 12345
      IP: 10.10.10.1

    - Getting credentials for SERVICE_NAME-proxy.

      - Access the the proxied service here:

    https://user:pass@proxy.domain

    - Finished.

### Elasticsearch Operations

Run `es-util.sh` with the provided credentials or include it inline with the `-u` and `-p` switches.

#### Create Snapshot

    es-util.sh -c REPO_NAME \
      -s BUCKET_SERVICE \
      -p $(make-proxy.sh -a APPNAME ELASTICSEARCH_SERVICE -up) \
      -n SNAPSHOT_NAME

**Output:**

    Looking for jq.
      - Found jq.
    Getting bindings for BUCKET_SERVICE.
    Attempting to create repo REPO_NAME.
      - result: {"acknowledged":true}
    Attempting to create snap SNAPSHOT_NAME.
      - result: {"accepted":true}
      - status: IN_PROGRESS
      - status: SUCCESS

#### List Snapshot

    Looking for jq.
      - Found jq.
    Getting bindings for BUCKET_SERVICE.
    Attempting to create repo REPO_NAME.
      - result: {"acknowledged":true}

**Output:**

    Snapshots:
      - name: SNAPSHOT_NAME
        - status: "SUCCESS"

#### Restore Snapshot

    es-util.sh -c REPO_NAME \
      -s BUCKET_SERVICE \
      -p $(make-proxy.sh -a APPNAME ELASTICSEARCH_SERVICE -up) \
      -n SNAPSHOT_NAME \
      -i INDEX_NAME \
      -r

**Output:**

    Looking for jq.
      - Found jq.
    Getting bindings for BUCKET_SERVICE.
    Attempting to create repo REPO_NAME.
      - result: {"acknowledged":true}
    Attempting to restore snap latest.
      - result: {"accepted":true}
      - status: 0.0%
      - status: 1.3%
      - status: 2.7%
      - status: 4.1%
      - status: 5.2%
      - status: 6.3%
      - status: 7.7%
      ...
      - status: 100.0%

#### Delete Snapshot

    es-util.sh -c REPO_NAME \
      -s BUCKET_SERVICE \
      -p $(make-proxy.sh -a APPNAME ELASTICSEARCH_SERVICE -up) \
      -d SNAPSHOT_NAME

**Output:**

    Looking for jq.
      - Found jq.
    Getting bindings for bservice.
    Attempting to create repo ed-college-choice-indexing.
      - result: {"acknowledged":true}
    Attempting to delete snap newsnap.
      - result: {"acknowledged":true}
    Success.

### Todo:

- Keep API results to avoid redundant calls.
- Add a switch to generate `Staticfile.auth`.
