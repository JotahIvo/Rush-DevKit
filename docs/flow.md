# O fluxo: triagem, S/M/L e os gates humanos

O Rush DevKit não força todo pedido de mudança pelo mesmo processo. A primeira decisão de qualquer
trabalho é **quanto processo ele merece** — essa é a função da skill `/rush`, o ponto de entrada.

## Triagem S/M/L

`/rush "<descrição do que você quer mudar>"` roda `.rush/scripts/triage.sh --paths "..." --files N
--json`, que calcula sinais determinísticos — a skill nunca adivinha um sinal que o script já
computa:

```json
{ "level": "L", "forced": true,
  "signals": { "file_count": 2, "sensitive_paths_touched": ["src/auth/login.ts"],
               "contract_changed": false, "migration_detected": false,
               "new_dependency": false },
  "reasons": ["toca path sensível: src/auth/"],
  "needs_human_confirmation": false }
```

Critérios do script:

| Sinal | Efeito |
|---|---|
| Toca um path listado em `security.sensitive_paths` (e `triage.sensitive_forces_L` é `true`) | força `L`, `forced: true` |
| Migration detectada | força `L` |
| Nova dependência (lockfile/manifest mudou) | força `L` |
| Mudança de contrato existente | força `L` |
| Nenhum dos sinais acima, e `file_count <= triage.max_files_for_S` (padrão 3) | `S` |
| Nenhum sinal acima, mas acima do limite de arquivos | `M`, com `needs_human_confirmation: true` |

A skill `rush` aplica julgamento **em cima** dos sinais, nunca no lugar deles:

- `forced: true` vence sempre — não é negociável, e a skill nomeia o sinal que decidiu.
- Incerteza de produto (pedido vago, sem critério de aceite claro, "não sei bem o que eu quero")
  eleva para **L** mesmo que o script diga S ou M — um diff pequeno preso a um objetivo confuso não
  é uma tarefa pequena.
- Quando o julgamento da skill diverge do `level` do script, ou `needs_human_confirmation` é
  `true`, ela faz **exatamente uma** pergunta de confirmação, com o nível proposto e a razão — nunca
  um questionário.

Roteamento final:

| Nível | Rota |
|---|---|
| **S** | Edição direta na sessão atual, seguida de `rush-verifier` e uma micro-revisão. Nenhum diretório de feature é criado. |
| **M** | `/rush-quick "<pedido>"` — caminho enxuto, sem PRD nem arquitetura. |
| **L** | `/rush-prd "<pedido>"` — início do fluxo completo. `/rush-pitch` antes dele só quando o pedido é uma frase solta sem problema declarado. |

## O fluxo L completo

```
(/rush-pitch)  →  /rush-prd  →  /rush-architect  →  /rush-features  →  /rush-spec (por feature,
    opcional                                                            gera prd + contratos junto —
                                                                        ou /rush-spec-all p/ todas)
                                                                            │
                                                              /rush-prototype (opcional)
                                                                            │
                                                                            ▼
                                                                    /rush-analyze (GO/NO-GO)
                                                                            │
                                                                            ▼
                                                                    /rush-implement
                                                                            │
                                                                            ▼
                                                                     /rush-review
                                                                            │
                                                                            ▼
                                                                    /rush-pr (por spec)
                                                                            │
                                                                            ▼
                                                                     /rush-retro (opcional)
```

Cada seta é uma fronteira de dono do artefato — nunca uma etapa arbitrária:

1. **`/rush-pitch`** *(opcional)* — problema, público, apetite, forma da solução, riscos, fora de
   escopo. Nenhuma tecnologia, endpoint ou tela. Existe para o caso em que a ideia ainda é uma
   frase e o problema por trás dela não foi nomeado: moldar isso numa página, barata e
   descartável, antes de alguém escrever requisito. Quando o problema já está claro, pule — o
   `/rush-prd` faz a própria conversa de enquadramento e um pitch aí só adiciona documento.
2. **`/rush-prd`** — **a porta de entrada real do fluxo L.** Define, completo, tudo que o spec vai
   construir: problema, usuários e casos de uso, metas, fora de escopo, requisitos funcionais
   numerados `FR-NNN` e testáveis, atributos de qualidade com alvo mensurável, domínio e dados,
   user journeys (que viram testes de jornada), restrições, métricas de sucesso, riscos e
   suposições. Não tem teto de tamanho: é o artefato que todo o resto cita de volta.
