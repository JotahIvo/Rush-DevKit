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
| `rush_spec_dir <id>` | Ecoa `specs/<id>/` (nível pai) resolvendo prefixo parcial (`001` → `001-autenticacao`) |
| `rush_feature_dir <id> [spec-id]` | Ecoa `specs/<spec-id>/<id>/` (nível filha, aninhado). Busca em todos os specs a menos que `[spec-id]` limite a busca; erro nomeado se `<id>` colidir entre specs |
| `rush_current_spec` | Spec ativo (`.rush/state.json` → `current_spec`) |
| `rush_current_feature` | Feature ativa dentro do spec ativo (`.rush/state.json` → `current_feature`) |
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

### `new-spec.sh <slug> [--title "..."] [--pitch] [--minimal] [--json]`

Cria `specs/NNN-<slug>/` (NNN sequencial de 3 dígitos, **nível pai**), copia `prd.md` e
`questions.md` dos templates, registra o spec em `.rush/state.json` (`current_spec`, `specs[]`).
Idempotente: slug existente retorna o diretório sem sobrescrever. Zera `current_feature` ao trocar
de spec — uma feature de outro spec não deve continuar "ativa" depois da troca.

`pitch.md` **não** é criado por padrão: o pitch é um passo opcional, e um template de pitch por
preencher em todo spec é uma violação de placeholder esperando para ser reportada. `--pitch`
(passado só pelo `/rush-pitch`) semeia. `--minimal` semeia **apenas** `questions.md`, sem
`prd.md` — é o que o `/rush-quick` usa, já que o caminho M pula a camada de produto de propósito.

```json
{ "spec_id": "001-autenticacao-google", "dir": "specs/001-autenticacao-google",
  "created": ["prd.md", "questions.md"], "already_existed": false }
```

### `new-feature.sh <spec-id> <slug> [--title "..."] [--no-prd] [--no-activate] [--json]`

Cria `specs/<spec-id>/MMM-<slug>/` (MMM sequencial de 3 dígitos, **aninhado dentro do spec**;
cada spec numera suas próprias features a partir de 001 — dois specs diferentes podem ter cada
um seu próprio `001-...`, o que é esperado, não colisão). Copia templates de feature, registra em
`.rush/state.json` (`current_spec`, `current_feature`, `features[]` — cada registro carrega
`spec_id` e é deduplicado por `dir`, não por `id`, porque `id` só é único dentro do spec).
`<spec-id>` precisa já existir (via `new-spec.sh`); idempotente: slug existente dentro daquele
spec retorna o diretório sem sobrescrever.

`--no-activate` cria/resolve a feature **sem** apontar `current_feature` para ela (`current_spec`
continua sendo atualizado). É obrigatório em criação em lote: sem isso o cursor fica em qualquer
feature que por acaso foi criada por último, que nunca é a resposta para "em qual feature estou
trabalhando". `--no-prd` pula o `prd.md` da feature — o caminho M (`/rush-quick`), que não tem PRD
de spec para rastrear de volta.

```json
{ "spec_id": "001-autenticacao-google", "feature_id": "002-entrada-com-google",
  "dir": "specs/001-autenticacao-google/002-entrada-com-google",
  "created": ["prd.md","spec.md","plan.md","tasks.md","done-contract.md"],
  "already_existed": false }
```

### `set-current.sh [--spec <id>] [--feature <id>] [--clear-feature] [--json]`

Move o cursor de `.rush/state.json` para o trabalho em andamento. Existe porque nada movia esse
cursor depois da criação, o que produzia um erro repetível: criar as features de um spec em lote
deixava `current_feature` na última criada, e implementar da 001 até a 00N mantinha o cursor na
00N o caminho inteiro — só coincidindo com a realidade na última feature.

Setar uma feature seta também o spec dela: os dois campos nunca podem discordar. Prefixo parcial é
resolvido como em `rush_feature_dir` (ambiguidade entre specs vira erro nomeado, exit 2).
`--clear-feature` deixa o spec ativo sem nenhuma feature.

