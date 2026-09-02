# Changelog

## 0.6.0

Quatro mudanças de fluxo, todas vindas de usar o kit num projeto de verdade: teto de linhas
estrangulando documento que precisava ser completo, pitch tratado como obrigatório quando quase
nunca é, PRD chegando depois da arquitetura que deveria orientar, e um cursor de feature que
apontava para a feature errada o caminho inteiro.

### Changed

- **Nenhum documento gerado tem mais teto de linhas.** Todo default de `config.json → budgets`
  passou a ser `null`, e `validate-artifacts.sh` não carrega mais limite embutido nenhum: um
  documento tem o tamanho que o conteúdo dele honestamente exige. O mecanismo continua existindo
  para o projeto que quiser um teto num arquivo específico (o caso típico é o `CLAUDE.md`, lido
  inteiro por todo agente em toda sessão) — basta setar a chave. O guardrail universal 4 de toda
  skill foi reescrito no mesmo espírito: densidade sobre completude, sem enchimento e sem corte
  para caber num número.
- **O PRD passou a ser a porta de entrada do fluxo L, e vem antes da arquitetura.** A ordem era
  pitch → arquitetura → PRD; agora é (pitch opcional) → **PRD → arquitetura** → features → spec.
  Arquitetar antes de enunciar requisito produz um PRD que já nasce justificando decisão
  estrutural tomada antes de alguém dizer o que o sistema precisa fazer. Com o PRD primeiro, a
  arquitetura recebe alvo: cada linha da tabela de atributos de qualidade é um compromisso com
  número, e uma linha que a arquitetura não atende dentro do apetite vira achado para levantar,
  não número que se afrouxa em silêncio. `/rush` roteia L para `/rush-prd`; `/rush-architect`
  agora lê o PRD como sua entrada principal; `/rush-new` reordenou seus passos.
- **`/rush-pitch` é oficialmente opcional.** Ele existe para o caso em que a ideia ainda é uma
  frase e o problema por trás dela não foi nomeado — moldar isso numa página barata antes de
  alguém escrever requisito. Quando o problema já está claro, `/rush-prd` faz a própria conversa
  de enquadramento e o pitch só adicionaria documento. Consequência mecânica: `new-spec.sh` não
  semeia mais `pitch.md` por padrão (só com `--pitch`, que apenas `/rush-pitch` passa), o que
  também elimina um template por preencher em todo spec que `validate-artifacts.sh` reportaria
  para sempre.
- **O PRD do spec foi reescrito para ser completo.** Novo `prd-template.md`, destilado das
  práticas de PRD para agentes de código: problema e visão, usuários e casos de uso, metas, fora
  de escopo com motivo, **requisitos funcionais numerados `FR-NNN` e testáveis** (nas formas EARS
  — `WHEN … THE SYSTEM SHALL …`), atributos de qualidade com alvo mensurável e condição, domínio
  e dados no nível conceitual, journeys com caminho de falha e os `FR-NNN` que cobrem, restrições
  com fonte, métricas de sucesso medidas no usuário (não no sistema), riscos com sinal precoce, e
  suposições. Ids de requisito são estáveis para a vida do spec — nunca renumerados, porque o PRD
  de cada feature os cita.

### Added

- **PRD por feature**, escrito por `/rush-spec` na mesma passada que `spec.md`, `plan.md`,
  `tasks.md` e `done-contract.md`. Deliberadamente contido — o PRD do spec já tem a definição
  completa, e repetir aqui é como dois documentos começam a discordar. Ele carrega o que é
  verdade só daquela fatia (quem serve, o que precisa permitir, o que deixa para uma irmã, como
  se julga que chegou) e, principalmente, uma tabela de **rastreabilidade**: todo requisito da
  feature cita ao menos um `FR-NNN` do PRD do spec, e a linha que nomeia os requisitos do pai
  *não* cobertos ali é o que impede duas features de cada uma assumir que a outra cuidou. Um
  requisito sem nada a citar é scope creep ou lacuna no PRD do spec — achado a reportar, nunca a
  preencher em silêncio. `/rush-analyze` passou a checar essa rastreabilidade e a tratar citação
  que não resolve como blocker.
- **`.rush/scripts/set-current.sh`** (`--spec` · `--feature` · `--clear-feature`) — move o cursor
  de `.rush/state.json` para o trabalho em andamento. Setar a feature seta o spec dela junto; os
  dois campos nunca podem discordar.
