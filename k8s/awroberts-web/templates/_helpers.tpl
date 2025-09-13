{{- define "awroberts-web.labels" -}}
app.kubernetes.io/name: {{ include "awroberts-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "awroberts-web.name" -}}
{{- .Chart.Name -}}
{{- end -}}
