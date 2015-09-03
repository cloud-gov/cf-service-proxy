# cf-service-proxy
Create a proxy for Clound Foundry service instances.

This app assumes you have a credential providing service bound to an existing application. It creates and nginx proxy to access the backing service remote.

### Usage:

Create a service proxy.

    make-proxy.sh -a APP -s SERVICE

Create and print the resulting connection string.

    make-proxy.sh -a APP -s SERVICE -p

Create and **only** print the resulting connection string.

    make-proxy.sh -a APP -s SERVICE -up
