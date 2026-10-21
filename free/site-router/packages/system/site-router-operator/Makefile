# The chart in this directory is the released chart of the site-router operator, as it
# was published, and nothing else of it is edited here: what this catalog decides
# is in values-cozystack.yaml. `make update` replaces the chart with the version
# named below.
CHART   := oci://ghcr.io/aenix-io/charts/site-router-operator
VERSION := 0.1.1

# What the released chart holds, which `make update` removes before it puts the
# new one in place.
UPSTREAM := Chart.yaml values.yaml values.schema.json .helmignore templates files

.PHONY: update
update:
	rm -rf $(UPSTREAM) .update
	helm pull $(CHART) --version $(VERSION) --untar --untardir .update
	cp -r .update/site-router-operator/. .
	rm -rf .update
