# Run from free/site-router.
CHART  := packages/apps/site-router
OP     := packages/system/site-router-operator
CONN   := packages/system/site-router-kube-ovn-connector

.PHONY: generate
generate: ## Make the schema and the parameter table from values.yaml, and put them in the ApplicationDefinition.
	cozyvalues-gen -m siterouter -v $(CHART)/values.yaml -s $(CHART)/values.schema.json -r $(CHART)/README.md
	hack/update-appdef.sh

# `cozypkg validate --helm-lint` is not used: it lints with the default values, and
# the chart of the operator has none for the networks of the cluster on purpose, and
# it takes the library the application chart links in for a dependency the chart
# does not declare. `make render` renders the charts with values instead.
.PHONY: validate
validate: ## Validate the repository as the marketplace would.
	cozypkg validate .

.PHONY: render
render: ## Render the three charts with the example values, which checks them against their schemas.
	helm template site-router-operator $(OP) --namespace cozy-site-router \
		--values $(OP)/values.yaml --values $(OP)/values-cozystack.yaml --values ci/operator-values.yaml >/dev/null
	helm template site-router-kube-ovn-connector $(CONN) --namespace site-router-kube-ovn-connector >/dev/null
	# The application chart finds the library in charts/, where the platform links it
	# for the time of the work. The link is made here and taken away again.
	mkdir $(CHART)/charts
	ln -s ../../../library/cozy-lib $(CHART)/charts/cozy-lib
	helm template site-router-a $(CHART) --namespace tenant-acme --values ci/app-values.yaml >/dev/null; \
		status=$$?; rm -r $(CHART)/charts; exit $$status
	@echo "the three charts render"
	bash hack/test-psk.sh

.PHONY: update-operator update-connector
update-operator: ## Take the released chart of the operator that the Makefile of its directory names.
	$(MAKE) -C $(OP) update

update-connector: ## Make the manifests of the connector for the version that the Makefile of its directory names.
	$(MAKE) -C $(CONN) update
