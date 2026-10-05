# Changelog

## 0.8.1

O `.claude/` instalado era uma mistura de versões: tinha os guardrails condensados da 0.8.0, mas
as mudanças de fluxo da 0.6.0 e a skill da 0.7.0 nunca tinham saído do staging — `rush-init` e
`rush-new` estavam sem permissão de escrita, e o resto foi sobrescrito pela 0.8.0, que semeou o
staging a partir do `.claude/` desatualizado.

### Removed

- **`models.*` no `config.json`.** Nenhum script, hook ou skill lia a chave — e nenhum poderia: uma
  skill roda no modelo do próprio frontmatter, escolhido antes de qualquer instrução dela executar.
  Uma alavanca de custo que não existe é pior que nenhuma. Saiu do schema e do `config.default.json`;
  a migração `0.8.1` remove a seção dos configs que a receberam da 0.8.0, reportando com `attention`
  quem tinha setado algum valor. Trocar o modelo de um comando é editar o `model:` do frontmatter.

### Changed

- **`/rush-analyze` virou rodada única.** Antes ele só reportava ("You never fix") e devolvia cada
  blocker à skill dona do artefato — o que terminava sempre em "corrija e rode o analyze de novo".
  Agora ele classifica cada achado em *Fix* (o estado certo já está determinado por um artefato
  acima: constitution > PRD > arquitetura > integration map > spec > contratos > plan > tasks >
  coverage), *Decide* (pergunta ao usuário, no máximo 3 por rodada, com opções e recomendação, e
  espera) ou *Run* (algo que só o usuário pode executar). Corrige, pergunta, re-verifica — scripts
  inteiros e julgamento sobre o que mudou — e só então dá o veredito. Continua proibido: decidir
  sozinho conflito com a constitution, mudar comportamento ou interface consumida por outra feature,
  e afrouxar critério, check, `verify:` ou journey test para chegar a GO. Se editou o
  `done-contract.md` com `gates.spec: human`, pede aprovação na mesma rodada. Os três evals do
  analyze foram reescritos para essa semântica.
- **Modelos revistos para a geração atual, com `effort` no frontmatter.** `opus` (`effort: high`)
  fica só onde a decisão roda uma vez e todo o resto herda o erro: init, new, architect, prd,
  features, update. O que roda por feature — spec, spec-runner, analyze, implement, quick, review —
  vai para `sonnet` com `effort: high`, com verificação determinística atrás. pitch, contracts e
  retro em `sonnet`/`medium`, prototype em `sonnet`/`low`. `haiku` para triagem, doctor, brief,
  context-save/load, pr, a orquestração do spec-all, e os três subagents de apoio: `rush-verifier`,
  `rush-explorer` e `rush-researcher`.
- **Escalonamento em vez de tier alto por padrão.** Explorer e researcher devolvem
  `CONFIDENCE: high | low`; `rush-architect` e `rush-init` os despacham com `model: sonnet` nas
  perguntas estruturais, e qualquer chamador repete em `sonnet` diante de `CONFIDENCE: low`.
- **Bloco de guardrails padronizado.** As nove skills que ainda carregavam a versão longa de sete
  itens passaram ao bloco condensado de cinco que as demais já usavam, com as variações próprias de
  cada uma preservadas e as referências "Guardrail N" renumeradas na mesma edição.

### Fixed

- **Fluxo L com PRD primeiro, de fato.** `/rush` roteia L para `/rush-prd`; `rush-prd` cria o spec
  e é a porta de entrada (FR-NNN, atributos de qualidade, journeys); `rush-architect` lê o PRD;
  `rush-pitch` é opcional e semeia com `--pitch`; `rush-new` e `rush-quick` (escalação) seguem a
  mesma ordem.
- **Cursor de feature**: `rush-features` cria com `--no-activate` e aponta o cursor no fim;
  `rush-spec` e `rush-implement` reivindicam a feature com `set-current.sh`.
- **`rush-quick` passava a gerar artefato que reprovava na validação**: agora escreve as seções que
  `validate-artifacts.sh` exige, com a Traceability citando o pedido, e os critérios de aceite no
  `done-contract.md`.
