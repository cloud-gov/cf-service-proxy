# cf-service-proxy
Create a proxy for Clound Foundry service instances.

This app assumes you have a credential providing service bound to an existing application. It creates and nginx proxy to access the backing service remote.

**Note:**

This script does not add authentication. Have a look at [basic authentication](https://github.com/cloudfoundry/staticfile-buildpack#basic-authentication) for the staticfile buildpack (the foundation of this hack) if you need auth in addition or lieu of what your service offers.

### Usage:

Create a service proxy.

    make-proxy.sh -a APP -s SERVICE

Create and print the resulting connection string.

    make-proxy.sh -a APP -s SERVICE -p

Create and **only** print the resulting connection string.

    make-proxy.sh -a APP -s SERVICE -up

### Todo:

- Keep API results to avoid redundant calls.
- Add a switch to generate `Staticfile.auth`.
