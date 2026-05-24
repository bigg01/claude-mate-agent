{{- define "claude-mate-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "claude-mate-agent.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "claude-mate-agent.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "claude-mate-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "claude-mate-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "claude-mate-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "claude-mate-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "claude-mate-agent.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret cert-manager writes the issued certificate into. Defaults to
"<fullname>-tls" when certManager.secretName is empty.
*/}}
{{- define "claude-mate-agent.certManagerSecretName" -}}
{{- default (printf "%s-tls" (include "claude-mate-agent.fullname" .)) .Values.certManager.secretName -}}
{{- end -}}

{{/*
Name of the K8s Secret produced by Vault Secrets Operator. Defaults to
"<fullname>-vault" when vault.secretsOperator.destinationName is empty.
*/}}
{{- define "claude-mate-agent.vaultSecretName" -}}
{{- default (printf "%s-vault" (include "claude-mate-agent.fullname" .)) .Values.vault.secretsOperator.destinationName -}}
{{- end -}}

{{/*
Render Vault Agent Injector pod annotations from values. Emits
"vault.hashicorp.com/<key>: <value>" lines; pass `.` as the context.
*/}}
{{- define "claude-mate-agent.vaultAgentAnnotations" -}}
{{- $inj := .Values.vault.agentInjector -}}
vault.hashicorp.com/agent-inject: "true"
{{- if $inj.role }}
vault.hashicorp.com/role: {{ $inj.role | quote }}
{{- end }}
{{- if $inj.initFirst }}
vault.hashicorp.com/agent-init-first: "true"
{{- end }}
{{- if $inj.preInjectOnly }}
vault.hashicorp.com/agent-pre-populate-only: "true"
{{- end }}
{{- range $name, $path := $inj.secrets }}
vault.hashicorp.com/agent-inject-secret-{{ $name }}: {{ $path | quote }}
{{- end }}
{{- range $name, $tmpl := $inj.templates }}
vault.hashicorp.com/agent-inject-template-{{ $name }}: |
  {{- $tmpl | nindent 2 }}
{{- end }}
{{- range $k, $v := $inj.extraAnnotations }}
{{- if hasPrefix "vault.hashicorp.com/" $k }}
{{ $k }}: {{ $v | quote }}
{{- else }}
vault.hashicorp.com/{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
{{- end -}}
