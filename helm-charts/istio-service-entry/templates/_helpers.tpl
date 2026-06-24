{{/*
Common labels applied to ServiceEntry resources.
*/}}
{{- define "istio-service-entry.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Render a single ServiceEntry. Expects dict with keys "root" (Helm root context)
and "entry" (ServiceEntry values map).
*/}}
{{- define "istio-service-entry.render" -}}
{{- $root := .root -}}
{{- $entry := .entry -}}
---
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: {{ required "ServiceEntry name is required" $entry.name }}
  namespace: {{ $entry.namespace | default "istio-system" }}
  labels:
    {{- include "istio-service-entry.labels" $root | nindent 4 }}
    {{- with $entry.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with $entry.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  hosts:
    {{- range $entry.hosts }}
    - {{ . | quote }}
    {{- end }}
  ports:
    {{- toYaml $entry.ports | nindent 4 }}
  location: {{ $entry.location | default "MESH_EXTERNAL" }}
  resolution: {{ $entry.resolution | default "DNS" }}
  {{- with $entry.endpoints }}
  endpoints:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $entry.addresses }}
  addresses:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $entry.exportTo }}
  exportTo:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $entry.subjectAltNames }}
  subjectAltNames:
    {{- range . }}
    - {{ . | quote }}
    {{- end }}
  {{- end }}
  {{- with $entry.workloadSelector }}
  workloadSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
