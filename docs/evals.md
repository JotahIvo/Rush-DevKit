# Evals

Evals no Rush DevKit não medem "o modelo é bom" em abstrato — medem se uma skill específica, dado
um cenário concreto, continua produzindo o que o kit promete (orçamento respeitado, seção
obrigatória presente, check que passa). São a forma do kit de transformar uma falha real, já
acontecida uma vez, em algo que nunca mais passa despercebido.

## O runner: `.rush/scripts/eval.sh`

```
eval.sh [<agente>|--all] [--agent <nome>] [--case <id>] [--json]
```

Para cada caso em `.rush/evals/<agente>/cases/*.json`, aplica os graders declarados e reporta
pass/fail/manual. Formato de um caso:

```json
{
  "id": "spec-budget-respected",
  "agent": "rush-spec",
  "description": "...",
  "given": { "cwd": "opcional, relativo à raiz do projeto", "setup": "comando shell opcional" },
  "graders": [
    { "type": "script", "run": "<comando>", "expect": "exit 0" },
    { "type": "file_exists", "path": "specs/007-checkout/spec.md" },
    { "type": "budget", "file": "specs/007-checkout/spec.md", "max_lines": 150 },
    { "type": "contains", "file": "specs/007-checkout/done-contract.md", "text": "## Acceptance Criteria" },
    { "type": "manual", "rubric": "..." }
  ]
}
```

## Os graders em camadas

Cada caso pode combinar graders de naturezas diferentes — isso é o que torna a suíte "em camadas",
não um único tipo de check repetido:

| Tipo | O que verifica | Determinístico? |
|---|---|---|
| `script` | Roda um comando e compara com `expect` (`"exit 0"`, `"exit N"`, `"contains: <texto>"`, `"not_contains: <texto>"`) — **exatamente o mesmo vocabulário** que `done-check.sh` usa para os checks de um `done-contract.md`. | Sim |
| `file_exists` | Um arquivo no `path` dado existe. | Sim |
| `budget` | Um arquivo não excede `max_lines` — a mesma lógica de orçamento que `validate-artifacts.sh` aplica em produção. | Sim |
| `contains` | Um arquivo contém o `text` dado. | Sim |
| `manual` | Uma `rubric` que exige julgamento humano — o runner **nunca finge avaliar** o que não consegue medir; casos `manual` são listados à parte para revisão humana, não contados como pass automático. | Não |

Saída:

```json
{ "agent": "rush-spec", "total": 12, "passed": 10, "failed": 1, "manual": 1,
  "cases": [{ "id": "spec-budget-respected", "status": "pass" }] }
```

Códigos de saída: `0` todo grader determinístico passou, `1` pelo menos um falhou, `2` erro de uso
ou falha interna.

## Como rodar

```bash
.rush/scripts/eval.sh rush-spec --json          # todos os casos de um agente
.rush/scripts/eval.sh --all --json              # todos os agentes
.rush/scripts/eval.sh --case spec-budget-respected --json   # um caso específico, buscado
                                                              # em todos os agentes se --agent
                                                              # não for dado
```

## Estado atual: runner + casos iniciais

`.rush/scripts/eval.sh` está implementado, e o kit já vem com uma suíte em `.rush/evals/` —
25 casos cobrindo os agentes de maior risco e o próprio kit:

| Agente | Casos | O que guardam |
|---|---|---|
| `rush-spec` | 4 | orçamento desligado por padrão mas aplicado quando o projeto pede, vazamento de processo na spec (fronteira O QUE/COMO), critério de aceite sem check, spec bloqueada por integration map quebrado |
| `rush-features` | 4 | integration map válido, consumo sem provedor, jornada sem teste, provedor duplicado |
| `rush-implement` | 4 | não promove a si mesmo, edição de teste bloqueada, não afrouxa teste para passar, para no orçamento de tentativas |
| `rush-analyze` | 3 | violação de MUST da constitution vira NO-GO, scripts verdes não bastam para GO, critério não coberto é blocker |
| `kit` | 5 | construto que quebra bash 3.2, referência de skill a script/template inexistente, `branch_pattern` aplicado de fato (e desligável), cursor de feature seguindo a atenção e não a criação, atualização que nunca toca em arquivo do projeto |
| `rush` | 2 | path sensível força L mesmo em diff de uma linha, correção trivial fica em S |
| `rush-quick` | 1 | escala em vez de empurrar quando aparece migration/contrato/dependência/path sensível |
| `rush-pr` | 1 | feature incompleta nunca é apresentada como pronta, por mais que os commits pareçam terminados |
| `rush-context-save` | 1 | caminho vem do script, store vazio é resposta válida, descartes ficam registrados |

