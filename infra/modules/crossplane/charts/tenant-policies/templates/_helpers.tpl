{{/*
Common labels stamped on every ClusterPolicy.
Usage:  labels:
          {{- include "ktp.labels" . | nindent 4 }}
*/}}
{{- define "ktp.labels" -}}
app.kubernetes.io/managed-by: terraform
app.kubernetes.io/part-of: crossplane-tenant-policies
{{- range $k, $v := .Values.commonLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/*
Precondition skipping platform/system principals — for the CLUSTER-SCOPED control-plane policy (XTenant /
ProviderConfig are cluster/control-plane resources that cannot be scoped by tenant namespace). Relies on
Kyverno set-operator wildcard support.
Usage:  {{- include "ktp.skipPlatformPrincipals" . | nindent 6 }}
*/}}
{{- define "ktp.skipPlatformPrincipals" -}}
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
Fetch the projected Team CR (the envelope) for the XTenant under review — used by the envelope policy.
default {} so a missing Team doesn't hard-error: the team-must-exist rule flags that case and the other rules
gate on ktp.teamExistsPrecondition.
Usage (under a rule):  {{- include "ktp.teamContext" . | nindent 6 }}
*/}}
{{- define "ktp.teamContext" -}}
context:
  - name: team
    apiCall:
      urlPath: "/apis/platform.refplat.org/v1alpha2/teams/{{`{{ request.object.spec.team }}`}}"
      default: {}
{{- end -}}

{{/*
Precondition: only evaluate when the Team CR resolved (its name matches the requested team). Keeps the
envelope rules from erroring / double-flagging when the Team is missing (team-must-exist owns that case).
Usage (under a rule):  {{- include "ktp.teamExistsPrecondition" . | nindent 6 }}
*/}}
{{- define "ktp.teamExistsPrecondition" -}}
preconditions:
  all:
    - key: "{{`{{ team.metadata.name || '' }}`}}"
      operator: Equals
      value: "{{`{{ request.object.spec.team }}`}}"
{{- end -}}

{{/*
v3 (ADR-067/069): context for the XEnvironment envelope — the projected Team CR (envelope) AND the projected
Product CR (team-ownership + tenancy). The Product CR name is "<team>-<product>" (the registry metadata.name).
Usage (under a rule):  {{- include "ktp.envContext" . | nindent 6 }}
*/}}
{{- define "ktp.envContext" -}}
context:
  - name: team
    apiCall:
      urlPath: "/apis/platform.refplat.org/v1alpha3/teams/{{`{{ request.object.spec.team }}`}}"
      default: {}
  - name: product
    apiCall:
      urlPath: "/apis/platform.refplat.org/v1alpha3/products/{{`{{ request.object.spec.team }}-{{ request.object.spec.product }}`}}"
      default: {}
{{- end -}}

{{/* Precondition: only evaluate when the Product CR resolved. */}}
{{- define "ktp.productExistsPrecondition" -}}
preconditions:
  all:
    - key: "{{`{{ product.metadata.name || '' }}`}}"
      operator: Equals
      value: "{{`{{ request.object.spec.team }}-{{ request.object.spec.product }}`}}"
{{- end -}}
