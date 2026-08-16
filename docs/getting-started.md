# Primeiros passos

Este guia cobre: pré-requisitos, como instalar o kit num repositório (existente ou novo), como
verificar a instalação, e um passo a passo completo de uma feature pequena do início ao fim.

## Pré-requisitos

- **Claude Code** — o kit é um conjunto de skills (`.claude/skills/`) e subagents
  (`.claude/agents/`) para o Claude Code. Sem ele, os arquivos em `.rush/` ainda são úteis (scripts
  puros de shell/Python), mas os comandos `/rush-*` não existem.
- **`python3`** — todo parsing determinístico (`config.json`, o grafo do integration map, os
  contratos, os hooks) usa `.rush/scripts/lib/rushlib.py`, que é stdlib puro. Nenhuma dependência
  externa de Python é instalada ou exigida.
- **`git`** — o kit lê histórico de commits para detectar convenções (`detect-stack.sh`), atribuir
  commits a features (`check-as-built.sh`) e fazer scan de segredos antes de commitar.
- **`bash`** — os scripts em `.rush/scripts/` e os hooks em `.rush/hooks/` são portáveis para bash
  3.2 (macOS) e Linux; nenhum depende de `jq` ou de flags GNU-only.
- Os comandos configuráveis (`test`, `lint`, `build`, `format`, `typecheck` em
  `.rush/config.json → commands`) dependem do stack do projeto — o kit não instala nada disso por
  você, apenas os invoca.

## Instalar num repositório existente

Clone o kit e rode o instalador apontando para o seu repositório:

```bash
git clone <url-do-rush-devkit> /tmp/rush-devkit
/tmp/rush-devkit/install.sh /path/to/seu-repo
```

O instalador copia `.claude/` (skills, subagents e o wiring dos hooks) e `.rush/` (schema de
config, templates, scripts, hooks, presets, evals), preservando o bit de execução dos scripts.

**Ele nunca sobrescreve arquivo existente** — se o seu repositório já tem `.claude/settings.json`,
`CLAUDE.md` ou um `.rush/config.json` já gerado, esses arquivos são pulados e reportados ao final.
Use `--force` para sobrescrever (revise o diff depois) ou `--dry-run` para ver o que aconteceria
sem escrever nada. Quando houver `settings.json` próprio, o caminho certo é mesclar à mão os hooks
do Rush (`SessionStart`, `PreToolUse` para `Bash`/`Edit`/`Write`/`NotebookEdit`, `PostToolUse`
para `Edit`/`Write`) em vez de trocar o arquivo inteiro.

O `.rush/config.json` **não** vem pronto de propósito: ele é gerado pelo `/rush-init` a partir do
que for detectado no seu projeto. Um config que não corresponde ao projeto é pior que nenhum,
porque toda verificação posterior herda a mentira.

Cópia manual continua funcionando, se preferir:

```bash
cp -r /tmp/rush-devkit/.claude /path/to/seu-repo/.claude
cp -r /tmp/rush-devkit/.rush   /path/to/seu-repo/.rush
```

Depois de copiar, verifique que os scripts continuam executáveis (a cópia de arquivo às vezes
derruba o bit `+x`):

```bash
chmod +x /path/to/seu-repo/.rush/scripts/*.sh /path/to/seu-repo/.rush/hooks/*.sh
```

Com o Claude Code aberto na raiz do projeto, rode:

```
/rush-init
```

`rush-init` detecta a stack (`.rush/scripts/detect-stack.sh`), explora a arquitetura real via o
subagent `rush-explorer`, confirma o que detectou com você, faz uma entrevista curta sobre o que o
código não revela (produto, estágio, o que nunca pode quebrar) e só então gera, com sua aprovação:
`CLAUDE.md`, `.rush/config.json`, `.rush/memory/constitution.md`, `.rush/memory/product.md`,
`.rush/memory/architecture.md` e os arquivos vazios `questions.md`, `debt.md`, `lessons.md`. No
final ele roda os comandos configurados (test/lint/build/typecheck) e `doctor.sh` como smoke
test — **o harness só é considerado instalado se os comandos realmente rodarem**.

`rush-init` recusa rodar se o repositório não tiver código ainda — nesse caso ele para e indica
`/rush-new`.

## Criar um produto novo

Em um repositório vazio ou quase vazio:

```
/rush-new "<ideia do produto em uma linha>"
```

