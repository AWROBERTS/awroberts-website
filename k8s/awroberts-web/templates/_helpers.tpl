{{/* Returns the chart name */}}
{{- define "awroberts-web.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/* Returns a full name using just the release name to avoid duplication */}}
{{- define "awroberts-web.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{/* Common labels for metadata */}}
{{- define "awroberts-web.labels" -}}
app.kubernetes.io/name: {{ include "awroberts-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | default "latest" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels for matching pods */}}
{{- define "awroberts-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "awroberts-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Returns the service account name, defaulting to 'default' */}}
{{- define "awroberts-web.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{ .Values.serviceAccount.name }}
{{- else }}
default
{{- end -}}
{{- end -}}
