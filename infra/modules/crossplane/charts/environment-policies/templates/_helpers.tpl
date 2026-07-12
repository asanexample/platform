{{/*
Common labels stamped on every ClusterPolicy.
Usage:  labels:
          {{- include "ktp.labels" . | nindent 4 }}
*/}}
{{- define "ktp.labels" -}}
app.kubernetes.io/managed-by: terraform
app.kubernetes.io/part-of: crossplane-environment-policies
{{- range $k, $v := .Values.commonLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/*
Precondition skipping platform/system principals — for the CLUSTER-SCOPED control-plane policy (XTenant /
ProviderConfig are cluster/control-plane resources that cannot be scoped by environment namespace). Relies on
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
    # skip a TERMINATING Environment — its finalizer-removal UPDATE must not be re-validated, or the delete wedges
    - key: "{{`{{ request.object.metadata.deletionTimestamp || '' }}`}}"
      operator: Equals
      value: ""
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
      urlPath: "/apis/platform.refplat.org/v1beta1/teams/{{`{{ request.object.spec.team }}`}}"
      default: {}
  - name: product
    apiCall:
      urlPath: "/apis/platform.refplat.org/v1beta1/products/{{`{{ request.object.spec.team }}-{{ request.object.spec.product }}`}}"
      default: {}
{{- end -}}

{{/* Precondition: only evaluate when the Product CR resolved. */}}
{{- define "ktp.productExistsPrecondition" -}}
preconditions:
  all:
    - key: "{{`{{ product.metadata.name || '' }}`}}"
      operator: Equals
      value: "{{`{{ request.object.spec.team }}-{{ request.object.spec.product }}`}}"
    - key: "{{`{{ request.object.metadata.deletionTimestamp || '' }}`}}"
      operator: Equals
      value: ""
{{- end -}}

{{/*
ADR-101: the LIST of every ServiceGrant on the cluster — used by restrict-environment-dependencies to check a
claimed XEnvironment.spec.dependencies entry against a matching, non-expired grant. Unlike ktp.envContext's
get-by-NAME lookups (default {} so a missing Team/Product just fails ITS OWN existence rule), this is a
collection call filtered downstream by JMESPath, so it needs no by-name fallback.

FAIL-CLOSED, deliberately: NO `default` is set. A `default` is Kyverno's explicit fail-OPEN knob — if the
apiCall errors (apiserver hiccup, timing during rollout) and no default exists, Kyverno fails the rule
evaluation, and with failurePolicy: Fail (below) the webhook itself denies the request. This matters here
because a plain LIST call (unlike a by-name GET) does not itself error just because zero ServiceGrants exist —
it returns `items: []` successfully — so omitting `default` only changes behavior on a REAL fetch failure, not
on the ordinary "no grant authored yet" case. Belt-and-suspenders: even independent of that engine-error path,
the rule's own logic is "deny unless a matching grant is found" — a legitimately empty (successful) list also
denies correctly through that same logic, it is not a fail-open path. Two independent reasons this fails
closed, not one relying solely on webhook plumbing.
Usage (under a rule):  {{- include "ktp.serviceGrantsContext" . | nindent 6 }}
*/}}
{{- define "ktp.serviceGrantsContext" -}}
context:
  - name: servicegrants
    apiCall:
      urlPath: "/apis/platform.refplat.org/v1beta1/servicegrants"
      jmesPath: "items"
{{- end -}}