- **`new-feature.sh --no-activate`** e **`--no-prd`**; **`new-spec.sh --pitch`** e **`--minimal`**.

### Fixed

- **`current_feature` apontava para a feature errada durante a implementação inteira.** Criar as
  features de um spec em lote deixava o cursor na última criada; implementando da 001 até a 00N
  ele ficava na 00N o caminho todo, coincidindo com a realidade só na última — o que produzia
  aquele "agora sim bateu" na feature final. A causa era o cursor ser reivindicado por *criação*
  em vez de por *atenção*. Agora `/rush-features` cria tudo com `--no-activate` e, no fim, aponta
  `set-current.sh` para a primeira feature da ordem topológica; `/rush-spec` e `/rush-implement`
  reivindicam a feature ao entrar nela. `session-start.sh` e `/rush-brief` passam a reportar a
  feature em que se está de fato trabalhando.
- **O caminho M deixava dois templates de PRD por preencher.** `/rush-quick` chamava `new-spec.sh`
  e `new-feature.sh` sem forma de pular a camada de produto, então todo spec M ficava com um
  `prd.md` de placeholders que ninguém naquele caminho voltaria para preencher e que
  `validate-artifacts.sh` reportaria indefinidamente. Agora usa `--minimal` e `--no-prd`.

## 0.5.0

Três skills que existiam sem poder rodar, um controle que o schema anunciava sem aplicar, e as
duas skills que ficaram apontando para o arquivo errado depois que a arquitetura virou por-spec
na 0.3.0. Nada aqui é funcionalidade nova pedida — é o kit fechando o que já tinha prometido.

### Added

- **`.rush/scripts/pr-commits.sh`** — a base factual de `/rush-pr`: todo commit desde o que
  adicionou `specs/<spec-id>/` ao histórico até `HEAD` (sha, data, autor, assunto, arquivos
  tocados, flag de merge) e o status de `done-check.sh` de cada feature sob o spec.
  `done_check_ok` é tri-estado — `true`, `false` ou `null` quando o check não pôde rodar —, e
  `--no-checks` pula a execução dos done-contracts (que roda a suíte de testes de verdade) e
  reporta `features_incomplete: null` em vez de fingir que mediu. Exit `1` quando alguma feature
  está incompleta: resultado válido, não erro.
- **`.rush/scripts/session-context.sh`** (`new-path <slug>` · `latest` · `list`) — dona do nome e
  da busca dos arquivos de `/rush-context-save`/`/rush-context-load` sob `.rush/memory/sessions/`.
  `new-path` cria só o diretório, nunca o arquivo, e reporta `dir_existed` e `gitignored` para a
  skill poder oferecer a entrada no `.gitignore` em vez de adicioná-la sozinha. Store vazio é
  `found: false` com exit `0` — resposta válida, não erro.
- **`.rush/templates/pr-template.md`**, **`pr-preferences-template.md`** e
  **`session-context-template.md`** — os três templates que `/rush-pr`, `/rush-context-save` e
  `/rush-context-load` preenchem.
- **Aplicação de `git.branch_pattern` em `guard-bash.sh`** — nega criar uma branch cujo nome não
  casa com nenhum padrão declarado (`git checkout -b`, `git switch -c`, `git branch <nome>`,
  incluindo rename/copy) e nega um `git commit` feito numa branch que não casa com nenhum. O padrão
  é uma forma, não uma regex: tudo literal exceto `NNN` (três dígitos), `slug` (kebab-case), `*`
  (um segmento) e `**` (qualquer coisa).
- **Check `skill_dependencies` no `doctor.sh`** — resolve todo caminho `.rush/scripts/*.sh` e
  `.rush/templates/*.md` citado por um `SKILL.md` ou por um subagent, e reporta como **erro** o que
  não existe. É o mecanismo que impede a recorrência da falha que originou esta versão: uma skill
  cujo script não existe é um comando que não pode funcionar, e hoje nada percebia isso até um
  usuário invocá-lo.
- **Cinco casos de eval novos** — `kit-skill-harness-references-exist` e
  `kit-branch-pattern-enforced` (determinísticos, com fixtures próprias),
  `quick-escalates-on-migration`, `pr-incomplete-feature-never-reported-done` e
  `context-save-resolves-path-via-script`. `/rush-quick`, `/rush-pr` e `/rush-context-save`
  passam a ter cobertura; a do `/rush-quick` cobre justamente a escalação que a própria skill
  chama de seu guardrail mais importante.

