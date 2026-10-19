# Site router

A routed site-to-site IPsec gateway for tenants of [Cozystack](https://cozystack.io). A tenant makes a `SiteRouter` application, gives it the address of the remote end and the networks behind it, and gets a gateway that is a virtual machine in the tenant namespace. The address of the tunnel and the pre-shared key show in the dashboard, and the workloads of the tenant reach the remote networks through the gateway.

The gateway is run by [site-router-operator](https://github.com/aenix-io/site-router-operator), on the appliance image of [barerouter](https://github.com/aenix-io/barerouter). This catalog packages the operator, the connector that routes to the gateway on kube-ovn, and the application the tenant sees. Everything it deploys is open source, which is why it is in `free/`.

## What it needs

- Cozystack with the marketplace, which is the release 1.7 line (`cozypkg v1.7.0` or a later release candidate). The platform sources the package depends on are `cozystack.networking`, `cozystack.kubevirt`, `cozystack.kubevirt-cdi` and `cozystack.cozystack-engine`.
- kube-ovn as the network of the pods, with Cilium alongside it, which is how Cozystack runs. The connector in this catalog is the one for kube-ovn, and the gateways are isolated with Cilium policies. The namespace of a tenant has to let the pods that send through the gateway in, and the gateway out to the world; the baseline policies of a Cozystack tenant namespace do.
- A load balancer for Services of type LoadBalancer, which the gateway publishes its tunnel on.

## Install

Connect the repository and install the package.

```bash
cozypkg tap oci://ghcr.io/aenix-io/cozyapps/site-router:v0.1.0
```

The operator refuses to start without the networks of the cluster, so they are given when the package is installed. They are not taken from anywhere, so that the package does not depend on the network the cluster runs: they are the pod network, the service network, and the join network when the network has one. On a Cozystack cluster they are what the platform was installed with:

```bash
kubectl get package cozystack.cozystack-platform \
  --output jsonpath='{.spec.components.platform.values.networking}'
```

Write them in a `Package` and create it. `cozypkg add` asks for no values, so the package is created from the manifest:

```yaml
# package.yaml
apiVersion: cozystack.io/v1alpha1
kind: Package
metadata:
  name: aenix.site-router
spec:
  variant: default
  components:
    site-router-operator:
      values:
        config:
          # Where the operator runs, which is the pod network.
          managementCIDR: 10.244.0.0/16
          clusterNetworks:
            podCIDR: 10.244.0.0/16
            serviceCIDR: 10.96.0.0/16
            # Only where the network has a join network, as kube-ovn does.
            joinCIDR: 100.64.0.0/16
```

```bash
kubectl apply --filename package.yaml
```

A network that a tenant asks for and that overlaps one of these is refused by the operator, so they have to be right.

## Use

The `SiteRouter` application appears in the dashboard catalog. A tenant gives it the address of the remote end (`peer.address`), the networks behind it (`remoteCIDRs`), and optionally static routes, BGP, and the size of the gateway. The parameters are in [packages/apps/site-router](packages/apps/site-router/README.md). Once the gateway is up, which takes some minutes while its disk is imported, the dashboard shows the address of the tunnel and the pre-shared key to configure the remote end with.

## Layout

```text
packages/
  core/platform/sources/site-router.yaml      # PackageSource aenix.site-router
  system/site-router-operator/                # the released chart of the operator, as it is
  system/site-router-kube-ovn-connector/      # the manifests of the connector, from its tag
  apps/site-router/                           # the application the tenant sees
  system/site-router-rd/                      # its ApplicationDefinition
  library/cozy-lib/                           # a copy of the library of the platform
ci/                                           # example values for `make render`
hack/                                         # the script that fills the ApplicationDefinition
```

`make generate` makes the schema of the application from `values.yaml` and puts it in the ApplicationDefinition. `make validate` runs `cozypkg validate`, and `make render` renders the three charts with the example values. `make update-operator` and `make update-connector` move the operator and the connector to the version named in the Makefile of their directory.

## The copy of cozy-lib

`packages/library/cozy-lib` is an exact copy of `packages/library/cozy-lib` of the platform at the tag `v1.7.0-rc.1` (commit `38d6ac7efb8a568f492b2e6e28c3a9d81df3286b` of cozystack). The application chart uses it for the roles of the tenants on the dashboard resource map. Nothing keeps the copy up to date: it has no version of its own, and it reads values by names that the platform may change, so when the platform moves, compare it with the copy before the next release of this catalog.

## Publishing

A release is a tag `site-router/vX.Y.Z` of this repository. The workflow validates the repository and pushes `packages/` as `oci://ghcr.io/aenix-io/cozyapps/site-router:vX.Y.Z`, signed with cosign. To move to a new version of the operator, run `make update-operator` (and `make update-connector`) in a branch, check what changed, and release.

## Not done yet

- The package has not been installed on a cluster. It validates and renders, and nothing more is claimed.
- The release of the application is not tied to the state of the gateway: it is ready when its objects are applied, and the dashboard shows the conditions of the gateway. Tying it to the `Ready` condition needs the timeouts of the release to be set for a gateway that takes minutes to come up.
- Only the connector for kube-ovn is here. The variant for another network is another variant of the `PackageSource`.
