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
namespaceSelector matching environment namespaces (those carrying the environment label).
Usage (under a resources: entry):
          {{- include "kpp.environmentNamespaceSelector" . | nindent 6 }}
*/}}
{{- define "kpp.environmentNamespaceSelector" -}}
namespaceSelector:
  matchExpressions:
    - key: {{ .Values.environmentNamespaceLabel }}
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
