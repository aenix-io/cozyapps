{{/*
The name of the SiteRouter, which is the name of the application: the release is
named <prefix><application>, and the operator names the objects of a gateway after
the SiteRouter, so the prefix is left off. The operator takes a name of up to 40
characters.
*/}}
{{- define "site-router.name" -}}
{{- $name := .Release.Name | trimPrefix "site-router-" -}}
{{- if or (not $name) (gt (len $name) 40) -}}
{{- fail (printf "the name of the application has to be 1 to 40 characters, and is %q" $name) -}}
{{- end -}}
{{- $name -}}
{{- end -}}
