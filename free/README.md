# free

The catalog of the applications that are open source throughout — both the code here and everything it deploys.

Nothing in this section requires an entitlement from anyone. If an application here turns out to pull something that is not open source, it belongs in [`contrib/`](../contrib/) instead, and moving it is a bug fix, not a policy change.

The catalog is one OCI artifact, `ghcr.io/aenix-io/cozyapps/free`, with every application below in it, released by a tag `free/vMAJOR.MINOR.PATCH`. Connect it to a Cozystack cluster, and each application shows in the catalog of the platform:

```bash
cozypkg tap oci://ghcr.io/aenix-io/cozyapps/free:<version>
```

## Applications

An application is a directory with a `packages/` in it. The `packages/` of all of them are merged into the artifact by [`hack/stage-section.sh`](../hack/stage-section.sh).

| Application | What it is |
| --- | --- |
| [`site-router/`](site-router/) | A routed site-to-site IPsec gateway for tenants: the operator, the connector for kube-ovn, and the application. |