- **`rush-analyze`** volta a checar rastreabilidade (`FR-NNN` citado que não existe é blocker) e
  procura critérios de aceite no `done-contract.md`.
- **`/rush-update` instalado** em `.claude/skills/`. Removidos `.rush/_incoming/` e os
  `apply-*-claude-edits.py` — que, sem exclusão no `kitfiles.py`, seriam enviados aos projetos.
- Referências cruzadas "Guardrail N" quebradas pela renumeração da 0.8.0, em oito arquivos.
- Tetos de linha fixos nos prompts trocados pelas chaves de `config.json → budgets`.
- `git.branch_pattern`: o schema aceitava só string e dizia que não era aplicado; agora aceita
  string, lista ou `null`, e o default do schema e do `config.default.json` é a lista que a
  migração 0.5.0 já gravava.
- Docs (README, agents, flow, getting-started, configuration, kit-conventions): contagem de skills,
  tabela de modelos, `prd.md` por feature desligado, budgets ligados, bloco de guardrails condensado.

## 0.8.0

O kit gastava mais contexto lendo do que escrevendo, e ninguém tinha medido isso.

O número que abriu a investigação: uma spec real de 12 features acumulou **221 mil palavras** em
`specs/`. Não é o problema — é o inventário. O problema é que cada comando do fluxo abria o
`config.json`, a `constitution.md`, o `integration-map.md`, o `shared-contracts/` inteiro, a
`architecture.md` da spec e os ADRs **em cheio, do zero, toda vez**. Nessa spec isso dava 15.636
palavras de leitura por invocação, das quais menos de 8% mudavam alguma decisão daquele comando.
Com `/rush-spec`, `/rush-analyze`, `/rush-implement` e `/rush-review` rodando por feature, o mesmo
material era relido dezenas de vezes por spec — e o fim de sessão chegava antes do fim da feature.

Dois agravantes vieram junto. O `prd.md` de feature repetia o PRD pai e o próprio `spec.md`: 34 mil
palavras de cópia, geradas uma vez e relidas por todo comando seguinte. E os `budgets`, que a 0.6.0
tinha zerado por um motivo correto — documento cortado para bater número só empurra a decisão que
faltou para a cabeça de alguém —, deixaram de existir na prática: sem teto, `spec.md` de feature
chegou a média de 3.334 palavras, e a guardrail "density over completeness" virou texto sem
mecanismo atrás.

### Added

- **`.rush/scripts/context-pack.sh [<feature-id>] [--spec <id>] [--json]`** — uma leitura no lugar
  de seis. Entrega as chaves de config em que um comando ramifica, as **linhas vinculantes** da
  constitution (não o ensaio inteiro), a linha do `integration-map.md` **desta** feature — o que
  ela provê, o que consome e de quem, **quem quebra se o que ela provê mudar**, e as jornadas que a
  cruzam —, os **caminhos** dos contratos (nunca o corpo deles), a *decisão* de cada ADR, a lista
  de seções da `architecture.md`, as perguntas ainda abertas, o débito desta feature, a contagem de
  linhas de cada artefato contra o seu budget e as tasks por status. Na spec medida: **1.212
  palavras no lugar de 15.636** — 92% a menos, por invocação.
- **`.rush/scripts/questions.sh [<spec-id>] --open|--list|--add|--answer|--archive-answered`** — o
  `questions.md` é append-only de propósito, e por isso só cresce: o da spec medida tinha 130
  entradas e 25.743 palavras, das quais 96 já respondidas. `--open` devolve as 34 que ainda
  importam; `--archive-answered` move as antigas para `questions.archive.md` deixando um índice de
  uma linha. Nada é apagado — só deixa de ser lido.
- **`.rush/scripts/analysis-state.sh <feature-id> [--record GO|NO-GO] [--json]`** — grava a
  impressão digital de tudo contra o que um veredito foi emitido, e na próxima rodada diz
  exatamente o que mudou. É o que permite ao `/rush-analyze` julgar só o que se mexeu em vez de
  reprocessar a feature inteira depois de uma correção de uma linha. A decisão de estreitar é do
  script, não do agente: ele se invalida sozinho se a constitution, o integration-map ou qualquer
  contrato da feature mudarem, ou se não houver GO anterior gravado.