### Changed

- **`git.branch_pattern` aceita uma lista, e o default passou a ser uma.** O default agora é
  `["feat/NNN-slug", "main", "master"]` — como string única, a checagem recém-criada transformaria
  todo commit na branch default em erro no instante em que passou a existir. `null` (ou lista
  vazia) desliga a checagem inteira. **Se o `.rush/config.json` do seu projeto tem
  `"branch_pattern": "feat/NNN-slug"` como string**, a partir desta versão commits em `main` são
  negados: troque pela lista, ou ponha `null`, ou mantenha assim se é exatamente isso que você
  quer.

### Fixed

- **`/rush-pr`, `/rush-context-save` e `/rush-context-load` não funcionavam.** As três shipparam
  referenciando dois scripts e três templates que nunca foram escritos; na primeira invocação elas
  paravam no próprio guardrail 2 ("se um script sai 2, pare e reporte"). As três também estavam
  fora de `docs/agents.md`, `docs/flow.md`, da tabela de modelos de `kit-conventions.md`, do README
  e do CHANGELOG. Agora existem de fato, e o novo check do `doctor.sh` guarda a classe do erro.
- **`/rush-features` e `/rush-analyze` liam a arquitetura errada.** Desde a 0.3.0 a arquitetura
  completa vive em `specs/<spec-id>/architecture.md` e `.rush/memory/architecture.md` guarda só o
  digest de 25 linhas por spec; `/rush-architect`, `/rush-brief` e `/rush-spec` foram atualizados
  na 0.4.0, essas duas não. O caso do `/rush-analyze` era o mais sério: um dos seus checks é
  "architecture not reflected in plan", rodando contra o resumo condensado.
- **Exemplos de documentação com id de feature no formato pré-0.3.0.** `docs/integration.md`,
  `docs/definition-of-done.md` e `docs/internals/script-interfaces.md` mostravam `001-auth`,
  `004-cart` e `specs/007-checkout/spec.md` — bare ids e o nível de aninhamento errado — enquanto
  `/rush-features` manda explicitamente usar `<spec-id>/<feature-id>`. Exemplo é o que o modelo
  copia. `docs/integration.md` agora diz a regra em uma frase, além de mostrá-la.
- **`docs/harness.md` descrevia `branch_pattern` como não implementado citando um texto de schema
  que não existe mais** — o `config.schema.json` já tinha sido corrigido para "advisory", o doc
  não. Agora os dois descrevem o comportamento real, incluindo o que ele não cobre: uma branch que
  o humano cria no próprio terminal não passa por hook nenhum.
- **`.gitignore` do kit passou a cobrir `.rush/memory/sessions/`** — o diretório que
  `/rush-context-save` cria é scratch de uma sessão, não artefato de projeto.
- **Restaurado o bit de execução de cinco scripts** (`memory-prune.sh`, `new-feature.sh`,
  `new-spec.sh`, `session-start.sh`, `validate-artifacts.sh`), que tinham perdido o `+x` na cópia
  de trabalho — `spec-budget-violation-caught` falhava com exit 126 por causa disso.
- **Removido `.rush/templates/_to_delete/progress-template.md`**, sobra da aposentadoria do
  `progress.md` na 0.3.0.

## 0.4.0

Token-cost changes, driven by real usage: a Pro-plan session burning its whole budget just
planning one spec's features, before `/rush-spec-all` could get through all of them for a
multi-feature spec, and shared memory files (`.rush/memory/debt.md`, `.rush/memory/architecture.md`)
that only ever grow as a project accumulates specs, read in full by every skill that touches them.

### Added

- **`rush-spec-runner` subagent** (`.claude/agents/rush-spec-runner.md`) — runs `/rush-spec`'s
  complete process for exactly one feature, in its own isolated context, and returns a compact
  structured result. It is not a different process from `/rush-spec`: it reads and follows
  `.claude/skills/rush-spec/SKILL.md` itself, with one behavioural difference documented in its own
  file — a question that would normally block on the user instead becomes a recorded default plus a
  `NEEDS_HUMAN_DECISION` flag in its report, since a batch dispatch has no one watching in real time
  to answer it.
- **`.rush/scripts/memory-prune.sh`** — archives resolved/closed sections out of `.rush/memory/debt.md`
  (status `accepted`/`repaid`, past `memory.archive_after_days`) and `.rush/memory/architecture.md`'s
  per-spec digest (only once every feature under that spec has its `feature_close` gate confirmed in
  `.rush/state.json`, and past the same threshold), into sibling `debt.archive.md` /
  `architecture.archive.md` files next to them. Nothing is deleted — `--restore <id>` moves one
  section back. `--dry-run --json` reports what would move without writing.
