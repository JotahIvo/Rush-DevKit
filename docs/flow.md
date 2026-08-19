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
| **M** | `/rush-quick "<pedido>"` — caminho enxuto, sem pitch/PRD/arquitetura. |
| **L** | `/rush-pitch "<pedido>"` — início do fluxo completo. |

## O fluxo L completo

```
/rush-pitch  →  /rush-architect  →  /rush-prd  →  /rush-features  →  /rush-spec (por feature,
                                                                       gera contratos junto —
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
                                                                     /rush-retro (opcional)
```

Cada seta é uma fronteira de dono do artefato — nunca uma etapa arbitrária:

1. **`/rush-pitch`** — problema, público, apetite, forma da solução, riscos, fora de escopo.
   Nenhuma tecnologia, endpoint ou tela.
2. **`/rush-architect`** — como o sistema inteiro do spec é estruturado: 2–3 candidatos com
   trade-offs, um ADR, fitness functions executáveis. Roda pelas 13 disciplinas (atributos de
   qualidade, boundaries, contratos, dados/migração, segurança, resiliência, performance,
   observabilidade, dependências, integrações externas, custo e — se `ai_features` for `true` —
   integração de IA). Grava a arquitetura completa em `specs/<spec-id>/architecture.md` e um
   resumo condensado em `.rush/memory/architecture.md`.
3. **`/rush-prd`** — consolida pitch + arquitetura em visão, metas, requisitos testáveis, critérios
   de sucesso mensuráveis e as user journeys (que depois viram testes de jornada).
4. **`/rush-features`** — divide o PRD em unidades de feature e produz `specs/integration-map.md`:
   o grafo `provides`/`consumes`, os contratos compartilhados com dono único, e as journeys — o
   mecanismo que impede uma feature de existir isolada. Ver [`integration.md`](./integration.md).
5. **`/rush-spec`** (uma vez por feature, na ordem topológica que o integration map devolve, ou
   `/rush-spec-all <spec-id>` para rodar o processo em todas de uma vez) — `spec.md`, `plan.md`,
   `tasks.md`, `done-contract.md` (com os critérios de aceite embutidos); quando a feature expõe
   uma interface, os contratos (OpenAPI/JSON Schema/AsyncAPI) são gerados no mesmo processo,
   congelados antes da implementação. `/rush-contracts` continua existindo, mas só para
   re-sincronizar um contrato depois de mudado, ou gerar um que ficou pendente.
6. **`/rush-prototype`** (opcional, invocação explícita) — um HTML estático e descartável do fluxo,
   nunca promovido a código real.
7. **`/rush-analyze`** — gate de consistência go/no-go entre spec, plan, contratos, constitution e
   integration map. Veredito sempre binário.
8. **`/rush-implement`** — código, task por task, cada uma verificada pelo `rush-verifier`.
9. **`/rush-review`** — revisão assistida e interativa antes do gate `feature_close`.
10. **`/rush-retro`** (opcional) — falhas reais viram mecanismo permanente (eval case, fitness
    function) ou regra registrada em `lessons.md`.

`/rush-new` (projeto novo) executa essencialmente os passos 1–7 em sequência automaticamente, com
apenas dois pontos de aprovação humana no meio (a escolha de stack, e a fila de specs terminada) em
vez de um gate por feature.

## O caminho M (`/rush-quick`)

`/rush-quick "<o que você quer mudar>"` produz um `spec.md` condensado (mesmo orçamento de 150
linhas do spec completo, mas deliberadamente mais magro), `tasks.md` e um `done-contract.md`
mínimo — sem pitch, sem PRD, sem arquitetura. É um caminho de primeira classe: a maioria das
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
