# Integração entre features: o mapa que impede o isolamento

O problema que esta camada resolve é específico: um kit spec-driven, feature por feature, tende a
produzir "features que funcionam sozinhas mas não se encaixam" — cada spec é internamente
consistente, cada implementação passa nos próprios testes, e o produto inteiro ainda quebra na
junção. `specs/integration-map.md` é a resposta estrutural a isso, não documentação depois do fato.

## O grafo: `specs/integration-map.md`

Produzido/atualizado por `/rush-features` (na criação, a partir das journeys do PRD) e por
`/rush-spec`/`/rush-quick` (quando uma feature individual toca uma interface), num bloco `json`
dentro do markdown:

```json
{
  "features": [
    { "id": "003-checkout/001-auth", "title": "Autenticação",
      "provides": [{ "kind": "endpoint", "name": "POST /auth/login", "contract": "specs/003-checkout/001-auth/contracts/login.yaml#/paths" }],
      "consumes": [], "depends_on": [] },
    { "id": "003-checkout/004-cart", "title": "Carrinho",
      "provides": [{ "kind": "endpoint", "name": "POST /cart/items" }],
      "consumes": [{ "kind": "endpoint", "name": "POST /auth/login", "from": "003-checkout/001-auth" }],
      "depends_on": ["003-checkout/001-auth"] }
  ],
  "shared_contracts": [
    { "name": "POST /auth/login", "owner": "003-checkout/001-auth", "path": "specs/shared-contracts/auth.md" }
  ],
  "journeys": [
    { "id": "guest-checkout", "description": "Cliente compra sem cadastro prévio",
      "features": ["003-checkout/001-auth", "003-checkout/004-cart"], "test": "tests/journeys/guest-checkout.spec.ts" }
  ]
}
```

Todo `id` de feature no mapa é `<spec-id>/<feature-id>`, nunca um id de feature sozinho: features
são aninhadas dentro do seu spec e cada spec numera as suas a partir de `001`, então `001-auth`
sozinho é ambíguo no instante em que existe mais de um spec. Isso vale para `id`, para o `from` de
um `consumes`, para `depends_on`, para `shared_contracts[].owner` e para os `features` de uma
journey.

`kind` é um de `endpoint | event | component | data | module`. `from`, numa entrada `consumes`,
sempre nomeia a feature que deveria prover aquilo. `depends_on` lista as features que precisam
existir antes desta poder ser implementada.

## O que `validate-integration-map.sh` rejeita, e por quê

`.rush/scripts/validate-integration-map.sh --json` lê esse bloco e sai `1` se encontrar qualquer
uma destas violações — todas tratadas como **erro**, nunca aviso:

| Regra | O que detecta | Por que é um erro, não um aviso |
|---|---|---|
| `consume_without_provider` | Uma entrada `consumes` cujo `from` não tem um `provides` correspondente de mesmo `kind`+`name` | Uma feature que depende de algo que ninguém se comprometeu a construir é uma promessa vazia — o consumidor será implementado contra uma interface que pode nunca existir com aquela forma. |
| `duplicate_provider` | Duas features declarando `provides` do mesmo `kind`+`name` | Duas implementações divergentes da "mesma" interface é exatamente como um consumidor acaba falando com a versão errada — e ninguém percebe até produção. |
| `dependency_cycle` | Um ciclo em `depends_on` | Um ciclo torna a ordem topológica indefinida — não há sequência segura de implementação, e `/rush-implement` não tem como saber o que construir primeiro. |
| `journey_missing_feature` | Uma journey referencia um `id` de feature que não existe em `features[]` | A jornada documenta um caminho que passa por algo que não está no mapa — ou o mapa está incompleto, ou a jornada foi mal transcrita. |
| `journey_without_test` | Uma journey sem `test` declarado | Uma afirmação de comportamento cross-feature sem nada que a prove é exatamente o tipo de coisa que "funciona isolado, quebra junto" descreve — sem teste, ninguém saberia se ela parou de valer. |
| `unknown_feature_ref` | Qualquer `id` referenciado (`from`, `depends_on`, journey) que não existe em `features[]` | Um ponteiro solto no grafo é indistinguível de um erro de digitação até alguém tentar segui-lo. |

A saída de sucesso inclui `order`: a ordenação topológica de `depends_on`, a sequência segura de
implementação. `/rush-features` e `/rush-new` leem esse campo diretamente em vez de tentar deduzir a
ordem por inspeção — é assim que o kit garante que uma feature nunca é implementada antes de algo
de que ela depende.

## Contratos compartilhados: um dono declarado, nunca implícito

Quando uma interface é consumida por duas ou mais features, ela vira um **contrato compartilhado**
sob `specs/shared-contracts/`, com exatamente uma feature dona registrada em
`shared_contracts[].owner` no mapa. As outras features consomem `from` o dono, nunca redefinem a
própria cópia.

Duas regras aplicam isso em pontos diferentes do processo:

- `/rush-features`, ao identificar uma interface consumida por 2+ features, é instruído a nunca
  deixar a propriedade implícita — um contrato compartilhado sem dono declarado é exatamente o
  risco que `duplicate_provider` existe para prevenir.
- `/rush-spec`, ao gerar os arquivos de contrato de uma feature durante seu próprio processo (ou
  `/rush-contracts`, ao re-sincronizar um contrato já congelado), nunca duplica uma interface que
  outra feature (ou `shared-contracts/`) já define — referencia o caminho existente e para. Se o
  mapa ainda não declara dono para uma interface que está prestes a colocar em
  `shared-contracts/`, isso é reportado como lacuna do mapa, não decidido ali.
- `.rush/scripts/validate-contracts.sh` reforça isso mecanicamente: todo contrato sob
  `specs/shared-contracts/` precisa ter, no integration map (`shared_contracts[]`, casado por
  path) ou inline no próprio arquivo (`owner`/`x-owner`), um dono que nomeia uma feature que
  realmente existe. Sem isso, o contrato é inválido.

## Testes de journey

Uma journey no mapa não é narrativa — é um contrato de que aquele caminho cross-feature continua
funcionando. Cada journey nomeia sua sequência ordenada de `features` e um `test`: um comando, o
caminho de um arquivo de teste, ou, na ausência de um check automatizável ainda, um gate humano
nomeado explicitamente.

Duas camadas verificam journeys, com responsabilidades diferentes:

- **Estrutural** (`validate-integration-map.sh`): a journey existe, referencia features reais, e
  tem um `test` não vazio. Isso não verifica se o teste realmente prova o comportamento — só que
  ele foi declarado.
- **De julgamento** (`/rush-analyze`, Process passo 3): para toda journey que cruza a feature em
  análise, confirma que o *comportamento*, não só a aresta do grafo, ainda se sustenta — por
  exemplo, se um contrato mudou de forma, `/rush-analyze` checa se o `consumes` declarado por cada
  feature na journey ainda é satisfeito por aquela nova forma.

Isso é o que fecha o nível 3 da Definition of Done — veja
[`definition-of-done.md`](./definition-of-done.md#nível-3--por-jornada-os-testes-de-journey).

## Ver também

- [`flow.md`](./flow.md) — onde `/rush-features` se encaixa no fluxo L completo.
- [`definition-of-done.md`](./definition-of-done.md) — os quatro níveis de "pronto", incluindo o
  de journey.
- [`agents.md`](./agents.md) — `/rush-features`, `/rush-spec`, `/rush-contracts` e `/rush-analyze`
  em detalhe.
