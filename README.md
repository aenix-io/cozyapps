# contrib

Contributed integrations for [Cozystack](https://cozystack.io) whose dependencies are licensed by their vendors rather than under an open-source licence.

> **This repository is not part of the Cozystack project and not part of the CNCF.** It is hosted and stewarded by [Ænix](https://aenix.io). Cozystack is a CNCF Sandbox project; nothing here is endorsed by, released by, or the responsibility of the CNCF or the Cozystack maintainers acting as such.

## Why this exists

Cozystack packages third-party software the way a Linux distribution does: an operator picks services from a catalog, and the platform runs them. Some software people want to run is not distributed under an open-source licence — Elasticsearch and its ECK operator under the Elastic License, or Flux packaged by ControlPlane under the AGPL with an enterprise tier.

Integrations for that software cannot live in the Cozystack repository, and not because nobody wants to maintain them: a CNCF project's dependencies must clear the foundation's licence policy, and these do not. Contributions that were otherwise welcome have been turned away on those grounds alone.

This repository is where they can live instead. The model is Debian's `contrib` area: the code here is free, and what it depends on is not.

## What is and is not here

Everything in this repository is Apache-2.0 and written for the purpose — charts, manifests, glue. **No vendor-licensed software is stored or redistributed here.** When an operator installs an integration, their own cluster pulls the vendor's images and charts from the vendor's own registries, at deploy time, under whatever terms the vendor sets.

That distinction is the whole design, not a technicality. It also means installing an integration may require an entitlement you have to hold yourself — an Elastic subscription, a ControlPlane licence. Each integration states which, in its own README, before you install anything.

## Relationship to the Cozystack catalog

An integration here is an ordinary external application catalog: you register it with your Cozystack installation and its applications appear alongside the built-in ones. Nothing needs to change in Cozystack itself, and removing the catalog removes the integrations.

Where the platform already satisfies a dependency with a free default, an integration here may offer an alternative to it rather than a replacement for it — the operator chooses, the default stays free.

## Contributing

Integrations are maintained by the people who contribute them. If you run one of these in production and are willing to keep it working, that is exactly who this is for.

Licensing rules for a contribution:

- the code you write is Apache-2.0;
- vendor software is fetched by the user's cluster from the vendor, never vendored here;
- the integration's README states the licence of every non-open-source component it pulls, and any entitlement the user must hold.

## Licence

Apache-2.0. See [LICENSE](LICENSE).

Cozystack is a trademark of the Linux Foundation. This project uses the name only to describe what its contents are for.