3. **`/rush-architect`** — como o sistema inteiro do spec é estruturado, **a partir do PRD**: cada
   linha da tabela de atributos de qualidade é um alvo que a estrutura tem que entregar. Produz
   2–3 candidatos com trade-offs, um ADR e fitness functions executáveis. Roda pelas 13
   disciplinas (atributos de qualidade, boundaries, contratos, dados/migração, segurança,
   resiliência, performance, observabilidade, dependências, integrações externas, custo e — se
   `ai_features` for `true` — integração de IA). Grava a arquitetura completa em
   `specs/<spec-id>/architecture.md` e um resumo condensado em `.rush/memory/architecture.md`.
4. **`/rush-features`** — divide o PRD em unidades de feature e produz `specs/integration-map.md`:
   o grafo `provides`/`consumes`, os contratos compartilhados com dono único, e as journeys — o
   mecanismo que impede uma feature de existir isolada. Ver [`integration.md`](./integration.md).
5. **`/rush-spec`** (uma vez por feature, na ordem topológica que o integration map devolve, ou
   `/rush-spec-all <spec-id>` para rodar o processo em todas de uma vez) — `prd.md` (a fatia de
   produto daquela feature: quem serve, quais `FR-NNN` do PRD do spec ela entrega, o que deixa
   explicitamente para uma feature irmã), `spec.md`, `plan.md`, `tasks.md`, `done-contract.md`
   (com os critérios de aceite embutidos); quando a feature expõe
   uma interface, os contratos (OpenAPI/JSON Schema/AsyncAPI) são gerados no mesmo processo,
   congelados antes da implementação. `/rush-contracts` continua existindo, mas só para
   re-sincronizar um contrato depois de mudado, ou gerar um que ficou pendente.
6. **`/rush-prototype`** (opcional, invocação explícita) — um HTML estático e descartável do fluxo,
   nunca promovido a código real.
7. **`/rush-analyze`** — gate de consistência go/no-go entre spec, plan, contratos, constitution e
   integration map. Veredito sempre binário.
8. **`/rush-implement`** — código, task por task, cada uma verificada pelo `rush-verifier`.
9. **`/rush-review`** — revisão assistida e interativa antes do gate `feature_close`.
10. **`/rush-pr`** — escreve `specs/<spec-id>/pr.md`, a descrição do pull request do **spec
    inteiro** (não de uma feature): todo commit desde a criação do spec e o status de done-check de
    cada feature sob ele, no formato definido uma vez em `.rush/memory/pr-preferences.md`. Uma
    feature com check falhando ou gate pendente aparece como incompleta, por mais que os commits
    dela pareçam terminados.
11. **`/rush-retro`** (opcional) — falhas reais viram mecanismo permanente (eval case, fitness
    function) ou regra registrada em `lessons.md`.

### Por que o PRD vem antes da arquitetura

A ordem inversa — arquitetar primeiro, escrever requisito depois — produz um PRD que já nasce
justificando decisões estruturais tomadas antes de alguém enunciar o que o sistema precisa fazer.
Com o PRD primeiro, a arquitetura recebe um alvo: cada atributo de qualidade da tabela é um
compromisso com número, e uma linha que a arquitetura não consegue atender dentro do apetite vira
um achado para levantar com o usuário, não um número que se afrouxa em silêncio.

`/rush-new` (projeto novo) executa essencialmente os passos 1–7 em sequência automaticamente, com
apenas dois pontos de aprovação humana no meio (a escolha de stack, e a fila de specs terminada) em
vez de um gate por feature.

## O caminho M (`/rush-quick`)

`/rush-quick "<o que você quer mudar>"` produz um `spec.md` condensado (mesmas seções obrigatórias
do spec completo, deliberadamente mais magro em conteúdo), `tasks.md` e um `done-contract.md`
mínimo — sem pitch, sem PRD, sem arquitetura. Ele chama `new-spec.sh --minimal` e
`new-feature.sh --no-prd` justamente para não deixar template de PRD por preencher no caminho M,
que ninguém voltaria para preencher. É um caminho de primeira classe: a maioria das
mudanças num projeto maduro é M, e forçá-las pelo fluxo completo seria peso de processo errado.

A regra mais importante desta skill é a **escalação imediata**: se em qualquer ponto — explorando o
código, escrevendo o spec ou definindo as tasks — ela encontra uma mudança de contrato existente,
uma migration, uma dependência nova ou um path sensível, ela **para ali mesmo**, não termina os
artefatos, não segue para `/rush-implement`, e redireciona para `/rush-pitch` no mesmo slug de
feature (nada do trabalho já feito é perdido). Isso existe porque artefatos M não passam por
revisão de arquitetura nem PRD — não têm como pegar o que uma mudança maior precisava.

