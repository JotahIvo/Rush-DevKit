# Contrato de interfaces dos scripts

Este documento é a **fonte da verdade** da fronteira entre os agentes (prompts) e o harness
determinístico (scripts). Skills chamam scripts por estes contratos; scripts nunca dependem de
um LLM. Se um comportamento precisa ser idêntico toda vez, ele vive aqui — não num prompt.

## Regras gerais

- Todos os scripts ficam em `.rush/scripts/`, com `#!/usr/bin/env bash` e `set -euo pipefail`.
- Trabalho de parsing (JSON, grafos, seções, orçamentos) é feito em Python 3 (**apenas stdlib**),
  em `.rush/scripts/lib/rushlib.py`. Bash cuida de processo, git e execução de comandos.
- **Blocos machine-readable em artefatos são JSON em cerca ` ```json `**, nunca YAML — a stdlib do
  Python não lê YAML e o kit não pode exigir dependências. Trade-off aceito conscientemente.
- Convenção de saída: `--json` imprime **um único objeto JSON** em stdout e nada mais.
  Sem `--json`, saída legível por humano.
- **Códigos de saída**: `0` sucesso / sem violações · `1` violações encontradas (resultado válido,
  não é erro do script) · `2` erro de uso ou falha interna.
- Nenhum script escreve fora da raiz do projeto. Nenhum script faz rede.
- Todo script aceita `-h|--help`.
- Portabilidade: macOS (bash 3.2) e Linux. Sem flags GNU-only (`grep -P`, `sed -i` sem sufixo,
  `date -d`). Sem dependência de `jq`.

## Descoberta de projeto

`RUSH_ROOT` é o diretório que contém `.rush/`. `lib/common.sh` exporta:

| Função | Comportamento |
|---|---|
| `rush_root` | Ecoa a raiz do projeto; erro se não encontrar |
| `rush_config <caminho.pontilhado> [default]` | Lê valor de `.rush/config.json` |
| `rush_config_bool <caminho> [default]` | Ecoa `true`/`false` |
| `rush_feature_dir <id>` | Ecoa `specs/<id>/` resolvendo prefixo parcial (`007` → `007-checkout`) |
| `rush_current_feature` | Feature ativa (`.rush/state.json` → `current_feature`) |
| `rush_die <msg>` / `rush_warn` / `rush_ok` / `rush_info` | Mensagens padronizadas (stderr) |
| `rush_json_out <json>` | Imprime JSON em stdout e sai 0 |

## Scripts

### `detect-stack.sh [--json]`

Detecção determinística da stack. **Nunca** adivinha via LLM.

Saída JSON:

```json
{
  "language": "typescript", "runtime": "node", "package_manager": "npm",
  "framework": "nestjs", "monorepo": false,
  "commands": { "test": "npm test", "lint": "npm run lint", "build": "npm run build",
                "format": "npm run format", "typecheck": "npx tsc --noEmit" },
  "database": "postgresql", "orm": "prisma", "migrations": "prisma/migrations",
  "ci": [".github/workflows/ci.yml"],
  "ai_sdks": ["@anthropic-ai/sdk"],
  "commit_convention": { "detected": "conventional", "confidence": 0.82, "sample": 100 },
  "preset_suggestion": "nestjs-prisma",
  "test_files": 42, "source_files": 310
}
```

`commit_convention` vem da análise dos últimos 100 commits (o padrão **real**, não o declarado).
Campos não detectados são `null` — nunca inventados.

### `triage.sh [--paths "a b c"] [--files N] [--json]`

Parte determinística da triagem S/M/L. Não decide sozinho quando há incerteza — sinaliza.

```json
{ "level": "L", "forced": true,
  "signals": { "file_count": 2, "sensitive_paths_touched": ["src/auth/login.ts"],
               "contract_changed": false, "migration_detected": false,
               "new_dependency": false },
  "reasons": ["toca path sensível: src/auth/"],
  "needs_human_confirmation": false }
```

Regras: path sensível, migration, dependência nova ou mudança de contrato ⇒ `L` (`forced: true`).
Sem sinais e `file_count <= triage.max_files_for_S` ⇒ `S`. Caso contrário `M` com
`needs_human_confirmation: true`.

### `new-feature.sh <slug> [--title "..."] [--json]`

Cria `specs/NNN-<slug>/` (NNN sequencial de 3 dígitos), copia templates, registra a feature em
`.rush/state.json`. Idempotente: slug existente retorna o diretório sem sobrescrever.

```json
{ "feature_id": "007-checkout", "dir": "specs/007-checkout",
  "created": ["spec.md","plan.md","tasks.md","done-contract.md","progress.md"],
  "already_existed": false }
```

### `validate-artifacts.sh [<feature-id>|--all] [--json]`

Valida seções obrigatórias, **orçamentos de tamanho** e marcadores pendentes
(`[NEEDS CLARIFICATION]`, `TODO`, placeholders `<...>` não preenchidos).

```json
{ "ok": false, "checked": ["specs/007-checkout/spec.md"],
  "violations": [{ "file": "specs/007-checkout/spec.md", "rule": "budget",
                   "message": "182 linhas (máx 150)", "severity": "error" }] }
```

Orçamentos (linhas): `pitch.md` 60 · `prd.md` 200 · `spec.md` 150 · `plan.md` 100 ·
`architecture` (seção da feature) 100 · `CLAUDE.md` 60 · `constitution.md` 200.
Sobrescrevíveis em `config.json → budgets`. Exit 1 se houver `severity: error`.

### `validate-integration-map.sh [--json]`

Lê o bloco ` ```json ` de `specs/integration-map.md` e valida o grafo entre features.

