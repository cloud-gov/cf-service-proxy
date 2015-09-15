# cf-service-proxy

Create a proxy for Cloud Foundry service instances.

### Examples

Create a service proxy.

    make-proxy.sh -s SERVICE_NAME

Create and print the resulting connection string.

    make-proxy.sh -s SERVICE_NAME -p

Create and **only** print the resulting connection string.

    make-proxy.sh -s SERVICE_NAME -up


### Switches

##### -s SERVICE_NAME (Required)

Name of the service instance to proxy.

**Example:** `redis`

##### -z SERVICE_PORT (Optional)

Destination service port being proxied.

**Example:** `"9200/tcp"`

**Default:** The `service_bindings.credentials.port` value is used. 

**Use:** Proxy a non-default port from a service instance which exposes multiple ports in `service_bindings.credentials.ports` key. For example, ELK might expose 5000, 5601, 9200 and 9300 for syslog, Kibana and Elasticsearch HTTP / Transport respectively.

##### -d PROXY_DOMAIN (Optional)

Domain portion of the proxy app route.

**Example:** `18f.gov`

**Default:** The first shared domain available to the org is used. 

**Use:** Force a specific domain to be used when creating the proxy route.

##### -n PROXY_NAME (Optional)

Hostname portion of the proxy app route.

**Example:** `myproject-dev-redis`

**Default:** The proxy app is created with the name `ORG_NAME-SPACE_NAME-SERVICE_NAME-proxy`.

**Use:** Force a specific domain to be used when creating the proxy route.

### Outputs

The script will create or update bindings for the service and proxy app as needed.

#### Creating

	Looking for jq.
	  - Found jq.
	Getting domains for ORG_NAME.
	Getting status for SERVICE_NAME.
	  - Checking service bindings for SERVICE_NAME.
	Creating temp app: placeholder-ED5B2D25-5A9D-4421-950C-BAFEE8B45E09
	Binding service to temp app: placeholder-ED5B2D25-5A9D-4421-950C-BAFEE8B45E09
	  - Checking service bindings for SERVICE_NAME.
	Deleting: placeholder-ED5B2D25-5A9D-4421-950C-BAFEE8B45E09
	Cleaning up: /tmp/placeholder-ED5B2D25-5A9D-4421-950C-BAFEE8B45E09
	Checking status for SERVICE_NAME-proxy.
	Creating SERVICE_NAME-proxy...
	
	Getting service credentials for SERVICE_NAME.
      Port: 12345
      IP: 10.10.10.1
	
	Getting app environment for SERVICE_NAME-proxy.
	! Proxy vars don't match.
	+ Injecting service credentials into SERVICE_NAME-proxy.
	  + Binding SERVICE_NAME-proxy to PROXY_HOST in 10.10.10.1.
	  + Binding SERVICE_NAME-proxy to PROXY_PORT in 12345.
	Checking status for SERVICE_NAME-proxy.
	- Finishing start of SERVICE_NAME-proxy.
	  - Getting credentials for SERVICE_NAME-proxy.
	Checking status for SERVICE_NAME-proxy.
	
	Access the the proxied service here:
	
	https://user:pass@proxy.domain
	Done.

#### Creating with Existing Bindings

	Looking for jq.
	  - Found jq.
	Getting domains for ed.
	Getting status for SERVICE_NAME.
	  - Checking service bindings for SERVICE_NAME.
	    - Found bindings.
	Checking status for SERVICE_NAME-proxy.
	Creating SERVICE_NAME-proxy...
	
	Getting service credentials for SERVICE_NAME.
      Port: 12345
      IP: 10.10.10.1
	
	Getting app environment for SERVICE_NAME-proxy.
	! Proxy vars don't match.
	+ Injecting service credentials into SERVICE_NAME-proxy.
	  + Binding SERVICE_NAME-proxy to PROXY_HOST in 10.10.10.1
	  + Binding SERVICE_NAME-proxy to PROXY_PORT in 12345.
	Checking status for SERVICE_NAME-proxy.
	- Finishing start of SERVICE_NAME-proxy.
	  - Getting credentials for SERVICE_NAME-proxy.
	Checking status for SERVICE_NAME-proxy.
	
	Access the the proxied service here:
	
	https://user:pass@proxy.domain
	Done.


#### Updating

	Looking for jq.
	  - Found jq.
	Getting domains for ORG_NAME.
	Getting status for SERVICE_NAME.
	  - Checking service bindings for SERVICE_NAME.
	    - Found bindings.
	Checking status for SERVICE_NAME.
	    - Skipping creation.
	    
    Getting service credentials for SERVICE_NAME.
      Port: 12345
      IP: 10.10.10.1

	Getting app environment for SERVICE_NAME-proxy.
	  - Getting credentials for SERVICE_NAME-proxy.
	Checking status for SERVICE_NAME-proxy.
	
	Access the the proxied service here:
	
    https://user:pass@proxy.domain

    Done.

# es-util.sh

A script to assist with creating, restoring and deleting Elasticsearch snapshots and repositories on S3 via the [cloud-aws plugin](https://github.com/elastic/elasticsearch-cloud-aws).

### Proxy Setup

Run `make-proxy.sh` to create the proxy and/or obtain credentials for `es-util.sh`.

### Elasticsearch Operations

Run `es-util.sh` with the provided credentials or include it inline with the `-u` and `-p` switches.


#### Export Connection String

Export your ES connection string to avoid re-running `make-proxy.sh` repeatedly.

```
export ES_CONNECTION=$(make-proxy.sh -s ELASTICSEARCH_SERVICE -d DOMAIN -up)
```

#### Create Snapshot

    es-util.sh -c REPO_NAME \
      -s BUCKET_SERVICE \
      -p $ES_CONNECTION \
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

#### List Snapshots

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
      -p $ES_CONNECTION \
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
      -p $ES_CONNECTION \
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