`rush-new` não é uma skill separada de infraestrutura: ele orquestra `/rush-pitch`,
`/rush-architect`, `/rush-prd` e `/rush-features` de verdade, na sequência — descoberta e corte de
MVP, escolha de stack com trade-offs reais (2–3 alternativas, aprovação explícita), scaffold com o
gerador oficial do ecossistema escolhido (`nest new`, `create-next-app`, etc.), harness mínimo, PRD
do MVP e a fila completa de specs prontas, validadas por `/rush-analyze`. Há dois pontos de
aprovação humana obrigatórios: a escolha de stack e a fila de specs terminada — nada é
escrito/escafoldado sem isso. Ao final, o próximo passo é `/rush-implement` na primeira feature da
ordem topológica.

## Verificar a instalação

A qualquer momento, especialmente logo após instalar:

```
/rush-doctor
```

ou diretamente:

```bash
.rush/scripts/doctor.sh --json --fix-suggestions
```

`doctor.sh` valida: `config.json` contra o schema, scripts executáveis e sintaticamente válidos,
hooks referenciados em `.claude/settings.json` existentes e executáveis, se os comandos de
`commands.*` realmente rodam, disponibilidade de `python3`, specs órfãs (sem código) e código sem
spec, validade do integration map, orçamentos de linha estourados, itens parados em
`questions.md`/`debt.md` há mais de `doctor.stale_days` dias, e a versão do kit. Sai com código `1`
se houver algum achado `severity: error`. A skill `/rush-doctor` transforma essa saída num relatório
priorizado com uma única "ação de maior valor" no final — ela nunca corrige nada sozinha.

## Passo a passo: uma feature pequena do início ao fim

Este exemplo segue o caminho **M** (médio porte): `/rush` → `/rush-quick` → `/rush-implement` →
`/rush-review`. Para o critério de triagem completo e o caminho **L**, veja [`flow.md`](./flow.md).

Cenário: adicionar um endpoint `GET /health` que reporta o status da aplicação e da conexão com o
banco.

### 1. `/rush "adicionar endpoint GET /health que reporta status da aplicação e do banco"`

A skill `rush` (triagem, roda em `haiku`) extrai uma lista aproximada de paths e chama:

```bash
.rush/scripts/triage.sh --paths "src/health" --files 2 --json
```

