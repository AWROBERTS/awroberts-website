{{/* Chart name */}}
{{- define "awroberts.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/* Full name */}}
{{- define "awroberts.fullname" -}}
{{- printf "%s-deploy" .Release.Name -}}
{{- end -}}

{{/* Common labels */}}
{{- define "awroberts.labels" -}}
app.kubernetes.io/name: {{ include "awroberts.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | default "latest" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels */}}
{{- define "awroberts.selectorLabels" -}}
app.kubernetes.io/name: {{ include "awroberts.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
