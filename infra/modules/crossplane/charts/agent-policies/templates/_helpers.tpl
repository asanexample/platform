{{/* Common labels stamped on every ClusterPolicy. */}}
{{- define "kap.labels" -}}
app.kubernetes.io/managed-by: terraform
app.kubernetes.io/part-of: crossplane-agent-policies
{{- range $k, $v := .Values.commonLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/* Precondition skipping platform/system principals — for the cluster-scoped control-plane policy. */}}
{{- define "kap.skipPlatformPrincipals" -}}
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
