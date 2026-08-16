# Definition of Done: os quatro níveis

"Pronto" no Rush DevKit não é uma palavra — é uma cadeia de quatro artefatos verificáveis, cada um
mais amplo que o anterior, que se retroalimentam. Nenhum deles é opinião de um agente sobre o
próprio trabalho.

## Nível 1 — por task: `verify:`

Cada task em `tasks.md` (gerado por `/rush-spec` ou `/rush-quick`) carrega sua própria linha
`verify:` — um comando real e já funcional que prova a conclusão sem julgamento humano:

```markdown
### T1 — implementar handler GET /health
- status: `pending`
- verify: `npm test -- health`
```

Uma task sem `verify:` **não está pronta para ser trabalhada**; a skill que a escreveu é instruída
a escrever o check antes do código, não depois. Quem executa o `verify:` e decide pass/fail é
sempre o subagent `rush-verifier` — nunca o agente que implementou (veja
[`harness.md`](./harness.md#o-loop-do-agente-rush-implement)). O único ator que pode então mudar o
status para `done` é o próprio `rush-verifier`:

```bash
.rush/scripts/task-status.sh <feature-id> --set <task-id> done --by rush-verifier
```

Qualquer outro `--by` é rejeitado com exit 1 por design — não é um bug a contornar.

## Nível 2 — por feature: `done-contract.md`

Cada feature carrega um `done-contract.md`, negociado com o usuário **antes de qualquer código ser
escrito**, com um bloco `json` machine-readable:

```json
{
  "checks": [
    { "name": "acceptance tests", "run": "npm test -- specs/007", "expect": "exit 0" },
    { "name": "contracts valid", "run": ".rush/scripts/validate-contracts.sh 007", "expect": "exit 0" },
    { "name": "fitness functions", "run": ".rush/scripts/fitness.sh 007", "expect": "exit 0" },
    { "name": "no spec drift", "run": ".rush/scripts/check-as-built.sh 007", "expect": "exit 0" }
  ],
  "human_gates": ["assisted review completed (/rush-review)"]
}
```

`expect` aceita quatro formas: `exit 0`, `exit N`, `contains: <texto>`, `not_contains: <texto>`.
Cada `run` deve ser um comando que **já funciona** de verdade — `done-check.sh` executa
literalmente, nunca reimplementa o que o comando faz.

`/rush-spec` exige que **todo critério de aceite em `spec.md` mapeie para exatamente um check ou um
human gate** aqui; um critério que não mapeia para nenhum dos dois é um critério que nada vai
aplicar — a skill é instruída a sinalizar essa lacuna em vez de deixá-la passar.

Quem executa esse contrato é `.rush/scripts/done-check.sh <feature-id> [--json] [--only <nome>]`:

```json
{ "ok": false, "feature": "007-checkout",
  "checks": [{ "name": "acceptance tests", "status": "fail", "exit_code": 1,
               "duration_ms": 8421, "output_tail": "...últimas 40 linhas..." }],
  "human_gates": [{ "text": "review assistida concluída", "confirmed": false }],
  "summary": { "passed": 2, "failed": 1, "gates_pending": 1 } }
```

**Sucesso é silencioso, falha é verbosa**: um check que passa não traz `output_tail`. Timeout por
check é `verification.check_timeout_seconds` (padrão 600s). Um `human_gates` só aparece como
confirmado se o texto exato do gate estiver registrado em
`.rush/state.json → gates_confirmed.<feature-id>` — nenhum agente escreve isso por si mesmo; é o
humano, tipicamente ao final de `/rush-review`, que instrui essa confirmação.

## Nível 3 — por jornada: os testes de journey

Uma feature pode passar em todos os seus próprios checks e ainda quebrar o produto se a jornada que
a atravessa parar de funcionar de ponta a ponta. `specs/integration-map.md` declara, para cada
journey, a sequência de features que ela cruza e **o teste que a prova**:

```json
"journeys": [
  { "name": "guest checkout", "features": ["001-auth", "004-cart"],
    "test": "tests/journeys/guest-checkout.spec.ts" }
]
```

`.rush/scripts/validate-integration-map.sh` rejeita qualquer journey sem `test` declarado
(`journey_without_test`) — uma journey sem teste é uma afirmação que ninguém verifica, e o
validador trata isso como erro, não aviso. `/rush-analyze` soma a esse check estrutural uma camada
de julgamento: para cada journey que cruza a feature em análise, ele confirma que o *comportamento*,
não só a aresta do grafo, ainda se sustenta. Veja [`integration.md`](./integration.md) para o mapa
completo.

## Nível 4 — permanente: CI

O kit não gera nem gerencia CI para um projeto já existente — `detect-stack.sh` apenas **detecta**
arquivos de CI existentes (`ci` no seu JSON, ex. `[".github/workflows/ci.yml"]`) como sinal
informativo; `rush-init` não os cria. Em projeto novo, `/rush-new` é explícito em escafoldar "the
test runner, linter/formatter and a minimal CI" como parte do passo de scaffold — ali sim o kit
gera algo mínimo, herdado do preset escolhido. Em ambos os casos, o efeito prático desejado é o
mesmo: os checks dos níveis 1–3 (test/lint/build/typecheck configurados em `commands.*`) devem
rodar de novo em CI, fora de qualquer sessão de agente, para que "pronto" não dependa só da máquina
de quem implementou.

## O mesmo contrato serve dois papéis ao mesmo tempo

O bloco `json` de `done-contract.md` não é reescrito para dois consumidores diferentes — é **o
mesmo artefato lido por dois motores**:

1. **Critério de parada do loop do implementador.** `rush-verifier`, ao terminar todas as tasks,
   roda `done-check.sh <feature-id> --json` como parte do fechamento da feature; enquanto algum
   check falha, a feature não está pronta, e é isso que decide se `/rush-implement` continua ou
   escala.
2. **Grader de eval.** `.rush/scripts/eval.sh` usa exatamente o mesmo vocabulário de `expect`
   ("exit 0", "exit N", "contains: <texto>", "not_contains: <texto>") no grader do tipo `script`
   dentro de um caso de eval:

   ```json
   { "type": "script", "run": ".rush/scripts/done-check.sh 007 --json", "expect": "exit 0" }
   ```

   Isso significa que um `done-contract.md` real de uma feature já fechada pode virar, sem
   tradução, o grader de um caso de eval que prova que aquele tipo de falha não vai mais passar
   despercebido — é exatamente o mecanismo que `/rush-retro` usa (veja
   [`evals.md`](./evals.md#como-rush-retro-alimenta-os-evals)).

## Ver também

- [`integration.md`](./integration.md) — o nível 3 em detalhe: por que cada regra do validador do
  integration map existe.
- [`harness.md`](./harness.md) — a regra "só o verifier promove" e como ela é aplicada em três
  camadas.
- [`evals.md`](./evals.md) — como o mesmo vocabulário de checks vira grader permanente.
