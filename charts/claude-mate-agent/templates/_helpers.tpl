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
Render guardrail env entries. Emits nothing when guardrails.enabled is false,
so disabled deployments have no GUARDRAILS_* env vars at all.
*/}}
{{- define "claude-mate-agent.guardrailsEnv" -}}
{{- if .Values.guardrails.enabled -}}
- name: GUARDRAILS_ENABLED
  value: "true"
{{- if .Values.guardrails.cost.enabled }}
- name: GUARDRAILS_COST_ENABLED
  value: "true"
- name: GUARDRAILS_COST_MAX_USD_PER_TASK
  value: {{ .Values.guardrails.cost.maxUsdPerTask | quote }}
- name: GUARDRAILS_COST_MAX_USD_PER_HOUR
  value: {{ .Values.guardrails.cost.maxUsdPerHour | quote }}
- name: GUARDRAILS_COST_ACTION
  value: {{ .Values.guardrails.cost.action | quote }}
{{- end }}
{{- if .Values.guardrails.input.enabled }}
- name: GUARDRAILS_INPUT_ENABLED
  value: "true"
- name: GUARDRAILS_INPUT_PATTERNS
  value: {{ join "," .Values.guardrails.input.patterns | quote }}
- name: GUARDRAILS_INPUT_EXTRA_PATTERNS
  value: {{ join "," .Values.guardrails.input.extraPatterns | quote }}
- name: GUARDRAILS_INPUT_ACTION
  value: {{ .Values.guardrails.input.action | quote }}
{{- end }}
{{- if .Values.guardrails.output.enabled }}
- name: GUARDRAILS_OUTPUT_ENABLED
  value: "true"
- name: GUARDRAILS_OUTPUT_PATTERNS
  value: {{ join "," .Values.guardrails.output.patterns | quote }}
- name: GUARDRAILS_OUTPUT_EXTRA_PATTERNS
  value: {{ join "," .Values.guardrails.output.extraPatterns | quote }}
- name: GUARDRAILS_OUTPUT_ACTION
  value: {{ .Values.guardrails.output.action | quote }}
{{- end }}
{{- if .Values.guardrails.workspace.enabled }}
- name: GUARDRAILS_WORKSPACE_ENABLED
  value: "true"
- name: GUARDRAILS_WORKSPACE_IGNORE_PATTERNS
  value: {{ join "," .Values.guardrails.workspace.ignorePatterns | quote }}
{{- end }}
{{- if .Values.guardrails.intent.enabled }}
- name: GUARDRAILS_INTENT_ENABLED
  value: "true"
- name: GUARDRAILS_INTENT_ACTION
  value: {{ .Values.guardrails.intent.action | quote }}
{{- range $role, $cfg := .Values.guardrails.intent.perPersona }}
{{- if $cfg.deny }}
- name: GUARDRAILS_INTENT_DENY_{{ $role | upper }}
  value: {{ join "," $cfg.deny | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
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