```json
{ "current_spec": "001-autenticacao-google", "current_feature": "002-entrada-com-google",
  "dir": "specs/001-autenticacao-google/002-entrada-com-google" }
```

Quem chama: `/rush-features` (passo final, apontando para a primeira feature da ordem topológica),
`/rush-spec` e `/rush-implement` (ao entrar numa feature). Criação não reivindica mais o cursor de
um lote.

### Esquema de `.rush/state.json`

```json
{
  "current_spec": "001-autenticacao-google",
  "current_feature": "002-entrada-com-google",
  "specs": [
    { "id": "001-autenticacao-google", "dir": "specs/001-autenticacao-google", "title": "..." }
  ],
  "features": [
    { "id": "002-entrada-com-google", "spec_id": "001-autenticacao-google",
      "dir": "specs/001-autenticacao-google/002-entrada-com-google", "title": "..." }
  ]
}
```

Não editar à mão fora de um script — todo escritor passa por `rushlib.py json-set` /
`json-list-append`, que fazem escrita atômica.

### `validate-artifacts.sh [<feature-id>|--all] [--json]`

Valida seções obrigatórias, marcadores pendentes (`[NEEDS CLARIFICATION]`, `TODO`, placeholders
`{{...}}` e `<...>` não preenchidos) e — só onde o projeto pediu — orçamento de tamanho.

```json
{ "ok": false, "checked": ["specs/003-checkout/004-cart/spec.md"],
  "violations": [{ "file": "specs/003-checkout/004-cart/spec.md", "rule": "budget",
                   "message": "182 linhas (máx 150)", "severity": "error" }] }
```

