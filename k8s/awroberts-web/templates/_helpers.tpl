{{/* Returns the chart name */}}
{{- define "awroberts-web.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/* Returns a full name combining release and chart name */}}
{{- define "awroberts-web.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "awroberts-web.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels for metadata */}}
{{- define "awroberts-web.labels" -}}
app.kubernetes.io/name: {{ include "awroberts-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels for matching pods */}}
{{- define "awroberts-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "awroberts-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