- **`memory` config block** (`.rush/config.json` → `memory.archive_after_days`, default `90`) —
  optional; a `config.json` from before this version behaves exactly as if it were present with the
  default, nothing breaks by its absence.
- **`doctor.sh`'s `memory_growth` check** — runs `memory-prune.sh --dry-run` and flags when
  `.rush/memory/debt.md` or `architecture.md` have sections eligible to archive, or have grown past
  a size heuristic even with nothing yet eligible.

### Changed

- **`/rush-spec-all` dispatches one `rush-spec-runner` subagent per feature instead of running
  `/rush-spec`'s process inline for each one.** Previously, specifying N features under one spec
  meant N full passes of exploration, contract generation and validation retries all accumulating in
  the same conversation — feature 10 carried the weight of everything read and written for the 9
  before it. Now only each feature's final structured result (roughly a dozen lines) returns to the
  conversation; the exploration, drafts and validation loop that produced it stay inside that
  feature's own subagent context and are discarded once it reports back. Sequencing, dependency
  ordering (provider before consumer) and "one feature failing doesn't stop the rest" are unchanged
  — only the isolation mechanism is new. Features are still dispatched one at a time, never
  concurrently, even when they don't depend on each other; parallelising independent features would
  save wall-clock time, not token cost, and is not what this version does.
- **`rush-architect`'s Inputs** now say explicitly to read `.rush/memory/architecture.md` in full
  only when the whole cross-spec picture is genuinely needed, and to prefer
  `rushlib.py parse-headings` plus reading only the relevant spec(s)' digest sections otherwise —
  the file accumulates one section per spec for the life of the project, and most decisions only
  need the sections actually relevant to them.
- **`rush-brief`'s Input 7** now scopes its `debt.md` read to entries whose "Originating
  feature/task" names the feature being briefed, instead of implying a read of the whole file for
  every brief.
- **`rush-retro`** gained step 8b: after accepting/repaying debt or confirming a spec's last
  `feature_close` gate, run `memory-prune.sh --dry-run --json` and report what it would archive,
  rather than leaving archiving to be discovered separately via `doctor.sh`.

None of this changes what any artifact says or what any check enforces — it changes where the
process that produces them runs, and how much of it stays in view afterward.

## 0.3.0

Six workflow changes, all driven by real friction running the kit on a live project: too many
manual `/rush-spec` invocations per spec, architecture scoped to a feature when it's really a
whole-system decision, a contracts step that was never skipped so it stopped earning its own
command, a progress.md nobody kept reading separately from tasks.md, acceptance criteria that could
drift out of sync with the checks meant to enforce them, and one global `questions.md` that became
unreadable once more than one spec was in flight.

### Added

- **`/rush-spec-all <spec-id>`** — runs `/rush-spec`'s full process for every feature nested under
  one spec, in dependency order (provider before consumer, from the integration map's topological
  order where available, otherwise numeric order). One feature failing or ending in unresolved
  questions never stops the rest from being attempted. Orchestration only: it carries none of its
  own content guardrails and waives none of `/rush-spec`'s.
- **`specs/<spec-id>/architecture.md`** — the complete, authoritative architecture for the whole
  system a spec builds, written once per spec by `/rush-architect` (budget 200 lines) instead of
  one section per feature in the shared memory file.
- **`.rush/templates/architecture-summary-template.md`** — the condensed per-spec digest
  `/rush-architect` appends to `.rush/memory/architecture.md` (budget 25 lines) after writing the
  full version. A pointer plus a handful of facts, never a copy of the full document's text.
- **`specs/<spec-id>/questions.md`**, seeded empty by `new-spec.sh` for every new spec.

### Changed

- **Architecture moved from per-feature to per-spec, and split into a full version plus a
  summary.** `/rush-architect` now runs once per spec (it always ran at the spec level in its
  Inputs, but wrote a per-feature section before) and produces the complete system architecture at
  `specs/<spec-id>/architecture.md`. `.rush/memory/architecture.md` now accumulates one condensed
  digest per spec instead of one full section per feature — reading every spec's architecture in
  full no longer means reading an ever-growing single file. `validate-artifacts.sh` budgets the two
  separately (`architecture`: 200 lines for the full file, new `architecture_summary`: 25 lines for
  the digest section).
