# Site router

A routed site-to-site IPsec gateway for the tenants of [Cozystack](https://cozystack.io). A tenant creates a `SiteRouter` application, gives it the address of the remote end and the networks behind it, and gets a gateway: a virtual machine in the tenant namespace that holds an IPsec tunnel to the remote site. The workloads of the tenant reach the remote networks through that gateway, and the remote networks reach the workloads of the tenant through it.

This document is the whole guide. It says what the catalog is, how it works inside Cozystack, how an administrator installs it, how a tenant uses it, how the remote end is configured, what to look at when something is wrong, how it is upgraded and removed, and how it is released.

- [What it is](#what-it-is)
- [What is in the catalog](#what-is-in-the-catalog)
- [How it works in Cozystack](#how-it-works-in-cozystack)
- [Requirements](#requirements)
- [Install](#install)
- [Use the application](#use-the-application)
- [Configure the remote end](#configure-the-remote-end)
- [Check it and fix it](#check-it-and-fix-it)
- [Upgrade and remove](#upgrade-and-remove)
- [What has been checked and what has not](#what-has-been-checked-and-what-has-not)
- [Releases and versions](#releases-and-versions)
- [Working on the catalog](#working-on-the-catalog)

## What it is

The gateway is run by [site-router-operator](https://github.com/aenix-io/site-router-operator) on the appliance image of [barerouter](https://github.com/aenix-io/barerouter). The operator watches a `SiteRouter` resource, makes a KubeVirt virtual machine from the image, pushes the IPsec configuration to it, and asks the network of the cluster to route the remote networks to it. This catalog packages the operator, the part that does the routing on kube-ovn, and the application a tenant sees, so that a Cozystack administrator installs them with `cozypkg` and a tenant uses them like any other application of the platform. Everything it deploys is open source, which is why it is in `free/`.

```text
  tenant namespace                                                      remote site

  pod ---- route to the remote networks via the gateway ----+
  pod ---- (the namespace holds the route)                  v
                                                    +----------------+
                                                    |  gateway VM    |==== IPsec, UDP 500 and 4500 ====> remote device --- remote networks
                                                    |  (one pod)     |     through the tunnel Service
                                                    +----------------+     (a LoadBalancer address)
  pod <---- only traffic from the remote networks, only to these pods ----+
```

Traffic that a workload sends to a remote network goes to the gateway, is encrypted there, and leaves through the tunnel. Traffic that comes back, and traffic that the remote side starts, is decrypted in the gateway and admitted to the pods of the tenant namespace only from the remote networks that were asked for, and to nothing else.

## What is in the catalog

A catalog is one directory that is released as one unit (see [Releases and versions](#releases-and-versions)). `packages/` is what a cluster receives:

| Directory under `packages/` | What it is |
| --- | --- |
| `core/platform/sources/site-router.yaml` | The `PackageSource` named `aenix.site-router`. It says what to install, in what order, and what has to exist first. |
| `system/site-router-operator` | The Helm chart of the operator, as released upstream (0.1.1), with the choices of this catalog in `values-cozystack.yaml`: the engine and the images of the appliance, by digest. |
| `system/site-router-kube-ovn-connector` | The connector that makes kube-ovn route the remote networks to the gateway. A chart made from the deploy files of the operator release of the same version. |
| `apps/site-router` | The chart of the application. It turns the values of the tenant into a `SiteRouter`, a `WorkloadMonitor` and the access rules for the dashboard. |
| `system/site-router-rd` | The `ApplicationDefinition` that registers the application in the platform, and the role that lets tenant admins write it. |
| `library/cozy-lib` | A copy of the helper library of the platform, which the application chart uses. |

## How it works in Cozystack

Cozystack installs software as packages. A `PackageSource` says what a package is made of, a `Package` asks for it to be installed, and the platform turns the components of the package into Flux `HelmRelease` objects. `cozypkg` adds a marketplace on top: a catalog is a tree of packages published as an OCI artifact, and an administrator connects it to a cluster with `cozypkg tap`.

What happens, in order:

1. `cozypkg tap oci://<registry>/<path>:<tag>` makes a Flux `OCIRepository` in `cozy-system` that follows the artifact, and registers the `PackageSource` objects the artifact carries under the names it declares (`aenix.site-router` here). Names that begin with `cozystack.` or `community.` are reserved, and a name that clashes with a core one is refused. It also makes an empty `Package` of the same name, which marks the catalog as registered. Tap checks the structure of the artifact and does not verify its signature.
2. The `Package` is where the administrator gives the values of the install. This package needs the networks of the cluster (see [Install](#install)), and the operator release fails on its schema until they are there. Applying a `Package` with the values over the empty one is what installs the catalog.
3. The `PackageSource` has one variant, `default`, for a cluster whose network is kube-ovn. It depends on four platform packages: `cozystack.networking`, `cozystack.kubevirt`, `cozystack.kubevirt-cdi` and `cozystack.cozystack-engine`. The platform installs nothing of this catalog until they are ready. The `Package` shows each of them under `status.dependencies`.
4. The platform makes three `HelmRelease` objects from the components:
   - `site-router-operator` in the namespace `cozy-site-router`: the operator, its CRDs (`SiteRouter` and `Forwarder`, group `siterouter.aenix.io`) and its configuration.
   - `site-router-kube-ovn-connector` in the namespace `site-router-kube-ovn-connector`, after the operator: the connector.
   - `site-router-rd` in `cozy-system`, after both: the `ApplicationDefinition` and a role.
5. The fourth component, `apps/site-router`, is not a release of its own. The platform keeps it as a Flux `ExternalArtifact` (named `aenix-site-router-default-site-router` in `cozy-system`) and uses it as the chart of the application. The `ApplicationDefinition` points at it.
6. The `ApplicationDefinition` registers the kind `SiteRouter` in the API group `apps.cozystack.io`, the same group as `Postgres` or `Kubernetes`, with the schema of the application. From then on a tenant creates a `SiteRouter` in the namespace of the tenant, and the platform makes a `HelmRelease` named `site-router-<name>` there, from the chart of the application with the values of the tenant. The dashboard puts the application in the category NaaS, with the tags vpn, ipsec and networking.
7. The chart of the application renders a `SiteRouter` of the operator (group `siterouter.aenix.io`) named `<name>`, a `WorkloadMonitor`, and a `ConfigMap`, `Role` and `RoleBinding` that let the tenant read its gateway in the dashboard.
8. The operator sees the `SiteRouter` and makes, all named `site-router-<name>` and owned by it:
   - a `VirtualMachine`, with a `DataVolume` for its boot disk (12 GiB, imported from the appliance image by CDI) and Secrets for its seed configuration and the key of its management API,
   - the Secret `site-router-<name>-psk` with the pre-shared key, generated by the operator,
   - the Service `site-router-<name>-tunnel`, of type LoadBalancer, with UDP ports 500 and 4500 and `externalTrafficPolicy: Local`. The address the load balancer gives is the address of the tunnel, and the gateway uses it as its IKE identity,
   - two `CiliumNetworkPolicy` objects: one admits the tunnel from the world and the management API from the operator only, the other denies the gateway the link-local range,
   - a `Forwarder`, which is how the operator asks the cluster network to route to the gateway.
9. When the virtual machine runs, the operator calls the management API of the gateway and applies the configuration: the IPsec peer, the routes, BGP if asked, and a firewall that drops everything not allowed. It then reads the configuration back and confirms that the source filter is in place, and it watches the state of the tunnel.
10. The connector serves the `Forwarder`. It lets the gateway pod forward traffic (it turns off the source check that kube-ovn does on the pod), and writes the routes to the remote networks, with the gateway pod as next hop, in the annotation `ovn.kubernetes.io/routes` of the tenant namespace. The `kubeovn-webhook` of Cozystack copies that annotation onto each pod when the pod is created. kube-ovn applies the routes of a pod only at that moment, so a pod that was created before the gateway has to be restarted to get them. The operator reports such pods in the condition `RoutesProgrammed`.
11. The tenant reads the address of the tunnel from the Service and the pre-shared key from the Secret, and configures the remote device with them.

The operator and the connector never touch the network of the cluster in any other way, and the connector changes on a pod or a namespace only the annotations it owns, which an admission policy that it ships enforces.

### Who can do what

- A tenant admin creates, changes and deletes `SiteRouter` applications. The platform lists by name the kinds a tenant admin may write, so this catalog adds a `ClusterRole`, `cozy:site-router:admin`, aggregated into the admin role.
- Every role from view up reads the applications and the Services of the tenant, so the address of the tunnel is visible to all of them.
- The pre-shared key is a `TenantSecret` named `site-router-<name>-psk`, and `use`, `admin` and `super-admin` read it. `view` does not. The other Secrets of the gateway (the key of the management API and the seed) are not shown to the tenant.
- The tenant does not write the `SiteRouter` of the operator, only the application. The `Role` the application chart makes gives `use` and above read access to that one resource, for the dashboard. This matters because the resource has two fields that reach further than a gateway does (`peer.auth.secretRef` and the annotation `siterouter.aenix.io/upgrade-to`), and the application exposes neither of them.

## Requirements

- Cozystack with the marketplace, which is the release 1.7 line. Use `cozypkg` of that release (`v1.7.0` or a release candidate from `v1.7.0-rc.1`).
- The platform packages `cozystack.networking` (kube-ovn and Cilium), `cozystack.kubevirt`, `cozystack.kubevirt-cdi` and `cozystack.cozystack-engine`. A stock Cozystack install (the `isp-full` variant) has them. `isp-slim` has no kube-ovn and no KubeVirt, so it cannot run this catalog.
- kube-ovn as the network of the pods, with Cilium alongside it, which is how Cozystack runs. The connector in this catalog is the one for kube-ovn, and the gateways are isolated with Cilium policies. The namespace of the tenant has to let the pods that send through the gateway reach it, and let the gateway out to the world. The baseline policies of a Cozystack tenant namespace do both.
- A load balancer for Services of type LoadBalancer, which the gateway publishes its tunnel on (MetalLB on a stock install), with free addresses in the pool, one per gateway.
- A default storage class, or one named in the application: the boot disk of a gateway is 12 GiB.
- x86_64 nodes. The appliance image is for amd64 only.
- For the gateway of a tenant, 2 CPUs and 2 GiB of memory by default, which the tenant can change.
- The remote device has to speak IKEv2 with a pre-shared key, and to accept UDP encapsulation on ports 500 and 4500.

## Install

This is done once per cluster by the administrator.

### 1. Connect the catalog

```bash
cozypkg tap oci://ghcr.io/aenix-io/cozyapps/site-router:v0.1.0
```

Tapping needs cluster-admin, and it can be run again safely. Check it:

```bash
cozypkg list
```

lists `aenix.site-router`, and `kubectl get packagesource aenix.site-router` is `Ready` ("generated 4 artifact(s)").

At this point the `Package` exists and is empty. The release of the operator fails with a message that begins `values don't meet the specifications of the schema` and names `config.managementCIDR` and `config.clusterNetworks`. That is expected, the next step fixes it.

### 2. Find the networks of the cluster

The operator needs the networks of the cluster, and refuses to start without them. They are not read from anywhere, so that the package does not depend on the network the cluster runs, and they are given once, here. There are four:

| Value | What it is |
| --- | --- |
| `config.clusterNetworks.podCIDR` | The network of the pods. |
| `config.clusterNetworks.serviceCIDR` | The network of the Services. |
| `config.clusterNetworks.joinCIDR` | The join network, for a network that has one, as kube-ovn does. |
| `config.managementCIDR` | Where the operator runs, which is the pod network. The management API of a gateway answers only to this network. |

A network that a tenant asks for and that overlaps one of these is refused by the operator, and the operator refuses to guess, so they have to be right. On a Cozystack cluster they are the values the platform was installed with:

```bash
kubectl get package cozystack.cozystack-platform \
  --output jsonpath='{.spec.components.platform.values.networking}'
```

```json
{"joinCIDR":"100.64.0.0/16","podCIDR":"10.244.0.0/16","podGateway":"10.244.0.1","serviceCIDR":"10.96.0.0/16"}
```

### 3. Give them to the package

`cozypkg add` asks for no values, so write them in a `Package` and apply it over the one that tap made:

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

`kubectl` warns that the `Package` has no `last-applied-configuration` annotation, because tap made it. The warning is harmless.

Other keys of the operator configuration go under the same `config` (where gateways are scheduled, the storage class of their disks, the class of the load balancer, the policy of upgrades). They are documented in the [install guide of the operator](https://github.com/aenix-io/site-router-operator/blob/main/docs/install.md). The engine and the images of the appliance are fixed by this catalog in `values-cozystack.yaml`, and are not to be changed here.

### 4. Check the install

Give it two or three minutes. Then:

```bash
kubectl get hr --all-namespaces | grep site-router
```

shows three releases, `site-router-operator`, `site-router-kube-ovn-connector` and `site-router-rd`, all `True`. The pod of the operator runs in `cozy-site-router` and the pod of the connector in `site-router-kube-ovn-connector`:

```bash
kubectl get pods --namespace cozy-site-router
kubectl get pods --namespace site-router-kube-ovn-connector
```

The application kind is registered when `kubectl api-resources --api-group=apps.cozystack.io` lists `siterouters`. The API server can take a short while to show a new kind.

## Use the application

A tenant needs the role `admin` of its tenant to create the application. Everything below is in the namespace of the tenant, which is `tenant-root` for the root tenant and `tenant-<name>` for the others.

### Create a gateway

In the dashboard, the application is `Site Router` in the category NaaS. From the command line:

```yaml
apiVersion: apps.cozystack.io/v1alpha1
kind: SiteRouter
metadata:
  name: office
  namespace: tenant-root
spec:
  peer:
    address: 203.0.113.10
  remoteCIDRs:
    - 192.0.2.0/24
    - 198.51.100.0/24
```

```bash
kubectl apply --filename office.yaml
```

The name is at most 40 characters. It becomes part of the names of everything the gateway makes, and cannot be changed later.

The parameters:

| Parameter | What it does |
| --- | --- |
| `peer.address` | The IP address or DNS name of the remote end. Leave it empty while it is not known, for example when the remote side is to call first. |
| `remoteCIDRs` | The IPv4 networks behind the remote end, up to 16. Traffic to them from the pods of the tenant goes to the gateway, and traffic from them is let through to the pods of the tenant. A network that no remote site can have (shorter than a /8, or in `0.0.0.0/8`, loopback, link-local or multicast) or that overlaps a network of the cluster is refused. |
| `staticRoutes` | Routes in the gateway itself, up to 16, each a `destination` (an IPv4 CIDR) and a `nextHop` (an IPv4 address). |
| `bgp.enabled`, `bgp.localASN`, `bgp.neighbors` | BGP between the gateway and the remote site. `localASN` is required when `enabled` is true. Each of up to 8 neighbors is an `address` and a `remoteASN`. |
| `resources.cpu`, `resources.memory` | The size of the gateway VM. 2 CPUs and 2Gi by default. |
| `storageClass` | The storage class of the boot disk. The default class of the cluster when empty. It cannot be changed after the gateway is created. |

The same table, as the platform generates it, is in [packages/apps/site-router/README.md](packages/apps/site-router/README.md). All values are validated twice, by the schema of the application and by the operator, which checks them against the real networks of the cluster. A value the operator refuses shows in the condition `Validated`.

### Wait for the gateway

The application is created at once, and the gateway takes a few minutes: the boot disk is imported, the virtual machine boots, and the operator configures it. On the cluster this catalog was checked on, the gateway was ready about two and a half minutes after the application was created.

```bash
kubectl get siterouters.siterouter.aenix.io --namespace tenant-root
```

```text
NAME     READY   TUNNEL ADDRESS   AGE
office   False   10.20.100.200    42s
```

Two resources are called `SiteRouter`. `kubectl get siterouters` shows the application, the one in `apps.cozystack.io`, and the application is ready as soon as its objects are applied, which does not say whether the gateway works. The state of the gateway, its tunnel and its routes is on the resource of the operator, `siterouters.siterouter.aenix.io`, whose conditions are:

| Condition | What it says |
| --- | --- |
| `Validated` | The spec is accepted: the networks are well formed and do not overlap the cluster. |
| `GatewayReady` | The virtual machine runs and the tunnel Service has an address. Reasons: `GatewayPending` (the machine is not running yet, with its phase), `TunnelAddressPending`, `PSKSecretPending`, `Upgrading`. |
| `Configured` | The configuration is applied to the gateway. `ConfigApplied` when it is. |
| `RoutesProgrammed` | The cluster routes the remote networks to the gateway. `PendingWorkloads` lists pods that were created before the routes and must be restarted. |
| `TunnelEstablished` | The tunnel is up. `tunnel-0=Down` while it is not. |
| `Ready` | All of the above. |

```bash
kubectl get siterouters.siterouter.aenix.io --namespace tenant-root office \
  --output jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
```

### Get the address and the key

The address of the tunnel is the external address of the Service, and it is also on the resource of the operator as `status.tunnelAddress`. The pre-shared key is in the Secret:

```bash
kubectl get service site-router-office-tunnel --namespace tenant-root
kubectl get tenantsecret site-router-office-psk --namespace tenant-root \
  --output jsonpath='{.data.psk}' | base64 --decode
```

Both are for the remote device, in the next section. The key is generated once and stays the same as long as the gateway exists. Treat it as a password.

### Reach the remote networks from the workloads

Every pod created in the namespace after the gateway is ready gets a route to each remote network, with the gateway as next hop. From a pod:

```bash
kubectl exec --namespace tenant-root <pod> -- ip route
```

shows lines like `192.0.2.0/24 via 10.244.0.124 dev eth0`. Pods that existed before the gateway do not have the routes until they are restarted, because kube-ovn applies routes when a pod is created, and the condition `RoutesProgrammed` names them. Restart them (delete a pod of a Deployment and it comes back with the routes). The gateways themselves are not in the scope, and a Service that carries a gateway's tunnel is left alone.

What the gateway lets in from the remote side: traffic from a remote network that was asked for, to the pods and Services of the tenant namespace, and the replies to traffic the pods started. Nothing else.

Two gateways in one namespace that ask for overlapping remote networks conflict. The one created first keeps the networks, the other is told `Conflict` and gets nothing new until the conflict is gone.

### Change and delete

Changing the values of the application changes the gateway. `storageClass` is the exception, it cannot be changed. Deleting the application deletes the gateway: its virtual machine, disk, Service and policies, and the routes of the namespace are withdrawn. The Secret with the pre-shared key stays, and has to be deleted by hand before a gateway of the same name is made (see [Remove an application](#remove-an-application)).

## Configure the remote end

The gateway holds one IKEv2 tunnel with a pre-shared key. The settings below are fixed by the engine, and the application does not change them. They come from the code of the engine and the appliance, and the tunnel was brought up against a second VM of the same appliance as the remote device. A device of another vendor has not been tried (see [what has been checked](#what-has-been-checked-and-what-has-not)).

| Setting | Value |
| --- | --- |
| Peer address on the remote device | The address of the tunnel (the external address of the Service `site-router-<name>-tunnel`). |
| Key exchange | IKEv2. |
| Authentication | Pre-shared key, the value of `site-router-<name>-psk`. |
| Identity of the gateway | Its own tunnel address, as an IP address. |
| Identity of the remote device | Its own address, the one given as `peer.address`, as an IP address. The gateway finds the key by that identity, so a device that presents another one (behind NAT, say) does not match. |
| IKE proposal | AES-256, SHA-256, Diffie-Hellman group 14 (2048-bit MODP). |
| IKE lifetime | 28800 seconds. |
| ESP proposal | AES-256, SHA-256, with PFS in group 14. |
| ESP lifetime | 3600 seconds. |
| Encapsulation | ESP in UDP is forced, so the device has to accept NAT traversal on ports 500 and 4500. |
| Mode | Tunnel. |
| Traffic selectors | On the gateway side `0.0.0.0/0`, and on the remote side each entry of `remoteCIDRs`, one child SA for each. So on the remote device the local selector is a network of `remoteCIDRs` and the remote selector is `0.0.0.0/0`. Make one tunnel (one child SA) on the remote device for each network. A device that offers two networks in one tunnel gets the first one only: in the test the second network had no SA and lost all its traffic. |

When `peer.address` is empty the gateway does not initiate, and waits for the remote device to call. The tunnel Service has to be reachable from the remote device on UDP 500 and 4500, which means the load balancer address has to be routable from there, and a firewall in between has to let those ports through.

## Check it and fix it

Start from the conditions of the operator resource (above) and the events:

```bash
kubectl describe siterouters.siterouter.aenix.io --namespace tenant-root office
kubectl get events --namespace tenant-root --sort-by=.lastTimestamp
```

The logs of the operator are `kubectl logs --namespace cozy-site-router deployment/site-router-operator`, and of the connector `kubectl logs --namespace site-router-kube-ovn-connector deployment/kube-ovn-connector`.

| What you see | What it means and what to do |
| --- | --- |
| The release `site-router-operator` fails with `values don't meet the specifications of the schema`. | The networks are not in the `Package` yet. Do [step 3](#3-give-them-to-the-package). |
| `cozypkg tap` times out pulling the artifact. | The registry was slow. Run it again, tapping is idempotent. |
| The `Package` has `dependencies` that are not ready. | A platform package that this catalog needs is not installed or not ready: `cozystack.networking`, `cozystack.kubevirt`, `cozystack.kubevirt-cdi`, `cozystack.cozystack-engine`. |
| `siterouters` is not in `kubectl api-resources` right after the install. | The API server shows new kinds after a short while. Check that `site-router-rd` is `True`. |
| A tenant admin gets `forbidden` creating a `SiteRouter`. | The role `cozy:site-router:admin` is made by `site-router-rd`. Check that release. |
| `Validated=False`. | The message names the field. A remote network that overlaps a network of the cluster, or that is a kind no remote site can have, is the usual cause. |
| `GatewayReady=False`, `the gateway VM is not running yet (phase "Pending")`. | The disk is being imported, or the machine cannot be scheduled. `kubectl get datavolume,pvc,vm,vmi --namespace <ns>`. A pending PVC points at the storage class, for example one with no provisioner, or no default class when the application names none. |
| `GatewayReady=False`, `Secret site-router-<name>-psk exists and is not controlled by this SiteRouter`. | A gateway of the same name was deleted before and left its Secret behind. Delete the Secret, see [Remove an application](#remove-an-application). |
| The Service `-tunnel` has no external address. | The load balancer has no free address in its pool. |
| The event `ConfigureFailed` with `i/o timeout` on port 443, once, at the start. | The guest was still booting. It goes away by itself. If it stays, the management API is not reachable from the operator: check that `managementCIDR` contains the pod network the operator is on. |
| `RoutesProgrammed=False`, `PendingWorkloads`. | The pods listed were created before the gateway and have no routes. Restart them. |
| `TunnelEstablished=False`, `tunnel-0=Down`. | The remote end has not completed the handshake: the remote device is not configured or not reachable on UDP 500 and 4500, the key or the identities differ, or the proposals do not match. Look at the log of the remote device. |
| The tunnel is up, and one of two remote networks has no traffic. | The remote device offered both networks in one tunnel. Give it a tunnel for each network. |
| The remote end is a pod of the same cluster, and the handshake never completes. | The baseline of a tenant lets a pod send to `world` and to the namespaces of its own tenant only, so the gateway cannot answer a pod of another namespace, nor can that pod reach the gateway. `cilium-dbg monitor --type drop` on the node shows `Policy denied`. This is a test setup, a remote site outside the cluster does not meet it. |
| The application shows `Ready` and nothing works. | That is the release being applied, not the gateway. Read the conditions of `siterouters.siterouter.aenix.io`. |

## Upgrade and remove

### Remove an application

Delete the `SiteRouter` application. On the cluster this was checked on, the virtual machine, disk, Service, policies, the other Secrets and the routes of the namespace were gone in about half a minute.

The Secret with the pre-shared key was not. It is owned by the gateway, and the garbage collector of that cluster did not remove it after the gateway was gone (a plain Secret with the same kind of owner was collected at once, so the labels the platform puts on the secrets of an application are involved, and why is not known). A gateway created later under the same name finds the old Secret, and the operator will not take over a Secret it did not make, so it waits with `GatewayReady=False` and the message `Secret site-router-<name>-psk exists and is not controlled by this SiteRouter`. Until that is fixed, delete the Secret after deleting the application:

```bash
kubectl delete secret site-router-<name>-psk --namespace <namespace>
```

A new name does not meet the problem.

### Remove the catalog

Delete every `SiteRouter` application first. An application left when the operator is removed has nothing to clean it up.

```bash
cozypkg untap aenix.site-router --yes
```

removes the `PackageSource`, the `OCIRepository` and the registration `Package`, and with them the three releases and the `ApplicationDefinition`. It leaves what the operator chart marks to keep:

- the CRDs `siterouters.siterouter.aenix.io` and `forwarders.siterouter.aenix.io`, because deleting a CRD deletes every object of it, and with it every gateway,
- the namespaces `cozy-site-router` and `site-router-kube-ovn-connector`.

To remove them as well, once no `SiteRouter` remains:

```bash
kubectl delete crd siterouters.siterouter.aenix.io forwarders.siterouter.aenix.io
kubectl delete namespace cozy-site-router site-router-kube-ovn-connector
```

Tap and the install can be done again over what is left. That was checked: the three releases were ready again in a minute and a half.

### Move to a new version

A new version of the catalog is a new tag. Run `cozypkg tap` with it, the same way as the first time (`--tag` overrides the tag of the reference). The upgrade is not checked yet. What the new version changes is in the release notes of its tag, and a new version of the operator replaces the CRDs together with the chart, since the chart carries them as templates.

## What has been checked and what has not

Checked on a three-node Cozystack `v1.7.0-rc.1` (`isp-full`, kube-ovn, MetalLB, replicated storage), with the artifact pushed to an anonymous registry:

- `cozypkg validate` and `cozypkg push`, and tap of the pushed artifact,
- the install over the empty package of tap, the three releases, the application kind in the API,
- a gateway created as a tenant admin, ready in about two and a half minutes, the tunnel Service with a MetalLB address, the key visible to the tenant and the other Secrets not,
- a pod created afterwards in the tenant got the routes to both remote networks through the gateway,
- deleting the application, removing the catalog with `untap`, and installing it again over the CRDs that were left,
- creating a gateway under a name that had been used, which was refused until the old pre-shared key Secret was deleted by hand (see [Remove an application](#remove-an-application)),
- a real tunnel and real traffic. The remote device was a second VM of the same appliance, in another namespace, standing for two remote networks. The tenant admin set `peer.address` in the application and read the address and the key as a tenant, and the remote VM was given the same two facts. The tunnel came up (IKEv2, AES-256, SHA-256, group 14, ESP in UDP) and the operator went to `Ready` once the pod that was older than the routes was restarted. Both ways, for both remote networks: ping at about 1 ms with no loss, the source of the remote network kept as it was (the backend saw `192.0.2.1` and `198.51.100.7`), the path MTU 1326 found and reported by the gateway. Throughput: a stream from a tenant pod to the remote side 933 Mbit/s (two pods of the tenant on the same network reach 1.58 Gbit/s), UDP from the remote side 300 Mbit/s with 0.03% loss. TCP from the remote VM was 100 Mbit/s with the tunnel and 95 Mbit/s to a pod with no tunnel at all, so that number is the limit of the test VM and not of the gateway.

Not checked:

- A remote device of another vendor. The tunnel was tested against the same appliance, which is the same IPsec stack, so a proposal or identity quirk of another device would not show.
- A remote site that is outside the cluster. The remote VM was a pod of the same cluster, and the gateway reached it only after two policies were added to let the gateway and the remote namespace talk, which the baseline of a tenant does not allow. A real remote site is `world` and needs neither.
- BGP and static routes on a running gateway. The configuration is accepted and applied, and what the gateway then does with it has not been observed.
- The dashboard. The definition is there, and the pages have not been looked at.
- Tap from `ghcr.io`, and the publishing job of the workflow, which has not run yet.
- Upgrading from one version of the catalog to another.

Known limits:

- Only the connector for kube-ovn is here. Another network is another variant of the `PackageSource` with another connector.
- The release of the application is ready when its objects are applied. The platform does not tie it to the `Ready` condition of the gateway. Doing that needs timeouts of the release set for a gateway that takes minutes to come up, which has not been measured.
- The application cannot choose the IKE or ESP proposals, the lifetimes, or the identities.
- One tunnel and one remote device for each gateway.
- The gateway sends ICMP redirects to a pod that sends to a remote network (`Redirect Host (New nexthop: <remote address>)` in the output of `ping`, counted as errors). They did no harm in the test: no packet was lost and the routes of the pod did not change. Why the pod ignored them was not looked into.

## Releases and versions

The unit of a release is the catalog, as the design of the marketplace has it: a catalog is one OCI artifact that bundles all its applications, and the artifact carries the version. `free/site-router` is a catalog that holds one application at present, so a release of the catalog is a release of this application. Everything in its `packages/` (the operator, the connector, the application and its definition) is one artifact with one version. An administrator taps the catalog and gets all of it, and there is no way to take the application without the operator. A catalog could hold more applications, as more `PackageSource` files, and they would share its version. The name and the place of the directory are provisional: moving it changes the reference that is tapped and the tag prefix, and does not change the name `aenix.site-router` the cluster sees.

- A release is a tag `site-router/vMAJOR.MINOR.PATCH` (a suffix such as `-rc.1` is allowed), and the artifact is `ghcr.io/aenix-io/cozyapps/site-router:vMAJOR.MINOR.PATCH`. Another catalog in the repository has its own directory, its own workflow and its own tag prefix, so tags do not collide and the catalogs are released independently.
- The version of the catalog is its own. It does not follow the version of the operator, which is 0.1.1 at present, or the version of the application chart, which is 0.1.0. It changes whenever anything in `packages/` changes: a patch for a fix in a chart or a text, a minor for a new version of the operator or new values, a major for a change that needs an administrator to act, such as a renamed value.
- What a version contains is pinned inside it: the chart of the operator is a copy of the release (`packages/system/site-router-operator/Chart.yaml`), the images of the appliance are pinned by digest in `values-cozystack.yaml`, the image of the connector by tag in its `values.yaml`, and the copy of `cozy-lib` is a copy of `v1.7.0-rc.1` of Cozystack. A cluster that taps `v0.1.0` gets exactly those, whatever is released later.
- The workflow pushes the artifact, then signs its digest with cosign, keyless, as the workflow. The signature is made for the digest, because a tag can be moved, so tags of a release are not moved. Tap does not verify signatures. To verify one:

```bash
cosign verify ghcr.io/aenix-io/cozyapps/site-router@<digest> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/aenix-io/cozyapps/\.github/workflows/site-router\.yml@refs/tags/site-router/v'
```

To make a release: change what has to change in a branch, run `make validate render` here, merge it, and push the tag on `main`:

```bash
git tag --sign site-router/v0.1.1 --message 'site-router v0.1.1'
git push origin site-router/v0.1.1
```

The tag starts the workflow. It validates, pushes and signs. Then tap the new tag on a test cluster before telling anyone about it.

## Working on the catalog

```text
packages/
  core/platform/sources/site-router.yaml      # PackageSource aenix.site-router
  system/site-router-operator/                # the released chart of the operator, as it is
  system/site-router-kube-ovn-connector/      # the manifests of the connector, from its tag
  apps/site-router/                           # the application the tenant sees
  system/site-router-rd/                      # its ApplicationDefinition and the admin role
  library/cozy-lib/                           # a copy of the library of the platform
ci/                                           # example values for `make render`
hack/                                         # the script that fills the ApplicationDefinition
Makefile
```

- `make generate` makes the schema of the application from its `values.yaml` (with `cozyvalues-gen`) and puts it in the `ApplicationDefinition`. Run it after changing `packages/apps/site-router/values.yaml`.
- `make validate` runs `cozypkg validate`, the same check the workflow runs. It does not use `--helm-lint`: lint renders with default values, and the chart of the operator has no defaults for the networks, on purpose.
- `make render` renders the three charts with the example values in `ci/`.
- `make update-operator` pulls the chart of the version named in the Makefile of `packages/system/site-router-operator`, with no changes to it, so that an update is a pull and a diff. After it, check `values-cozystack.yaml` for the versions and digests of the appliance image that the operator release carries.
- `make update-connector` makes the chart of the connector from the deploy files of the tag named in its Makefile.

The platform gives every release of a package its cluster values, and the schema of the operator chart refuses a key it does not know, so the `PackageSource` carries the annotation `operator.cozystack.io/skip-cozystack-values: "true"`. What the operator needs of the cluster is given as values of the package instead.

### The copy of cozy-lib

`packages/library/cozy-lib` is an exact copy of `packages/library/cozy-lib` of the platform at the tag `v1.7.0-rc.1` (commit `38d6ac7efb8a568f492b2e6e28c3a9d81df3286b` of cozystack). A catalog can use a library only from its own artifact, and the application chart uses this one for the roles of the tenants on the dashboard resource map. Nothing keeps the copy up to date. It has no version of its own, and it reads values by names that the platform may change, so when the platform moves, compare it with the copy before the next release of this catalog.

### Checks on a pull request

The workflow `site-router` runs `make validate` and `make render` on every pull request that changes this directory, with the `cozypkg` of the Cozystack release the catalog is written for (`COZYPKG_VERSION` in the workflow). The `cozystack.*` names in `dependsOn` are reported as information only, because the validator cannot see the platform: a wrong name there is not caught until a cluster installs it.
