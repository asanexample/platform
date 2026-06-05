{{/*
Common labels stamped on every ClusterPolicy.
Usage:  labels:
          {{- include "kpp.labels" . | nindent 4 }}
*/}}
{{- define "kpp.labels" -}}
app.kubernetes.io/managed-by: terraform
app.kubernetes.io/part-of: kyverno-platform-policies
{{- range $k, $v := .Values.commonLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/*
namespaceSelector matching tenant namespaces (those carrying the tenant label).
Usage (under a resources: entry):
          {{- include "kpp.tenantNamespaceSelector" . | nindent 6 }}
*/}}
{{- define "kpp.tenantNamespaceSelector" -}}
namespaceSelector:
  matchExpressions:
    - key: {{ .Values.tenantNamespaceLabel }}
      operator: Exists
{{- end -}}

{{/*
Exclude block listing infra namespaces — for namespaced policies so Kyverno never gates
platform/system workloads.
Usage:  {{- include "kpp.excludeInfra" . | nindent 2 }}
*/}}
{{- define "kpp.excludeInfra" -}}
exclude:
  any:
    - resources:
        namespaces:
{{- range .Values.excludeNamespaces }}
          - {{ . }}
{{- end }}
{{- end -}}

{{/*
Build a Kyverno image pattern ("reg1/* | reg2/*") from allowedRegistries.
Usage:  image: "{{ include "kpp.registryPatterns" . }}"
*/}}
{{- define "kpp.registryPatterns" -}}
{{- $p := list -}}
{{- range .Values.allowedRegistries -}}{{- $p = append $p (printf "%s/*" .) -}}{{- end -}}
{{- join " | " $p -}}
{{- end -}}

{{/*
Precondition skipping platform/system principals — for CLUSTER-SCOPED policies (RBAC bindings,
default-namespace) that cannot be scoped by namespace label. Relies on Kyverno set-operator
wildcard support.
Usage:  {{- include "kpp.skipPlatformPrincipals" . | nindent 4 }}
*/}}
{{- define "kpp.skipPlatformPrincipals" -}}
preconditions:
  all:
    - key: "{{`{{ request.userInfo.username }}`}}"
      operator: AnyNotIn
      value:
{{- range .Values.excludePrincipals }}
        - {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
Fetch the projected Team CR (the envelope) for the XTenant under review — used by the envelope policy
(restrict-tenant-envelope). default {} so a missing Team doesn't hard-error: the team-must-exist rule
flags that case and the other rules gate on kpp.teamExistsPrecondition.
Usage (under a rule):  {{- include "kpp.teamContext" . | nindent 6 }}
*/}}
{{- define "kpp.teamContext" -}}
context:
  - name: team
    apiCall:
      urlPath: "/apis/platform.refplat.org/v1alpha2/teams/{{`{{ request.object.spec.team }}`}}"
      default: {}
{{- end -}}

{{/*
Precondition: only evaluate when the Team CR resolved (its name matches the requested team). Keeps the
envelope rules from erroring / double-flagging when the Team is missing (team-must-exist owns that case).
Usage (under a rule):  {{- include "kpp.teamExistsPrecondition" . | nindent 6 }}
*/}}
{{- define "kpp.teamExistsPrecondition" -}}
preconditions:
  all:
    - key: "{{`{{ team.metadata.name || '' }}`}}"
      operator: Equals
      value: "{{`{{ request.object.spec.team }}`}}"
{{- end -}}