- **Contract generation folded into `/rush-spec`.** When a feature's `spec.md` declares an
  interface it provides, `/rush-spec` now generates that interface's contract file(s) (OpenAPI,
  JSON Schema, AsyncAPI) itself, as part of its own process — no separate command is needed for the
  normal flow. `/rush-contracts` still exists, repurposed as the tool for re-syncing a contract
  after it changes post-freeze (or generating one `/rush-spec` skipped for some reason); its
  mechanics are unchanged, only its role in the flow is narrower now.
- **`progress.md` retired; `tasks.md` absorbed it.** Every feature's session diary now lives in a
  `## Session Log` section at the bottom of `tasks.md` (level-4 `####` entries on purpose — task
  headings are level-3 and every script that parses tasks treats "###" as a potential task, so the
  log had to be a level nothing else uses). `new-feature.sh` no longer copies
  `progress-template.md`; `session-start.sh` reads the newest Session Log entry instead of a
  separate file's newest heading.
- **Each task's status line now carries a `[ ]`/`[x]` checkbox**, e.g. `` - [x] status: `done` ``,
  toggled automatically by `task-status.sh`/`rushlib.py`'s `set_task_status` (checked only when
  status is `done`) — a glance at `tasks.md` now shows completion without reading every status
  word. Reading stays backward compatible with files that have no checkbox yet; the first status
  change on such a file adds one.
- **Acceptance criteria moved from `spec.md` into `done-contract.md`.** A criterion and the check
  (or human gate) that enforces it are now written and read together, in one document, instead of
  living in two files that could silently drift apart. `spec.md` no longer has an "Acceptance
  Criteria" section (dropped from `validate-artifacts.sh`'s required sections for it);
  `done-contract.md` gained one, immediately before the Definition of Done JSON block, and
  `validate-artifacts.sh` now requires "Acceptance Criteria", "Definition of Done" and "Acceptance
  Criteria Coverage" sections in it.
- **`questions.md` moved from one shared `.rush/memory/questions.md` to one per spec**,
  `specs/<spec-id>/questions.md`, seeded by `new-spec.sh`. A big multi-spec project no longer has
  every spec's non-blocking questions interleaved in one file — each spec's questions sit with its
  own artifacts. `session-start.sh` reads the current spec's file; `doctor.sh`'s staleness check
  scans every spec's file and reports across all of them. The canonical Guardrail 7 text ("Blocking
  question: ask the user. Non-blocking question: append to...") changed to match in all 18 skills
  and in `docs/internals/kit-conventions.md`.

### Migration

Projects on `0.2.x` upgrading in place: for each existing feature, move its `progress.md` content
into a new `## Session Log` section at the bottom of `tasks.md` (by hand, or leave the old file —
nothing deletes it automatically) and delete `progress.md` once migrated. For each spec, create
`specs/<spec-id>/questions.md` (copy over any entries from the old shared
`.rush/memory/questions.md` that concern that spec) — the old shared file is not deleted
automatically either. For each feature's `spec.md`, move its "Acceptance Criteria" section into
`done-contract.md` (immediately before the Definition of Done block) and add or update the
Coverage table there. For each spec that already ran `/rush-architect`, its old per-feature section
in `.rush/memory/architecture.md` can be split into a full `specs/<spec-id>/architecture.md` plus a
condensed digest the next time `/rush-architect` runs for it — nothing requires doing this
retroactively for closed specs.

## 0.2.0

Structural change: features now nest under their spec, both levels carry their
own numeric id, and `.rush/state.json` tracks the active spec and the active
feature inside it separately. Driven directly by real usage: a pitch run
without a PRD left an unnumbered `specs/<slug>/` directory with only
`pitch.md` and no `state.json`, and `/rush-features` created several
`specs/NNN-slug/` as siblings when the user's mental model was one numbered
parent containing them.

### Changed

- **specs/ is now two levels: `specs/<spec-id>/<feature-id>/`.** A spec
  (`specs/NNN-slug/`) is the parent unit — `pitch.md` and `prd.md` live
  directly in it. A feature (`specs/<spec-id>/MMM-slug/`) is a deliverable
  unit split out of it by `/rush-features` (or the single implicit feature
  `/rush-quick` creates) — `spec.md`, `plan.md`, `tasks.md`,
  `done-contract.md`, `progress.md` live there. Feature ids restart at `001`
  inside every spec, the same way task ids restart inside every feature's
  `tasks.md` — a bare feature id can therefore collide across specs, which is
  expected, not an error; pass the spec id to disambiguate.
