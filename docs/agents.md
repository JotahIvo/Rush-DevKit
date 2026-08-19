# Skills e subagents

O Rush DevKit é composto por **18 skills** (comandos `/rush-*`, cada um um `SKILL.md` sob
`.claude/skills/<nome>/`) e **4 subagents** (`.claude/agents/*.md`, despachados pelas skills, nunca
chamados diretamente pelo usuário). O nome do diretório é o nome do comando:
`.claude/skills/rush-spec/SKILL.md` → `/rush-spec`.

Toda linha desta tabela vem literalmente do frontmatter e do corpo de cada `SKILL.md`/agent — nada
aqui é inferido ou aspiracional. Onde um comportamento parecia plausível mas não está escrito no
arquivo, ele foi deixado de fora.

Duas colunas merecem nota:

- **Trigger** — `auto` significa que o modelo pode disparar a skill sozinho a partir da
  `description` (quando o pedido do usuário casa com "o quê + quando"); `manual`
  (`disable-model-invocation: true`) significa que só um comando explícito do usuário dispara —
  reservado a skills com efeito colateral pesado (criam/alteram muitos arquivos, fazem scaffold,
  ou implementam código).
- **Modelo** — fixado no frontmatter da própria skill (`model:`), nunca em `config.json`. Veja
  [`configuration.md`](./configuration.md#modelo-por-agente) para como trocar.

## Adaptação

| Skill | O que faz | Trigger | Modelo | O que NÃO faz |
|---|---|---|---|---|
| `/rush-init` | Instala e adapta o harness a um repo existente: detecta stack, mapeia arquitetura real via `rush-explorer`, entrevista sobre produto e convenções invisíveis, gera `CLAUDE.md`, constitution, memory e `config.json`. | manual | opus | Não decide direção de produto nem desenha features; não escreve nada antes da sua aprovação; recusa rodar se não houver código (aponta para `/rush-new`). |
| `/rush-new` | Cria um produto do zero: descoberta, escolha de stack com trade-offs, scaffold com o gerador oficial, harness mínimo, PRD do MVP e a fila completa de specs, orquestrando as skills reais (não reimplementa cada uma). | manual | opus | Não escreve boilerplate à mão; não escafolda ou gera specs em massa sem aprovação explícita nos dois gates (stack e fila); para e roteia para `/rush-init` se já houver código real. |

## Descoberta

| Skill | O que faz | Trigger | Modelo | O que NÃO faz |
|---|---|---|---|---|
| `/rush-pitch` | Converte uma ideia crua em `pitch.md`: problema, público, apetite, forma da solução, riscos, fora de escopo — via conversa curta e provocativa. | auto | opus | Não nomeia tecnologia, endpoint, tela ou schema; não estima esforço em horas/pontos; no máximo 3 perguntas por rodada. |
| `/rush-architect` | Desenha a arquitetura completa do sistema de um spec nas 13 disciplinas (atributos de qualidade, boundaries, contratos, segurança, resiliência, performance, observabilidade, IA quando aplicável, etc.), produz 2–3 candidatos, recomenda um, grava ADR e escreve fitness functions executáveis. Grava a versão completa em `specs/<spec-id>/architecture.md` e um resumo condensado em `.rush/memory/architecture.md`. | auto | opus | Não decide o quê construir (isso é pitch/PRD); não escreve passo a passo de implementação (isso é o plan); nunca afirma uma propriedade de performance/segurança sem expressá-la como check; nunca copia o documento completo para dentro do resumo da memória. |

## Especificação

| Skill | O que faz | Trigger | Modelo | O que NÃO faz |
|---|---|---|---|---|
| `/rush-prd` | Consolida pitch + arquitetura em `prd.md`: visão, metas, requisitos testáveis, critérios de sucesso mensuráveis e tecnologicamente agnósticos, e as user journeys que viram testes de jornada. | auto | opus | Não redecide tecnologia/trade-offs estruturais (já decididos pela arquitetura); não faz o breakdown em features (isso é `/rush-features`); rejeita critério de sucesso fraseado como interno de sistema (latência, throughput). |
| `/rush-features` | Divide um PRD em unidades de feature entregáveis e produz/atualiza `specs/integration-map.md`: o grafo de provides/consumes, as journeys cross-feature e o teste que prova cada uma — o mecanismo que torna "feature isolada que não se conecta" estruturalmente impossível. | auto | opus | Não escreve `spec.md`/`plan.md` de nenhuma feature (isso é `/rush-spec`, uma por vez); não reabre decisões de escopo já fechadas pelo PRD. |
| `/rush-spec` | Escreve `spec.md` (comportamento observável), `plan.md` (abordagem), `tasks.md` (unidades ordenadas) e `done-contract.md` (definition of done executável, com os critérios de aceite embutidos) de uma feature; quando a feature provê uma interface, gera os contratos verificáveis (OpenAPI, JSON Schema, AsyncAPI) correspondentes no mesmo processo. | auto | opus | Não toma decisão de produto (pitch/PRD) nem estrutural (arquitetura); não escreve código; nunca inventa uma interface que o integration map atribui a outra feature; nunca duplica um contrato que outra feature já possui. |
| `/rush-spec-all` | Roda o processo completo de `/rush-spec` para todas as features de um spec, em ordem de dependência (provedor antes de consumidor), despachando um subagent `rush-spec-runner` isolado por feature — só o resultado final de cada uma volta a esta conversa — em vez de rodar tudo inline. | manual | opus | Não relaxa nenhum guardrail de `/rush-spec`; uma feature que falha ou termina com perguntas em aberto não impede as demais de serem tentadas; nunca despacha duas features concorrentemente. |
| `/rush-contracts` | Re-sincroniza um contrato (OpenAPI, JSON Schema, AsyncAPI) depois que a interface correspondente muda pós-congelamento, ou gera um contrato que `/rush-spec` deixou pendente. | auto | sonnet | Não decide o que a interface faz (isso é o spec); não implementa; não redesenha uma interface que outra feature já possui — referencia, nunca duplica. |
| `/rush-prototype` | Gera **um** mockup HTML+CSS estático e descartável do fluxo de uma feature, com dados mockados exatamente na forma dos contratos, para visualizar antes de codar. | manual | sonnet | Não é polimento visual nem interatividade real; nunca deve ser importado ou promovido a código de produção — isso é dito explicitamente no relatório e embutido como banner visível no arquivo. |
| `/rush-analyze` | Roda o gate go/no-go de consistência entre spec, plan, contratos, constitution e integration map de uma feature (ou do projeto inteiro) antes da implementação começar. | auto | opus | Nunca corrige — só reporta, com o arquivo, a regra violada e quem deve corrigir; o veredito é sempre binário (GO/NO-GO), nunca "GO com ressalvas". |

## Implementação

| Skill | O que faz | Trigger | Modelo | O que NÃO faz |
|---|---|---|---|---|
| `/rush-quick` | Caminho rápido para mudanças de porte M: um `spec.md` condensado, `tasks.md` e um `done-contract.md` mínimo, sem pitch/PRD/arquitetura, com handoff para `/rush-implement`. | auto | sonnet | Nunca produz conteúdo de `pitch.md`/`prd.md`/`architecture.md`; escala imediatamente para `/rush-pitch` (fluxo L) no instante em que detecta mudança de contrato existente, migration, dependência nova ou path sensível. |
| `/rush-implement` | Implementa uma feature task por task a partir de spec/plan/tasks, com cada task verificada pelo `rush-verifier` antes de avançar, e escalando quando uma task resiste. | manual | sonnet | Não decide o quê construir, nem a arquitetura; nunca marca nada como pronto (só o verifier promove); nunca afrouxa um check existente sem aprovação humana explícita (`autonomy.edit_tests`). |

## Revisão

| Skill | O que faz | Trigger | Modelo | O que NÃO faz |
|---|---|---|---|---|
| `/rush-review` | Caminha um humano pelo código de uma feature finalizada, arquivo por arquivo, conectando cada mudança ao spec e à arquitetura, e coletando achados interativamente — o objetivo é compreensão, não aprovação rápida. | auto | opus | Não corrige o que encontra (isso volta para `/rush-implement`); não confirma o gate humano em nome do humano; nunca despeja a revisão inteira numa mensagem só. |
| `/rush-retro` | Fecha o loop de aprendizado: cada falha real de uma feature fechada vira um mecanismo determinístico (eval case, fitness function) ou, só quando não há como automatizar, uma regra em `lessons.md`/`CLAUDE.md`. Também audita `debt.md` e o `questions.md` de cada spec. | manual | sonnet | Não reabre nem reimplementa a feature; nunca escreve mudança na constitution sem confirmação explícita do diff exato. |

## Suporte

| Skill | O que faz | Trigger | Modelo | O que NÃO faz |
|---|---|---|---|---|
| `/rush` | Ponto de entrada: classifica um pedido em S/M/L a partir de `triage.sh` e roteia — edição direta, `/rush-quick` ou `/rush-pitch`. | auto | haiku | Nunca implementa, nunca escreve spec, nunca cria diretório de feature; faz no máximo uma pergunta de confirmação. |
| `/rush-brief` | Resume o estado atual de uma feature (progresso, tasks, done-check, questões, débito, próximo passo exato) em `specs/<feature-id>/brief.md` para retomada por outra pessoa/sessão. | auto | haiku | Não muda nada — não edita spec/plan/tasks/done-contract nem status de task; se algo parece errado, registra como observação, não conserta. |
| `/rush-doctor` | Roda `doctor.sh` e transforma os achados num relatório priorizado e acionável, terminando em uma única ação de maior valor. | auto | haiku | Nunca corrige nada sozinho — nem um `chmod +x` trivial; nunca inventa achado que o script não reportou. |

## Subagents

Diferente das skills, subagents nunca são invocados diretamente pelo usuário — são despachados por
uma skill com uma pergunta específica e devolvem um resumo denso, não uma transcrição.

| Subagent | O que faz | Ferramentas | Modelo | O que NÃO faz |
|---|---|---|---|---|
| `rush-explorer` | Explora código existente e responde a uma pergunta específica sobre como parte do sistema funciona, com caminhos de arquivo citados, convenções observadas e inconsistências relatadas como fato, não escondidas. | `Read`, `Glob`, `Grep`, `Bash` | sonnet | Somente leitura: nunca edita, cria, apaga arquivo, nem roda comando que muda estado (sem install, sem migration, sem git write). |
| `rush-researcher` | Pesquisa fatos externos (versões de biblioteca, limites de protocolo, restrições de plataforma, prior art) e devolve um resumo **sempre com fonte**, nunca uma afirmação sem link. | `WebSearch`, `WebFetch`, `Read`, `Glob`, `Grep` | sonnet | Nunca resolve silenciosamente uma divergência entre fontes — reporta ambas; nunca busca URL autenticada nem usa segredo/credencial na query. |
| `rush-verifier` | Roda testes, lint, typecheck, build, fitness functions e os checks do done-contract para uma task ou feature. É o **único ator autorizado a promover uma task para `done`**. | `Bash`, `Read`, `Glob`, `Grep` | haiku | Nunca edita código-fonte, teste, config ou check; nunca promove com evidência parcial ("os testes que importam passaram" não é pass); nunca infere sucesso pela ausência de saída — sempre checa o exit code. |
| `rush-spec-runner` | Roda o processo completo de `/rush-spec` (lendo e seguindo `.claude/skills/rush-spec/SKILL.md` ele mesmo) para exatamente uma feature, em contexto isolado. Despachado só por `/rush-spec-all`, nunca para uma feature avulsa (aí é `/rush-spec` diretamente, que fica interativo com o usuário). | `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep` | opus | Nunca espera uma resposta do usuário — uma pergunta que bloquearia `/rush-spec` vira um default registrado mais uma flag `NEEDS_HUMAN_DECISION` no relatório; nunca toca em mais de uma feature por despacho. |

## Ver também

- [`flow.md`](./flow.md) — em que ordem essas skills se encadeiam, S/M/L e os gates humanos.
- [`harness.md`](./harness.md) — como hooks e config aplicam as regras que cada skill declara em
  seus Guardrails.
- [`configuration.md`](./configuration.md) — como trocar o modelo de um agente.
