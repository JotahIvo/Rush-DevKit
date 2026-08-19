# Configuração: `.rush/config.json`

`.rush/config.json` é validado contra `.rush/config.schema.json` e lido por toda skill antes de
qualquer ação — é um contrato, não uma preferência (veja
[`harness.md`](./harness.md#configjson-como-contrato-aplicado-não-sugestão) para como os hooks o
aplicam mecanicamente). Esta página lista toda chave do schema: o que faz, valores válidos, o
padrão, e — o que o schema por si só não deixa óbvio — **quem lê essa chave e o que muda quando ela
muda**.

`config.json` é gerado por `/rush-init`/`/rush-new` a partir de `.rush/config.default.json`,
sobreposto pelos `config_overrides` de um preset detectado e pelas suas respostas na entrevista.
Ele mesmo é um arquivo protegido: nenhum agente pode editá-lo (`guard-edit.sh` nega qualquer
tentativa) — só um humano, ou uma nova rodada de `/rush-init --refresh`.

## `version`

String no formato `N.N.N`. Versão do **formato do schema**, não do projeto nem do kit. `doctor.sh`
a compara contra o que `.rush/VERSION` espera para avisar sobre config desatualizado depois de um
upgrade do kit. Consequência de mudar manualmente: nenhuma, a menos que você também tenha migrado a
forma do arquivo — mudar só o número não muda comportamento.

## `language`

| Chave | Valores | Padrão | Consequência de mudar |
|---|---|---|---|
| `language.docs` | tag BCP-47 (`"en"`, `"pt-BR"`, ...) | `"en"` | Todo texto voltado ao usuário e todo artefato gerado (pitch, PRD, spec, relatórios no chat) passa a ser escrito nesse idioma. Toda skill lê isso antes de escrever a primeira linha de prosa. **Nunca** afeta o idioma dos prompts (`SKILL.md`/subagents ficam em inglês por convenção do kit — veja `docs/internals/kit-conventions.md`) nem identificadores de código. |
| `language.code_comments` | tag BCP-47 | `"en"` | Idioma dos comentários que agentes escrevem dentro do código. Independente de `docs`, para permitir documentar em um idioma e comentar código em outro. |
| `language.commits` | tag BCP-47 | `"en"` | Idioma do assunto/corpo das mensagens de commit escritas por agentes. Independente das outras duas, para manter o histórico consistente mesmo que o idioma da documentação mude no meio do projeto. |

## `git`

| Chave | Valores | Padrão | Quem lê / consequência |
|---|---|---|---|
| `git.allow_commit` | boolean | `true` | Lido por `guard-bash.sh`. Com `false`, **nenhum** agente pode rodar `git commit`, sob nenhuma circunstância — eles deixam a mudança em staged e reportam; o commit vira ato humano. |
| `git.allow_push` | boolean | `false` | Lido por `guard-bash.sh`. Com `false` (padrão seguro), nenhum `git push` é permitido mesmo com `allow_commit=true` — é uma permissão deliberadamente separada e de risco maior. Só ative em ambientes onde push autônomo é risco aceito. |
| `git.commit_convention` | `"conventional"` \| `"gitmoji"` \| `"none"` \| `"custom"` | `"conventional"` | Lido por `guard-bash.sh`, que valida a mensagem de todo `git commit -m`/`--message` contra o formato esperado e **nega** o commit se não bater. `"none"`/`"custom"` não são checados estaticamente pelo hook (para `"custom"`, a convenção real precisa estar documentada em `constitution.md`/`CLAUDE.md`, que os agentes leem antes de compor a mensagem). `detect-stack.sh` reporta separadamente a convenção **realmente observada** no histórico, para você conferir se o valor declarado bate com a realidade. |
| `git.branch_pattern` | string (ex. `"feat/NNN-slug"`) | `"feat/NNN-slug"` | **Declarado no schema como aplicado por hook, mas isso não está implementado hoje** — nenhum hook lê ou valida esta chave. Veja [`harness.md`](./harness.md#discrepância-conhecida-branch_pattern-não-é-aplicado). Trate como documentação de convenção até que a aplicação exista de fato. |

## `code`

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `code.comments_policy` | `"none"` \| `"minimal"` \| `"didactic"` | `"minimal"` | Governa a densidade de comentários explicativos que `/rush-implement` escreve. `"none"`: só o que o linter exigir. `"minimal"`: só decisões não óbvias. `"didactic"`: denso, apropriado para projeto didático/referência. Nunca afeta corretude, só volume. |
| `code.test_first` | boolean | `false` | Lido por `/rush-implement`. Com `true`, cada task exige escrever e rodar um teste que falha antes de escrever a implementação (red-green). Com `false`, testes podem vir junto ou depois — de qualquer forma, `done-contract.md` continua sendo o gate final. |

## `commands`

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `commands.test` | string ou `null` | `null` | Lido por `done-check.sh` e `rush-verifier` como o sinal primário de pass/fail. `null` significa nenhum comando configurado ainda — scripts que dependem dele pulam a checagem, e `doctor.sh` sinaliza a lacuna. |
| `commands.lint` | string ou `null` | `null` | Rodado antes de commit e por `rush-verifier` quando relevante à mudança. |
| `commands.build` | string ou `null` | `null` | Detecta quebra de integração que só testes unitários não pegam. |
| `commands.format` | string ou `null` | `null` | Lido por `post-edit.sh`: se configurado, roda automaticamente depois de todo `Edit`/`Write`. Se `null`, o hook não faz nada — é a própria presença do comando que liga a formatação automática, não uma chave separada de on/off. |
| `commands.typecheck` | string ou `null` | `null` | Passo separado de `build`/`lint` porque alguns stacks (TS com bundler, Python com mypy/pyright) rodam isso com seu próprio exit code independente. |

Todos os cinco são populados por `rush-init`/`rush-new` a partir de `detect-stack.sh` ou de um
preset — nunca adivinhados; um comando `null` é pulado pelos scripts que o usariam, em vez de um
comando inventado que quebraria silenciosamente.

## `gates`

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `gates.architecture` | `"human"` \| `"auto"` | `"human"` | Se `"human"`, uma pessoa precisa aprovar a saída de `/rush-architect` antes de qualquer spec de feature construir em cima dela. Decisões estruturais são caras de desfazer — o padrão seguro é `"human"`. |
| `gates.spec` | `"human"` \| `"auto"` | `"human"` | Se `"human"`, uma pessoa aprova o `done-contract.md` negociado antes de `/rush-implement` rodar contra ele. |
| `gates.feature_close` | `"human"` \| `"auto"` | `"human"` | Se `"human"`, uma pessoa ainda confirma a revisão assistida (`/rush-review`) antes do fechamento, mesmo com todo check automático verde. |
| `gates.implement_start` | `"human"` \| `"auto"` | `"auto"` | Se `"auto"` (padrão comum), `/rush-implement` começa a codar assim que spec e done-contract existem e foram aprovados — os gates de `spec`/`architecture` já são o ponto de revisão. Ajuste para `"human"` se quiser um sinal verde extra explícito antes do código começar. |

Nenhum desses gates é aplicado por um hook automatizado hoje — a aplicação é via `done-check.sh`
reportando `human_gates` como pendentes até `.rush/state.json → gates_confirmed.<feature-id>`
conter o texto exato do gate, e via as próprias skills se recusando a prosseguir sem a confirmação
que a configuração pede.

## `autonomy`

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `autonomy.max_attempts_per_task` | inteiro ≥ 1 | `3` | Critério de parada negativo do loop de `/rush-implement`: depois de N falhas do verifier na mesma task, o agente para e escala em vez de tentar de novo. |
| `autonomy.new_dependency` | `"ask"` \| `"allow"` \| `"deny"` | `"ask"` | `"ask"`: agente pausa e pede aprovação antes de adicionar uma dependência nova. `"allow"`: decide sozinho, ainda reportando. `"deny"`: nunca adiciona, sinaliza a necessidade como achado. Também alimenta `triage.sh`: uma dependência nova sempre força nível L quando isto não é `"allow"`. |
| `autonomy.migrations` | `"ask"` \| `"allow"` \| `"deny"` | `"ask"` | Mesmo padrão para migrations de banco/schema — `"ask"` é o padrão seguro porque migrations são difíceis de reverter limpo. |
| `autonomy.edit_tests` | `"ask"` \| `"allow"` \| `"deny"` | `"ask"` | Governa editar/afrouxar um teste ou check existente para fazer algo passar. Com `"ask"` ou `"deny"`, `guard-edit.sh` **bloqueia mecanicamente** a edição de qualquer arquivo que pareça teste — não é só uma instrução de prompt. `"allow"` só é apropriado em projetos de baixo risco/protótipo. |

## `security`

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `security.sensitive_paths` | array de globs | `[]` | Lido por `triage.sh` (força nível L quando `triage.sensitive_forces_L` é `true`) e por `guard-edit.sh` (permite a edição, mas injeta um aviso explícito). Tipicamente semeado por `rush-init`/um preset com paths de auth/pagamento/segredos detectados. |
| `security.blocked_commands` | array de strings/regex | `[]` | Lido por `guard-bash.sh`: qualquer comando que dê match é **sempre negado**, antes de qualquer outra regra. Vazio por padrão — estenda conforme comandos de risco forem identificados. |
| `security.secret_scan_before_commit` | boolean | `true` | Lido por `guard-bash.sh`: com `true`, `secret-scan.sh --staged` precisa sair `0` antes de qualquer commit; um achado bloqueia. Desative só se um scan equivalente já roda em outro lugar (hook externo, ou política de scan só em CI). |

## `triage`

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `triage.sensitive_forces_L` | boolean | `true` | Lido por `triage.sh`. Com `true`, tocar qualquer path de `security.sensitive_paths` sempre força nível L, não importa quão poucos arquivos. Desligar isso raramente é apropriado — existe principalmente para permitir relaxar a triagem temporariamente enquanto se ajusta a lista de `sensitive_paths` em si. |
| `triage.max_files_for_S` | inteiro ≥ 1 | `3` | Lido por `triage.sh`. Número máximo de arquivos para uma mudança ainda qualificar como nível S quando nenhum outro sinal força um nível maior. Subir o valor deixa mais mudanças pularem o fluxo completo; baixar empurra mais trabalho para revisão spec-driven. |

## `budgets`

Lidos por `.rush/scripts/validate-artifacts.sh`. Todos são contagens máximas de linha; estourar o
orçamento é sinal de que o artefato/feature deveria ser dividido, não que o limite deveria subir
casualmente.

| Chave | Padrão | Artefato |
|---|---|---|
| `budgets.pitch` | 60 | `pitch.md` |
| `budgets.prd` | 200 | `prd.md` |
| `budgets.spec` | 150 | `spec.md` de uma feature |
| `budgets.plan` | 100 | `plan.md` de uma feature |
| `budgets.architecture` | 100 | seção por-feature de `architecture.md` (não o arquivo inteiro) |
| `budgets.claude_md` | 60 | `CLAUDE.md` do projeto |
| `budgets.constitution` | 200 | `.rush/memory/constitution.md` |

## `verification`

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `verification.check_timeout_seconds` | inteiro ≥ 1 | `600` | Lido por `done-check.sh`: timeout por check do `done-contract.md`. Um check que estoura é reportado como falha de timeout, não deixado pendurado. |
| `verification.stale_spec_commits` | inteiro ≥ 1 | `10` | Lido por `check-as-built.sh`: número de commits de código numa feature sem atualização correspondente em `spec.md` antes de reportar drift (`stale_spec`). Baixar pega drift mais cedo, ao custo de mais avisos. |

## `doctor`

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `doctor.stale_days` | inteiro ≥ 1 | `14` | Lido por `doctor.sh`: dias que um item aberto em `questions.md`/`debt.md` pode ficar parado antes de ser sinalizado como estagnado. |

## `memory`

Bloco opcional — um `config.json` de antes desta chave existir se comporta exatamente como se ela
estivesse presente com o valor padrão; nada quebra pela ausência.

| Chave | Valores | Padrão | Consequência |
|---|---|---|---|
| `memory.archive_after_days` | inteiro ≥ 0 | `90` | Lido por `memory-prune.sh`: idade, em dias desde a data mais recente encontrada na seção, antes de uma entrada resolvida de `debt.md` (status `accepted`/`repaid`) ou a seção de um spec totalmente fechado no resumo de `architecture.md` virar elegível para arquivamento. Uma entrada `open`, ou um spec ainda não fechado, nunca é elegível, não importa a idade. |

## `ai_features`

Boolean, padrão `false`. Declara se **o produto sendo construído** (não o próprio kit) expõe
features de IA/LLM. Com `true`, `/rush-architect` e `/rush-spec` aplicam escrutínio extra (superfície
de prompt injection, comportamento de fallback de modelo, orçamentos de custo/latência) e o campo
`ai_sdks` de `detect-stack.sh` passa a ser sinal relevante em vez de ruído. **Nunca** liga ou
configura o modelo usado para rodar os próprios agentes do kit — isso é fixado no frontmatter de
cada skill, não aqui. O próprio schema é explícito sobre essa separação.

## Modelo por agente

`config.json` **não tem uma chave para trocar o modelo de um agente** — de propósito. O schema
declara isso na própria descrição do arquivo: "It does NOT configure which model each agent uses:
model choice lives in each skill's own frontmatter [...] and is never duplicated here." A única
forma real de trocar o modelo de uma skill é editar o campo `model:` no frontmatter do
`SKILL.md` correspondente:

```yaml
---
name: rush-spec
model: opus
---
```

Tabela recomendada de modelos por agente (de `docs/internals/kit-conventions.md`):

| Modelo | Agentes |
|---|---|
| `opus` | `rush-init`, `rush-new`, `rush-architect`, `rush-pitch`, `rush-prd`, `rush-features`, `rush-spec`, `rush-analyze`, `rush-review` |
| `sonnet` | `rush-quick`, `rush-implement`, `rush-contracts`, `rush-prototype`, `rush-retro`, `rush-explorer`, `rush-researcher` |
| `haiku` | `rush` (triagem), `rush-doctor`, `rush-brief`, `rush-verifier` |

Quem tem acesso a um tier ainda mais alto pode trocar `model: opus` por `model: fable` em
`rush-init` e `rush-architect` — são os dois pontos de maior alavancagem do kit (fundação e
estrutura, respectivamente). Nunca fixe um model ID completo/versionado no frontmatter; use o
alias de tier.

## Ver também

- [`harness.md`](./harness.md) — como cada chave é efetivamente aplicada pelos hooks, não apenas
  lida por convenção.
- [`flow.md`](./flow.md) — onde `gates` e `triage` se encaixam no fluxo S/M/L.
- [`agents.md`](./agents.md) — o modelo de cada skill, já resolvido a partir do frontmatter atual.