Rodando hoje, no kit limpo:

```
total=25 passed=17 failed=0 manual=8
```

(Esses números envelhecem — `.rush/scripts/eval.sh --all --json` devolve os atuais.)

Os casos `manual` são exatamente os que exigem julgamento (não há grader determinístico honesto
para "o agente parou quando devia") — o runner os reporta como `manual` em vez de fingir
avaliá-los. Um caso pode misturar as duas naturezas: `quick-escalates-on-migration` fixa o sinal
determinístico do `triage.sh` **e** carrega a rubrica do que só uma execução real mostra; os
graders determinísticos dele rodam e reportam individualmente, mesmo com o caso classificado como
`manual`. Fixtures compartilhadas ficam em `.rush/evals/fixtures/`. A suíte cresce pelo mecanismo
abaixo.

## Como `/rush-retro` alimenta os evals

`/rush-retro` (invocação explícita, depois de uma feature fechada, ou como varredura periódica do
projeto) é o mecanismo que preenche `.rush/evals/`. Seu processo, para cada falha real encontrada
(um bug que foi a produção, um check que pegou tarde, uma suposição não-bloqueante que se provou
errada):

1. **Classifica a falha**: pega cedo por um check existente (nenhuma ação), pega tarde por um check
   existente (mover o check para mais cedo, não criar regra nova), ou não foi pega até um humano
   achar (esta é a categoria que precisa de mecanismo novo).
2. Para toda falha "não pega até um humano achar", a preferência de correção é, nesta ordem:
   - **Novo caso de eval** sob `.rush/evals/<agente>/cases/`, no formato dos casos existentes no
     diretório (ou o formato mínimo que `eval.sh` consegue avaliar, se o diretório ainda está
     vazio: um id, o cenário de entrada, e o que conta como pass — determinístico sempre que
     possível, `manual` só quando o julgamento é genuinamente necessário).
   - Fitness function nova/ajustada, se a falha é uma propriedade estrutural checável no código.
   - Regra registrada em `CLAUDE.md`, só se nenhum check determinístico for viável.
   - Mudança de constitution proposta (nunca aplicada sem confirmação explícita do diff), só se a
     falha reflete um princípio que deveria bloquear *toda* feature futura, não só esta.
   Toda adição é registrada em `.rush/memory/lessons.md`: a falha, o mecanismo, a data.
3. **Sanity-check do caso novo**: depois de escrever, `/rush-retro` roda
   `.rush/scripts/eval.sh <agente> --case <id> --json` para confirmar que o runner de fato parseia
   e classifica o caso (determinístico vs. `manual`) em vez de falhar silenciosamente ao carregar.

`/rush-retro` também audita retiradas: um item de checklist ou fitness function que nunca disparou
durante o período revisado é candidato a remoção, com a evidência (não um palpite) de que nunca
pegou nada — isso é o que mantém a suíte enxuta em vez de só crescer.

## Ver também

- [`definition-of-done.md`](./definition-of-done.md#o-mesmo-contrato-serve-dois-papéis-ao-mesmo-tempo) —
  como o vocabulário `run`/`expect` de `done-contract.md` é o mesmo usado pelo grader `script`.
- [`agents.md`](./agents.md) — `/rush-retro` em detalhe, incluindo suas garantias sobre mudanças de
  constitution.
- [`harness.md`](./harness.md#memória-do-projeto-questionsmd-debtmd-lessonsmd) — `lessons.md`, onde
  toda adição de eval é registrada com a falha que a motivou.
