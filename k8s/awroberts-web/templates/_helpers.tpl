{{/* Chart name */}}
{{- define "awroberts-web.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/* Full name = release name + suffix to avoid repetition */}}
{{- define "awroberts-web.fullname" -}}
{{- printf "%s-deploy" .Release.Name -}}
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