Erros detectados: `consume_without_provider`, `duplicate_provider`, `dependency_cycle`,
`journey_missing_feature`, `journey_without_test`, `unknown_feature_ref`.

```json
{ "ok": false, "features": 8, "journeys": 3,
  "violations": [{ "rule": "consume_without_provider", "feature": "004-cart",
                   "detail": "consome endpoint 'POST /auth/login' que ninguém provê",
                   "severity": "error" }],
  "order": ["001-auth","002-catalog","004-cart"] }
```

`order` é a ordenação topológica (ordem segura de implementação). Exit 1 em erro.

### `validate-contracts.sh [<feature-id>|--all] [--json]`

Parseia contratos em `specs/*/contracts/` e `specs/shared-contracts/`: OpenAPI (`openapi:`),
JSON Schema, AsyncAPI. Valida sintaxe, `$ref` resolvível e — em shared-contracts — que a feature
dona declarada no integration map existe. Exit 1 em contrato inválido.

### `done-check.sh <feature-id> [--json] [--only <check-name>]`

**Executor da Definition of Done.** Lê o bloco ` ```json ` de `done-contract.md`, executa cada
`run` e compara com `expect`. É o critério de parada do loop do implementer e o grader dos evals.

Formato do bloco no `done-contract.md`:

```json
{
  "checks": [
    { "name": "acceptance tests", "run": "npm test -- specs/007", "expect": "exit 0" },
    { "name": "contract honored", "run": ".rush/scripts/validate-contracts.sh 007", "expect": "exit 0" }
  ],
  "human_gates": ["review assistida concluída (/rush-review)"]
}
```

`expect` suportado: `exit 0`, `exit N`, `contains: <texto>`, `not_contains: <texto>`.
Timeout por check: `config.json → verification.check_timeout_seconds` (default 600).

```json
{ "ok": false, "feature": "007-checkout",
  "checks": [{ "name": "acceptance tests", "status": "fail", "exit_code": 1,
               "duration_ms": 8421, "output_tail": "...últimas 40 linhas..." }],
  "human_gates": [{ "text": "review assistida concluída", "confirmed": false }],
  "summary": { "passed": 2, "failed": 1, "gates_pending": 1 } }
```

**Sucesso é silencioso, falha é verbosa**: checks que passam trazem `output_tail` vazio.

### `task-status.sh <feature-id> [--list] [--set <task-id> <status>] [--by <ator>] [--json]`

Lê e altera status em `tasks.md`. **Regra dura**: promover para `done` exige
`--by rush-verifier`; qualquer outro ator recebe exit 1 e mensagem explicando que apenas o
verifier promove. Status: `pending`, `in_progress`, `blocked`, `done`.

### `check-as-built.sh <feature-id> [--json]`

Detecta spec drift comparando o que a spec/plan declara com o que o git mostra: arquivos tocados
pelos commits da feature vs arquivos previstos no plan; endpoints nos contratos vs referências no
código; data do último commit de código vs último commit da spec.

```json
{ "ok": false, "feature": "007-checkout",
  "drift": [{ "kind": "unplanned_file", "detail": "src/payments/webhook.ts não consta no plan.md" },
            { "kind": "stale_spec", "detail": "spec.md não é atualizada há 14 commits de código" }] }
```

Exit 1 quando há drift não reconciliado.

### `fitness.sh [<feature-id>|--all] [--json]`

Executa as fitness functions de `.rush/memory/fitness/*.sh`. Cada arquivo declara
`# description:` e `# scope:` (`all` ou id de feature) no cabeçalho, e sai 0/1.

### `secret-scan.sh [--staged|--paths "..."] [--json]`

Varredura por padrões de segredo (chaves de provedores conhecidos, blocos PEM, entropia alta em
atribuições suspeitas). Respeita `.rush/secret-scan-allow` (uma regex por linha). Exit 1 em hit.

### `session-start.sh [--json]`

Ritual de início de sessão: feature atual, contagem de tasks por status, perguntas não respondidas
em `questions.md`, débitos abertos, working tree suja, últimos commits, última entrada de progresso
e o comando de teste baseline sugerido.

### `doctor.sh [--json] [--fix-suggestions]`

Diagnóstico: config válido contra o schema · scripts executáveis · hooks referenciados existem ·
comandos do config funcionam · specs órfãs (sem código) e código sem spec · integration map válido ·
orçamentos estourados · questions/debt parados há mais de N dias · drift acumulado · versão do kit.
Exit 1 se houver item `severity: error`.

### `eval.sh [<agente>|--all] [--json] [--case <id>]`

Runner de evals. Para cada caso em `.rush/evals/<agente>/cases/*.json`, aplica os graders
determinísticos e reporta. Graders que exigem julgamento são marcados `manual` e listados para
revisão humana — o runner nunca finge avaliar o que não consegue medir.

```json
{ "agent": "rush-spec", "total": 12, "passed": 10, "failed": 1, "manual": 1,
  "cases": [{ "id": "spec-budget-respected", "status": "pass" }] }
```

## Como as skills devem chamar scripts

- Sempre pelo caminho relativo à raiz: `.rush/scripts/<nome>.sh`.
- Sempre com `--json` quando o agente for **interpretar** o resultado.
- **Nunca** reimplementar em prosa o que o script faz. Se o script não cobre o caso, o caminho é
  melhorar o script — não improvisar no prompt.
- Se um script sair com `2` (erro interno), o agente **para e reporta**; não tenta contornar.
