# The manifests in templates/ are the deploy files of the connector for kube-ovn at
# the tag of the operator named below, with the image in values.yaml and without the
# Namespace, which the platform makes for the component. `make update` makes them
# again for another version: set VERSION, run it, and commit what it changed.
SOURCE  := github.com/aenix-io/site-router-operator/connectors/kube-ovn/deploy
VERSION := 0.1.1

.PHONY: update
update:
	{ \
	  echo "# Made by 'make update' from $(SOURCE) at v$(VERSION), without the Namespace."; \
	  echo "# Edit the Makefile and run it again, not this file."; \
	  kubectl kustomize "$(SOURCE)?ref=v$(VERSION)" \
	    | yq eval-all 'select(.kind != "Namespace")' - \
	    | sed -E 's#^( +image: ).*$$#\1"{{ .Values.image.repository }}:{{ .Values.image.tag }}"#'; \
	} > templates/manifests.yaml
	sed -i.bak -E 's#^(version|appVersion): .*#\1: "$(VERSION)"#' Chart.yaml && rm Chart.yaml.bak
	sed -i.bak -E 's#^( +tag: ).*#\1"$(VERSION)"#' values.yaml && rm values.yaml.bak