- **`artifacts.feature_prd`**, **`context.*`** e **`models.*`** no `config.json` (com schema e
  migração 0.8.0).

### Changed

- **O `prd.md` de feature deixa de ser gerado** (`artifacts.feature_prd: "off"`). O que ele tinha
  de insubstituível — o mapa dos requisitos da feature de volta para os ids do PRD pai — virou uma
  seção **Traceability** obrigatória no `spec.md` sempre que não existe `prd.md`. O
  `validate-artifacts.sh` cobra exatamente isso, então nada se perde por desligar. `new-feature.sh`
  ganhou `--prd` para o caso contrário; `--no-prd` continua valendo e agora é o default.
- **Budgets voltam ligados no `config.default.json`**, com números tirados de artefatos reais que
  passaram do ponto, e **duas chaves novas**: `tasks` e `done_contract` — o `tasks.md` é o arquivo
  mais relido da vida de uma feature, é onde comprimento composta mais rápido. Projetos existentes
  **não** são alterados: a migração relata os números e deixa a escolha, porque reprovar uma
  validação que passava ontem, em arquivos que ninguém tocou, não é migração.
- **`/rush-analyze` ficou silencioso no verde.** Script que passa vira uma linha; só a falha é
  citada verbatim. É a mesma regra que o `rush-verifier` já seguia — "success is silent, failure is
  verbose" —, que estava escrita para o verificador e não para o analisador. E o passe de
  julgamento pode ser delta, guiado pelo `analysis-state.sh`, com a obrigação de dizer quando foi.
- **Onze skills tiveram a seção `Inputs` reescrita** para o pacote de contexto, com a regra
  explícita de abrir em cheio **apenas** o que o pacote nomeou e contra o que se vai escrever.
- **O preâmbulo de guardrails repetido em 13 skills** foi condensado de 5 itens para 3, sem perder
  nenhuma regra.
- **`/rush-implement`** passa ao `rush-verifier` só o id da feature e da task. Colar o diff, o spec
  ou o raciocínio no despacho copia o contexto inteiro para dentro de um segundo contexto — o
  oposto do motivo pelo qual ele roda isolado.
- **`/rush-pr`** lê o `pitch.md` e não o `prd.md`: uma descrição de PR não é lugar de rederivar a
  definição do produto.

### Notes

- As edições sob `.claude/` estão preparadas em `.rush/_incoming-0.8.0/dot-claude/` — o bridge do
  desktop recusa escrita ali. Aplique com `python3 .rush/apply-0.8.0-claude-edits.py` (tem
  `--dry-run`, faz backup `.pre-0.8.0` de cada arquivo substituído).
- **`.rush/_incoming/` continua com o staging da 0.7.0 sem aplicar** — o `rush-update/SKILL.md`
  nunca chegou em `.claude/skills/`, e algumas descrições ali divergem do que está instalado. O
  staging da 0.8.0 foi semeado a partir do `.claude/` **vivo**, justamente para não herdar essa
  divergência. Decida o que fazer com o da 0.7.0 antes de rodar o `update.sh` numa próxima versão.

## 0.7.0

O kit não tinha caminho de atualização. `install.sh` tem dois modos e os dois estão errados para
isso: sem `--force` ele pula tudo que já existe — e depois do `/rush-init` existe tudo, então um
"update" copiava zero arquivos —, e com `--force` ele sobrescreve `config.json`, `CLAUDE.md`,
`settings.json`, a memória do projeto e os casos de eval que o `/rush-retro` escreveu. Na prática
só havia reinstalação destrutiva.

O que faltava não era um comando, eram três capacidades: **trocar** o que é do kit, **preservar**
o que é do projeto, e **migrar** o que fica no meio — as chaves de config cuja semântica mudou
entre versões. Esta versão adiciona as três.

### Added

