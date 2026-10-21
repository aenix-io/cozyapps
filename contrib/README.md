# contrib

The catalog of the applications whose code is Apache-2.0 but which are licensed by their vendors.

The name is Debian's: *contrib* is free software that depends on something outside the free archive. The code in this directory is free. What it installs is not, and is never stored here — your cluster pulls it from the vendor at install time, on the vendor's terms.

The catalog is one OCI artifact, `ghcr.io/aenix-io/cozyapps/contrib`, with every application in this directory in it, released by a tag `contrib/vMAJOR.MINOR.PATCH`. There is no application yet, so there is nothing to release.

**Read the application's README before installing.** Several of these products forbid offering them to third parties as a hosted or managed service without a separate agreement — which is what running them on Cozystack as an operator amounts to. Each application states the licence of what it pulls and the entitlement you need.
