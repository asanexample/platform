{{/* Common labels stamped on every ClusterPolicy. */}}
{{- define "ksp.labels" -}}
app.kubernetes.io/managed-by: terraform
app.kubernetes.io/part-of: crossplane-service-grant-policies
{{- range $k, $v := .Values.commonLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/*
Precondition skipping platform/system principals — an ALLOW-LIST in effect (only these principals may author
a ServiceGrant), mechanically identical to ktp.skipPlatformPrincipals / kap.skipPlatformPrincipals: everyone
whose username IS in excludePrincipals/extraExcludePrincipals skips the rule (and is therefore allowed);
everyone else falls through to `deny: {}`.
Usage:  {{- include "ksp.skipAllowedPrincipals" . | nindent 6 }}
*/}}
{{- define "ksp.skipAllowedPrincipals" -}}
preconditions:
  all:
    - key: "{{`{{ request.userInfo.username }}`}}"
      operator: AnyNotIn
      value:
{{- range .Values.excludePrincipals }}
        - {{ . | quote }}
{{- end }}
{{- range .Values.extraExcludePrincipals }}
        - {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
ADR-101: the LIST of every XEnvironment on the cluster — used by the regulated-tier exclusion rule to resolve
whether a ServiceGrant's target/subject {team, product, stage} names an XEnvironment claim carrying a
hipaa/pci tier. Product/Team do NOT carry a tier (only the SET of tiers a Team allows, envelope.allowedTiers);
the concrete tier a specific Environment actually runs at lives on the XEnvironment claim itself
(spec.tier) — this is why the lookup is against xenvironments, not the Team/Product CRs ktp.envContext reads.

NO `default` is set (same fail-closed reasoning as ktp.serviceGrantsContext): a plain LIST call succeeds with
items: [] when nothing matches, so omitting `default` changes behavior only on a REAL fetch error (which then
denies via failurePolicy: Fail). NOTE the asymmetry vs ktp.serviceGrantsContext: this rule is "deny IF a match
resolves to hipaa/pci", not "deny unless a match is found" — so an empty/erroring result here fails OPEN for
the hipaa/pci check specifically (no evidence of regulated tier => admitted). That is an accepted, DELIBERATE
gap for this rule (the git-level validate-service-grants.sh independently resolves the same tier from the
actual claim file and rejects there too — a second, more complete layer), not an oversight; a stricter variant
that hard-denies whenever tier is UNRESOLVABLE is a reasonable v2 tightening if this proves insufficient.
Usage (under a rule):  {{- include "ksp.xenvironmentsContext" . | nindent 6 }}
*/}}
{{- define "ksp.xenvironmentsContext" -}}
context:
  - name: xenvironments
    apiCall:
      urlPath: "/apis/platform.refplat.org/v1beta1/xenvironments"
      jmesPath: "items"
{{- end -}}
