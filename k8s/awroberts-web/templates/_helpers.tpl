{{/* Chart name */}}
{{- define "awroberts-web.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/* Full name = release name only */}}
{{- define "awroberts-web.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{/* Common labels */}}
{{- define "awroberts-web.labels" -}}
app.kubernetes.io/name: {{ include "awroberts-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | default "latest" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels */}}
{{- define "awroberts-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "awroberts-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