- **`new-feature.sh` now requires `<spec-id> <slug>`** (previously just
  `<slug>`) and creates the feature nested under that spec. A new
  **`new-spec.sh <slug>`** creates the parent, scaffolding `pitch.md`/`prd.md`
  from templates.
- **`.rush/state.json` gained `current_spec`** alongside `current_feature`
  (now scoped to the active spec) and a top-level `specs[]` registry, next to
  the existing `features[]` (each record now carries `spec_id`, and is
  deduplicated by `dir` rather than `id`, since ids are only unique within
  their spec).
- **`rush_feature_dir` in `common.sh` resolves the nested path** and takes an
  optional `[spec-id]` to scope/disambiguate; a new **`rush_spec_dir`**
  resolves the parent level. Every script that already called
  `rush_feature_dir` and just joined paths onto its result (`task-status.sh`,
  `done-check.sh`, `fitness.sh`, …) needed no further change. Scripts with
  their own duplicated resolution logic (`check-as-built.sh`,
  `validate-artifacts.sh`, `validate-contracts.sh`,
  `validate-integration-map.sh`) were updated to search both levels.
- **`guard-edit.sh`'s tasks.md protection** now matches
  `specs/<spec-id>/<feature-id>/tasks.md`.
- **`/rush-pitch` numbers a spec immediately** via `new-spec.sh`, instead of
  staging an unnumbered `specs/<slug>/pitch.md` and deferring numbering to a
  later `/rush-features` run that might not happen (the exact gap that
  produced the bug this release fixes). `/rush-architect` and `/rush-prd` now
  explicitly operate at the spec level (`<spec-id>`, pre-`/rush-features`);
  `/rush-features` creates each split feature nested under the spec it split
  and uses `<spec-id>/<feature-id>` as the node id in `integration-map.md`;
  `/rush-quick` and `/rush-spec` create a spec (if needed) before the feature
  nested inside it.
- Decided against a per-spec architecture summary file: `/rush-architect`'s
  output keeps accumulating as one section per feature in the shared
  `.rush/memory/architecture.md` — unchanged from 0.1.x.

### Migration

There is no automatic migrator in this release (see the open item on an
update path that doesn't require re-running `/rush-init`). An existing flat
`specs/NNN-slug/` project needs its feature directories moved under the spec
they belong to and `.rush/state.json` rebuilt by hand — see
`docs/internals/script-interfaces.md` for the exact shape.

## 0.1.1

Fixes a shipping bug that made the kit unusable on macOS.

### Fixed

- **`guard-edit.sh` could not be parsed by macOS bash 3.2** (`unexpected EOF while
  looking for matching backtick`). A literal backtick inside a heredoc inside
  `$( )` is a whole-file syntax error on bash 3.2 — and since this is a
  `PreToolUse` hook, the failure blocked *every* `Write` and `Edit` in the
  project, including the edit that would have fixed it. `bash -n` under bash 5
  passed throughout, which is why it shipped.
  All four hooks now write their Python to a temp file instead of using
  `PYCODE=$(cat <<'PYEOF' … )`, which also keeps stdin free for the hook payload
  and removes the argv size limit. `new-feature.sh` had the same latent
  construct and was converted too.
- **`.rush/config.json` and `constitution.md` were denied unconditionally**, so
  `/rush-init` could not create them — the harness was unable to install itself.
  Creating them is now allowed (with a notice that the file becomes human-owned);
  modifying an existing one is still denied.

### Added

- **`.rush/scripts/lint-shell-portability.sh`** — static check for constructs
  that break on macOS bash 3.2: heredocs inside `$( )`, bash 4+ builtins
  (`mapfile`, `declare -A`, `${var,,}`), and GNU-only flags (`grep -P`,
  `sed -i` without a suffix, `date -d`, `readlink -f`, the `timeout` binary).
  Wired into `doctor.sh` as the `shell_portability` check, and covered by the
  eval case `kit-no-bash32-breaking-constructs`, whose fixture reproduces the
  original incident.

The ratchet applied to the kit itself: the failure became a mechanism, not a
note asking people to be careful.

## 0.1.0

First release. 17 skills, 3 subagents, 14 scripts, 4 hooks, 17 templates,
3 stack presets, 17 eval cases.