Mesmo no caminho rápido, se a mudança fornece ou consome algo que outra feature poderia tocar, o
`specs/integration-map.md` é atualizado e validado — pular isso "porque é só M" é exatamente como o
mapa apodrece.

## O caminho S

Sem skill dedicada além do roteamento de `/rush`: edite diretamente na sessão, rode
`rush-verifier` no final, e faça uma micro-revisão antes de considerar concluído. Nenhum diretório
`specs/<id>/` é criado — o overhead de um processo completo não se justifica para 1–3 arquivos sem
sinal de risco.

## Fora da triagem: continuidade entre sessões

`/rush-context-save` e `/rush-context-load` não pertencem a nenhum dos três caminhos — valem para
qualquer um deles, porque o que eles resolvem é ortogonal ao tamanho da mudança: o que uma conversa
descobriu e que **só existe nela**. `tasks.md` (Session Log), `questions.md`, `debt.md` e
`done-contract.md` já sobrevivem à sessão por conta própria e são lidos pelo processo normal de
toda skill; o que não sobrevive é o raciocínio, a abordagem que foi tentada e descartada, e a
thread que estava no meio quando a sessão acabou.

`/rush-context-save` grava exatamente isso em `.rush/memory/sessions/` (scratch local, não artefato
de projeto — vai para o `.gitignore`), e `/rush-context-load` recapitula na sessão seguinte,
checando antes se o estado do projeto mudou desde a gravação. A seção de maior valor é a de
abordagens descartadas: uma decisão adotada costuma estar visível no código ou no artefato
resultante; uma rejeitada é invisível, e sem registro a sessão nova repropõe exatamente o que já
foi tentado.

## Onde ficam os gates humanos

`config.json → gates` (veja [`configuration.md`](./configuration.md)) define, por marco, se o
harness segue sozinho (`auto`) ou exige aprovação explícita (`human`):

| Gate | Padrão | O que segura |
|---|---|---|
| `architecture` | `human` | Aceitar a saída de `/rush-architect` antes que qualquer spec de feature construa em cima dela. |
| `spec` | `human` | Aprovar o `done-contract.md` negociado antes que `/rush-implement` rode contra ele. |
| `feature_close` | `human` | Confirmar a revisão assistida (`/rush-review`) antes de fechar a feature, mesmo com todo check automático verde. |
| `implement_start` | `auto` | Deixar `/rush-implement` começar a codar assim que spec e done-contract existem e foram aprovados. |

Um gate humano não é decorativo: `done-check.sh` reporta cada `human_gates` do `done-contract.md`
como não confirmado a menos que o texto exato do gate apareça em
`.rush/state.json → gates_confirmed.<feature-id>` — e nenhum agente escreve essa confirmação por
conta própria (Guardrail universal 5: "Never mark work as done yourself. Only `rush-verifier`
promotes status", e para o gate de revisão, só o humano confirma).

## A fronteira O QUE / COMO

Cada artefato tem exatamente um dono, e o teste de bolso para saber onde algo pertence é:

> **muda com a feature → spec; muda com o projeto → harness; não muda nunca → kit.**

| Artefato | Dono de | Proibido |
|---|---|---|
| pitch / PRD | o quê e por quê (produto) | tecnologia, endpoint, tela |
| arquitetura | como estrutural, trade-offs, fitness functions | passo a passo de implementação |
| spec | o quê técnico observável, interfaces, aceite | detalhe interno de implementação |
| plan / tasks | como da implementação | redefinir comportamento |
| harness (config/hooks/constitution) | como o agente trabalha | — |

Consequência prática: **processo de agente nunca vive numa spec.** "Rodar a suíte de testes",
"commitar ao final", "só o verifier promove status" são configuração de harness
(`.rush/config.json`, hooks) — se um `spec.md` ou `plan.md` contém uma instrução desse tipo, isso é
um achado a reportar (tipicamente por `/rush-analyze`), não conteúdo válido do artefato.

Toda skill do kit declara essa fronteira explicitamente em sua seção `Guardrails` e recusa escrever
fora da própria camada — por exemplo, `/rush-pitch` nomeia tecnologia como um achado a sinalizar,
nunca como algo a registrar no pitch; `/rush-spec` reporta uma interface que "deveria" existir mas
não está no integration map como um gap, nunca inventa uma.

## Ver também

- [`agents.md`](./agents.md) — cada skill em detalhe: o que faz, gatilho, modelo, o que não faz.
- [`integration.md`](./integration.md) — o integration map que `/rush-features` produz e que
  `/rush-analyze` audita.
- [`harness.md`](./harness.md) — como os hooks aplicam essas regras mecanicamente, não apenas por
  instrução de prompt.