- **`.rush/scripts/lib/kitfiles.py`** — a fonte da verdade sobre o que é de quem. Classificação
  por caminho, três classes: `kit` (substituído quando o projeto não tocou), `seed` (escrito uma
  vez na instalação, nunca revisitado — `.rush/memory/**`) e `merge` (`settings.json`, mesclado
  campo a campo). Tudo o mais nunca aparece num plano, que é como os casos de eval do
  `/rush-retro` e o `config.json` sobrevivem sem regra especial.
- **`.rush/manifest.json` e `.rush/baseline.tar.gz`**, gravados pelo `install.sh`. O manifesto
  guarda **dois** hashes por arquivo: `sha256` (o que está no disco) e `kit_sha256` (o que o kit
  enviou naquela versão). É o par que torna a comparação de três vias possível — `local ≠
  enviado` responde "o projeto mexeu", `enviado-antes ≠ enviado-agora` responde "o kit mexeu". O
  baseline guarda a cópia pristina de cada arquivo do kit, que é o que dá ao merge uma base em
  vez de adivinhação. Ambos devem ser commitados; quem clonar o projeto precisa deles.
- **`update.sh <target> [--dry-run] [--adopt] [--json] [--finalize]`** na raiz do kit. Roda a
  partir do kit **novo** contra o projeto, e não o contrário: só a versão que introduz uma
  mudança traz a migração que explica o que ela significa para um config escrito antes dela.
  Aplica tudo que é decidível, faz backup do que substitui, e para no que exige julgamento sem
  tocar no arquivo de trabalho.
- **Migrações de config** em `.rush/migrations/<versão>.py`, aplicadas em ordem para toda versão
  em `(instalada, nova]`. A pergunta que cada uma faz não é "qual é o novo default" e sim **"o
  projeto escolheu esse valor ou herdou o default de uma versão anterior?"** — herdado acompanha o
  kit, escolhido fica e é reportado. As duas primeiras são reais: `0.5.0` (o `branch_pattern` que
  deixou de ser decorativo e passaria a negar todo commit em `main` num projeto que carregava a
  string default) e `0.6.0` (os `budgets`, liberando os herdados e mantendo um `claude_md: 40` que
  alguém apertou de propósito).
- **`/rush-update`** — a skill que resolve os conflitos. Merge em três vias: aplica o que o kit
  mudou (`base` → `new`) por cima do que o projeto mudou (`base` → `local`), carregando a
  *intenção* da customização quando a versão nova reestruturou a seção onde ela morava. Faz merge
  de prompt e template apenas; script e hook param para um humano mesmo sendo legíveis, porque um
  merge sintaticamente válido e semanticamente errado no `guard-edit.sh` bloqueia toda escrita no
  projeto — inclusive a própria correção. Termina num portão de verificação obrigatório (lint de
  portabilidade, `doctor`, `validate-artifacts --all`, `eval --all`) e restaura do backup se algo
  regrediu, em vez de insistir no merge.
- **Check `kit_update` no `doctor.sh`** — reporta update pela metade, manifesto ausente (projeto
  anterior ao rastreamento; o próximo update precisa de `--adopt`), ou `.rush/VERSION` discordando
  do manifesto. Um projeto preso entre duas versões era invisível até agora.
- **`docs/updating.md`** e o caso de eval `kit-update-never-touches-project-files`, que monta duas
  versões do kit e um projeto em `mktemp -d` e prova o contrato: config, constitution, `CLAUDE.md`,
  specs e arquivo `seed` intactos; arquivo do kit não tocado acompanha o kit; arquivo customizado
  fica como está e vira conflito.

### Changed

- **`install.sh`** grava o manifesto e o baseline ao final, e aponta para o `update.sh` em vez de
  sugerir `--force` para atualizar.
- **`.rush/VERSION` só é escrito no `--finalize`**, junto do manifesto. Um projeto com conflito
  pendente não pode anunciar a versão nova enquanto ainda roda prompts da antiga — e o manifesto
  só registra o arquivo mergeado como divergente de propósito se for escrito *depois* do merge.
  Sem essa ordem, o update seguinte veria o arquivo como pristino e sobrescreveria o merge.
- **`.gitignore`** passa a cobrir `.rush/backups/` e `.rush/.update/` (temporários), deixando
  `manifest.json` e `baseline.tar.gz` versionados de propósito.

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