Suponha que o resultado seja `{"level":"M","forced":false,"signals":{...},"needs_human_confirmation":false}`
— sem path sensível, sem migration, sem dependência nova, sem mudança de contrato existente. A
skill explica em uma linha o sinal decisivo ("M — toca poucos arquivos, nenhum sinal de
escalonamento") e roteia para `/rush-quick`. Nenhum arquivo é criado nesta etapa — `rush` nunca
escreve spec ou código.

### 2. `/rush-quick "adicionar endpoint GET /health..."`

`rush-quick` primeiro reconfirma o nível com o mesmo `triage.sh`. Se, a qualquer momento durante a
exploração, aparecer um sinal de escalonamento (mudança de contrato existente, migration,
dependência nova, path sensível), a skill **para** e redireciona para `/rush-pitch` — isso não
aconteceu aqui.

Ela cria o diretório da feature:

```bash
.rush/scripts/new-feature.sh health-check --title "Health check endpoint" --json
```

o que gera `specs/003-health-check/` com `spec.md`, `plan.md`, `tasks.md`, `done-contract.md` e
`progress.md` copiados dos templates (com `{{FEATURE_ID}}`, `{{FEATURE_TITLE}}`, `{{DATE}}` já
substituídos), e registra a feature como ativa em `.rush/state.json`.

Em seguida, `rush-quick` escreve:

- **`spec.md`** (dentro do orçamento de 150 linhas): Behaviour (o que o endpoint retorna e em que
  condições), Interfaces → Provides `GET /health`, Acceptance Criteria numeradas e testáveis, Out
  of Scope, Assumptions. Como o endpoint é uma interface nova, `specs/integration-map.md` é
  atualizado com a entrada `provides` correspondente e `.rush/scripts/validate-integration-map.sh
  --json` é rodado para confirmar que não há violação.
- **`tasks.md`**: unidades pequenas e independentemente verificáveis, cada uma com seu `verify:`,
  todas começando `pending`. Exemplo: `T1 — implementar handler GET /health` com
  `verify: npm test -- health`.
- **`done-contract.md`**: bloco `json` com pelo menos um check de teste de aceitação, mais
  `validate-integration-map.sh` já que uma interface foi tocada, e um `human_gates` para a revisão
  assistida.

Depois roda `.rush/scripts/validate-artifacts.sh 003-health-check --json` e corrige qualquer
violação de orçamento ou seção faltante (até 3 iterações).

Neste ponto, `specs/003-health-check/` contém:

```
spec.md            — behaviour + interface GET /health + critérios de aceite
plan.md             — ainda o template não preenchido (o caminho M não gera um plano separado;
                       o "como" cabe nos verify: das tasks)
tasks.md            — tasks pendentes, cada uma com verify:
done-contract.md    — checks + human_gates negociados com você antes de qualquer código
progress.md         — vazio, pronto para a primeira entrada de sessão
```

O que você decide aqui: aprovar o `done-contract.md` proposto (é negociado, não imposto) e
confirmar as no máximo 3 perguntas que a skill eventualmente fizer sobre escopo, segurança ou UX.

### 3. `/rush-implement 003-health-check`

Antes de tocar em qualquer arquivo, a skill roda o ritual de sessão
(`.rush/scripts/session-start.sh --json`) e o **baseline check** — o comando de teste configurado
em `commands.test`. Se o baseline já estiver quebrado, ela para: não dá para atribuir falhas ao
próprio trabalho a partir de um ponto de partida vermelho.

Para cada task, o loop é sempre o mesmo:

1. **Plan** — declara em 1–2 linhas o que vai mudar; marca
   `task-status.sh 003-health-check --set T1 in_progress --by rush-implement`.
2. **Act** — implementa a menor mudança que satisfaz a task, respeitando contratos existentes e as
   convenções de `CLAUDE.md`.
3. **Observe** — despacha o subagent `rush-verifier`, que roda o `verify:` da task mais
   lint/typecheck/build configurados e decide pass/fail — nunca quem implementou.
4. **Adjust** — em falha, forma uma hipótese sobre a causa antes de mudar qualquer coisa; conta a
   tentativa. Ao atingir `autonomy.max_attempts_per_task` (padrão 3), para e escala ao humano com o
   que tentou e por quê acha que falha.
5. **Close** — só o `rush-verifier` promove a task:
   `task-status.sh 003-health-check --set T1 done --by rush-verifier`. Depois, uma linha em
   `progress.md` e um commit (se `git.allow_commit` for `true`), com a convenção de commit do
   projeto e referência à feature/task.

Ao fim de todas as tasks: `check-as-built.sh 003-health-check --json` (reconcilia qualquer drift
entre o que foi planejado e o que o git mostra) e `done-check.sh 003-health-check --json` (executa
o `done-contract.md`; os `human_gates` continuam pendentes — nenhum agente os confirma).

O que você decide aqui: nada de obrigatório ainda — os gates humanos deste passo (`implement_start`)
são `auto` por padrão; o gate humano real chega no próximo passo.

### 4. `/rush-review 003-health-check`

Uma revisão **assistida e interativa**: a skill roda em `opus`, lê `done-check.sh` como estado
objetivo de partida, e caminha arquivo por arquivo (ou grupo coerente de mudanças), sempre
conectando cada trecho a um critério de aceite ou decisão de arquitetura, parando para você reagir
antes de seguir. Ela nunca corrige nada durante a revisão — achados viram itens em
`specs/003-health-check/review.md`, classificados por severidade (blocker / should-fix / nitpick).

O que você decide aqui: se a implementação está aprovada. `feature_close` é `human` por padrão em
`config.json → gates` — a skill não confirma esse gate por você; ela indica exatamente como
registrar a confirmação (em `.rush/state.json → gates_confirmed.<feature-id>`) depois que você
decidir.

Depois de fechada, `/rush-retro 003-health-check` (opcional) transforma qualquer falha real que
aconteceu no caminho em um mecanismo permanente — veja [`evals.md`](./evals.md).

## Próximos passos

- Entenda os 17 skills e 3 subagents em [`agents.md`](./agents.md).
- Entenda a triagem S/M/L e o fluxo completo L em [`flow.md`](./flow.md).
- Entenda hooks, config e os limites de segurança em [`harness.md`](./harness.md).
- Entenda o que "pronto" significa em cada nível em [`definition-of-done.md`](./definition-of-done.md).