**Nenhum artefato tem teto de linhas embutido**: todo default de `config.json → budgets` é `null`
e a checagem de tamanho só roda onde o projeto setou a chave. Ver
[`configuration.md`](../configuration.md#budgets).

Seções obrigatórias por artefato: `spec.md` (behaviour, interfaces, data, edge cases, out of
scope, assumptions) · `plan.md` (approach, files, order of work, risks, alternatives) ·
`done-contract.md` (acceptance criteria, definition of done, acceptance criteria coverage) ·
**PRD de spec** (overview, use cases, goals, out of scope, functional requirements, quality
attributes, journeys, success metrics, assumptions) · **PRD de feature** (overview, requirements,
traceability, out of scope, success criteria). Os dois PRDs compartilham o nome `prd.md` mas têm
formas diferentes de propósito, então o checador recebe o *tipo* em vez de adivinhar pelo nome do
arquivo. Exit 1 se houver `severity: error`.

### `validate-integration-map.sh [--json]`

Lê o bloco ` ```json ` de `specs/integration-map.md` e valida o grafo entre features.

Erros detectados: `consume_without_provider`, `duplicate_provider`, `dependency_cycle`,
`journey_missing_feature`, `journey_without_test`, `unknown_feature_ref`.

```json
{ "ok": false, "features": 8, "journeys": 3,
  "violations": [{ "rule": "consume_without_provider", "feature": "003-checkout/004-cart",
                   "detail": "consome endpoint 'POST /auth/login' que ninguém provê",
                   "severity": "error" }],
  "order": ["003-checkout/001-auth","003-checkout/002-catalog","003-checkout/004-cart"] }
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
    { "name": "acceptance tests", "run": "npm test -- specs/003-checkout/004-cart", "expect": "exit 0" },
    { "name": "contract honored", "run": ".rush/scripts/validate-contracts.sh 003-checkout/004-cart", "expect": "exit 0" }
  ],
  "human_gates": ["review assistida concluída (/rush-review)"]
}
```

`expect` suportado: `exit 0`, `exit N`, `contains: <texto>`, `not_contains: <texto>`.
Timeout por check: `config.json → verification.check_timeout_seconds` (default 600).

```json
{ "ok": false, "feature": "003-checkout/004-cart",
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
{ "ok": false, "feature": "003-checkout/004-cart",
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

### `memory-prune.sh [--file debt|architecture|all] [--older-than N] [--dry-run] [--restore ID] [--json]`

Arquiva, sem apagar nada, seções resolvidas/fechadas de `.rush/memory/debt.md` (status
`accepted`/`repaid`, mais antigas que `memory.archive_after_days`) e do resumo por-spec de
`.rush/memory/architecture.md` (só specs com todo `feature_close` confirmado em `.rush/state.json`),
movendo cada seção, byte a byte, para `debt.archive.md`/`architecture.archive.md` ao lado do
arquivo ativo. `--restore <id>` reverte um item. `--dry-run` reporta sem escrever. Reaproveita
`rushlib.py`'s `parse_headings`/`dump_text_file` — não reimplementa parsing de markdown.

### `session-start.sh [--json]`

Ritual de início de sessão: feature atual, contagem de tasks por status, perguntas não respondidas
no `questions.md` do spec atual, débitos abertos, working tree suja, últimos commits, última
entrada do Session Log de `tasks.md` e o comando de teste baseline sugerido.

### `session-context.sh new-path <slug> | latest | list [--json]`

Dona do **nome e da busca** dos arquivos de contexto de sessão sob `.rush/memory/sessions/` —
o conteúdo é da skill (`/rush-context-save` escreve, `/rush-context-load` lê); nenhuma das duas
inventa nome de arquivo nem decide por inspeção qual é o mais recente.

`new-path <slug>` devolve o caminho do próximo arquivo (`<YYYY-MM-DD>-<slug>.md`, com sufixo
numérico se o nome já existir), cria o diretório e **não escreve arquivo nenhum**. `dir_existed`
é `false` na primeira gravação do projeto e `gitignored` diz se o `.gitignore` já cobre o
diretório — é o que permite a skill oferecer a entrada em vez de adicioná-la por conta própria.

```json
{ "path": ".rush/memory/sessions/2026-09-01-triagem.md", "slug": "triagem",
  "date": "2026-09-01", "dir_existed": false, "gitignored": false }
```

`latest` devolve `{"found": false, "path": null, "count": 0}` e **sai 0** quando não há nada
salvo — store vazio é resposta válida, não erro. `list` devolve `{"count": N, "sessions": [...]}`,
mais recente primeiro (data do nome do arquivo, mtime desempata no mesmo dia).

### `pr-commits.sh [<spec-id>] [--no-checks] [--json]`

Base factual de `/rush-pr`: todo commit desde o que **adicionou** `specs/<spec-id>/` ao histórico
até `HEAD`, e o status de done-check de cada feature do spec. Sem `<spec-id>`, usa o
`current_spec`. A unidade de PR aqui é o spec, não a feature.

```json
{ "spec_id": "003-checkout", "spec_dir": "specs/003-checkout", "branch": "feat/003-checkout",
  "range": { "from": "<sha>", "from_short": "d01b33f", "to": "<sha>", "rev_range": "<sha>^..HEAD" },
  "commit_count": 3,
  "commits": [{ "sha": "...", "short": "cb87f57", "date": "2026-09-01T16:46:36+00:00",
                "author": "...", "subject": "feat(002): carrinho",
                "files": ["src/cart.ts"], "merge": false }],
  "features": [{ "id": "002-cart", "node_id": "003-checkout/002-cart",
                 "dir": "specs/003-checkout/002-cart", "title": "Carrinho",
                 "done_check_ok": false, "checks_passed": 0, "checks_failed": 1,
                 "gates_pending": 0, "note": null }],
  "summary": { "features": 2, "features_incomplete": 1, "commits": 3, "checks_run": true } }
```

`done_check_ok` é **tri-estado**: `true`, `false`, ou `null` quando o check não pôde rodar (sem
`done-contract.md`, ou `--no-checks`) — `/rush-pr` trata `null` igual a `false`: assunto para
levantar com o usuário, nunca para assumir. `--no-checks` pula `done-check.sh` (que roda a suíte
de testes de verdade, e pode demorar o que a suíte demorar) e reporta `features_incomplete: null`.

Exit: `0` todas as features completas (ou `--no-checks`), `1` pelo menos uma incompleta — check
falhando ou human gate pendente, resultado válido e não erro —, `2` uso inválido, spec inexistente
ou diretório fora de um repositório git. Um spec ainda não commitado devolve `range.from: null`,
`commit_count: 0` e um campo `note` dizendo isso, em vez de inventar um intervalo.

### `lib/kitfiles.py <plan|apply|snapshot|migrate|classify>`

Não é um script de projeto — é a biblioteca que `install.sh` e `update.sh` compartilham, e a
única fonte da verdade sobre **o que é do kit e o que é do projeto**. Classificação por caminho,
três classes (`kit`, `seed`, `merge`) e nada mais; o resto do projeto nunca aparece num plano.
Documentada em [`updating.md`](../updating.md).

```
plan     --kit <dir> --target <dir> [--adopt]   o que um update faria; não escreve nada
apply    --kit <dir> --target <dir> [--adopt]   aplica o inequívoco, staging do resto
snapshot --kit <dir> --target <dir> [--version] grava manifest.json + baseline.tar.gz + VERSION
migrate  --kit <dir> --target <dir> --from X --to Y [--dry-run]   migrações de config.json
classify <path...>                               a classe de um caminho
```

Saída de `plan` (exit `0` sem conflito, `1` com conflito, `2` sem manifesto e sem `--adopt`):

```json
{ "from_version": "0.6.0", "to_version": "0.7.0",
  "add": [...], "update": [...], "remove": [...],
  "conflict": [{ "path": "...", "agent_mergeable": true, "has_base": true }],
  "local_only": [...], "unchanged": [...], "seed_missing": [...],
  "settings_merge": ".claude/settings.json",
  "summary": { "add": 3, "update": 4, "remove": 1, "conflict": 2, ... } }
```

Formato de `.rush/manifest.json` — os **dois** hashes por arquivo são o que torna a comparação de
três vias possível: `sha256` é o que está no disco, `kit_sha256` é o que o kit enviou naquela
versão. `local ≠ enviado` responde "o projeto mexeu"; `enviado-antes ≠ enviado-agora` responde "o
kit mexeu". Sem o segundo, um arquivo que o `/rush-update` mergeou pareceria pristino no update
seguinte e seria sobrescrito, perdendo o merge.

```json
{ "kit_version": "0.7.0", "installed_at": "...", "updated_at": "...",
  "files": { ".rush/scripts/triage.sh": { "sha256": "...", "kit_sha256": "...", "class": "kit" } } }
```

### `update.sh <target> [--dry-run] [--adopt] [--json] [--finalize]`

Fica na raiz do **kit**, não do projeto, e roda a partir do kit novo — só a versão que introduz
uma mudança traz a migração que a explica. Exit `0` update completo, `1` conflitos pendentes
(estado válido, não erro), `2` erro de uso ou projeto sem manifesto sem `--adopt`.

Grava `.rush/.update/pending.json` enquanto há conflito, e só escreve `manifest.json`,
`baseline.tar.gz` e `.rush/VERSION` no `--finalize` — depois dos merges, para que o manifesto
registre o arquivo mergeado como divergente de propósito.

### `doctor.sh [--json] [--fix-suggestions]`

Diagnóstico: config válido contra o schema · scripts executáveis · hooks referenciados existem ·
comandos do config funcionam · specs órfãs (sem código) e código sem spec · integration map válido ·
orçamentos estourados · questions (de cada spec) e debt parados há mais de N dias · drift
acumulado · versão do kit · **estado da atualização** (`kit_update`: update pela metade, manifesto
ausente, ou `VERSION` discordando do manifesto). Exit 1 se houver item `severity: error`.

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
