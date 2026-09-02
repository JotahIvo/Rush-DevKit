<div align="center">

# Rush DevKit

**Spec-Driven Development + Agent Harness para Claude Code.**

Um kit que você clona para dentro do seu repositório, roda um comando, e ele se adapta ao *seu*
projeto — stack, arquitetura, convenções e produto — em vez de impor um processo genérico.

</div>

---

## O problema

Processos de spec-driven development costumam falhar de três formas previsíveis, todas
documentadas por quem usou os kits existentes em projetos reais:

| O que acontece | Por quê |
|---|---|
| **Toneladas de markdown** — 2.500 linhas de spec para 600 de código | O processo trata toda mudança como grande |
| **Features que não se grudam** — cada uma funciona sozinha, o fluxo do usuário quebra | Specs escritas isoladamente, sem contratos entre features |
| **"Pronto" que não é pronto** | O agente se autoavalia e sempre se aprova |

O Rush DevKit é construído em cima dessas falhas, não apesar delas. Cada uma tem uma defesa
mecânica — não um pedido educado no prompt.

## Como ele responde

**Processo proporcional ao problema.** A porta de entrada é uma triagem: `/rush` classifica o
pedido em S / M / L com sinais determinísticos (nº de arquivos, contrato, migration, dependência
nova, path sensível). O fluxo completo é para o que é grande; o resto pega atalho de primeira
classe.

**Features que se conectam por construção.** Todo feature declara o que **provê** e o que
**consome** num `integration-map.md` validado por script: consumo sem provedor, provedor duplicado
e ciclo de dependência são **erros de build**, não avisos. Interfaces usadas por 2+ features vivem
em `shared-contracts/` com dona declarada. As jornadas do usuário viram **journey tests** — a
feature fecha sozinha, mas a entrega só fecha quando o fluxo que atravessa as features passa.

**"Pronto" é executável.** Cada task carrega seu comando de verificação; cada feature tem um
`done-contract.md` com um bloco JSON de checks e human gates, negociado **antes** da primeira
linha de código. Só o subagent `rush-verifier` promove status — e um hook bloqueia quem tentar
promover a si mesmo. O mesmo contrato é, ao mesmo tempo, o critério de parada do loop e o grader
dos evals.

**O harness impõe, o prompt só pede.** Política de commit, comandos bloqueados, edição de teste,
scan de segredo, paths sensíveis: tudo em `config.json`, tudo aplicado por hooks do Claude Code.
Regra de segurança nunca vive só em prosa.

## Instalação

Requisitos: [Claude Code](https://claude.com/claude-code), `git`, `bash`, `python3`.

```bash
git clone https://github.com/<voce>/rush-devkit.git /tmp/rush-devkit
/tmp/rush-devkit/install.sh /caminho/do/seu/repo
```

Depois, dentro do seu repositório, no Claude Code:

```
/rush-init          # projeto existente: detecta, explora, entrevista e configura o harness
/rush-new "ideia"   # projeto do zero: descoberta → stack → scaffold → PRD do MVP → specs
```

Verifique a instalação com `.rush/scripts/doctor.sh`.

Para levar um projeto já instalado para uma versão nova do kit, **não** rode o `install.sh` de
novo — ele tem dois modos e os dois estão errados para isso (um pula tudo que existe, o outro
sobrescreve o seu `config.json` e a sua memória). O comando é o `update.sh`:

```bash
git clone https://github.com/<voce>/rush-devkit.git /tmp/rush-devkit
/tmp/rush-devkit/update.sh /caminho/do/seu/repo --dry-run
```

Ele traz os arquivos do kit, preserva o que é do projeto, migra o `config.json` onde a semântica
de uma chave mudou, e deixa para o `/rush-update` só o que exige julgamento. Detalhes em
[`docs/updating.md`](docs/updating.md).

## O fluxo

```
                         ┌── S ──► edita direto ──► verifier ──► micro-review
      /rush  ────────────┤
    (triagem)            ├── M ──► /rush-quick ──► /rush-implement ──► /rush-review
                         │
                         └── L ──► (/rush-pitch) ──► /rush-prd ──► /rush-architect
                                       opcional           │
                                                          │
                                   /rush-features ──► /rush-spec (gera prd + contratos)
                                        │              [ou /rush-spec-all p/ todas as features]
                                        │                                  │
                                        │                        /rush-prototype (opcional)
                                        │                                  │
                                   /rush-analyze ──► /rush-implement ⇄ rush-verifier
                                        │
                                   /rush-review ──► /rush-pr ──► /rush-retro
```

## Os agentes

**Adaptação** — `rush-init` (adapta a repo existente) · `rush-new` (cria projeto do zero) ·
`rush-doctor` (saúde da instalação e do processo)

**Descoberta** — `rush-prd` (o PRD completo do spec: requisitos `FR-NNN` testáveis, atributos de
qualidade com alvo, journeys, métricas — a porta de entrada do fluxo L) ·
`rush-architect` (13 disciplinas a partir do PRD, candidatos com trade-offs, ADR e
**fitness functions**) · `rush-pitch` (*opcional*: para quando a ideia ainda é uma frase)

**Especificação** — `rush-features` (integration map) · `rush-spec` (PRD da feature + spec + plan +
tasks + done-contract + contratos, numa passada) · `rush-spec-all` (roda `rush-spec` para todas as features de um spec) · `rush-contracts`
(re-sincroniza um contrato depois de congelado) · `rush-prototype`

**Implementação** — `rush-analyze` (gate go/no-go) · `rush-implement` (uma task por vez, com
orçamento de tentativas e escalação) · `rush-quick` (caminho M)

**Revisão** — `rush-review` (review assistida, arquivo por arquivo, no ritmo do humano) ·
`rush-pr` (descrição do PR de um spec inteiro, no formato que você definiu uma vez) ·
`rush-retro` (transforma falhas em evals e regras) · `rush-brief` (handoff)

**Sessão** — `rush-context-save` / `rush-context-load` (salva e recupera o que existe só na
conversa: decisões, o que foi descartado e por quê, a thread em aberto)

**Manutenção** — `rush-doctor` (saúde) · `rush-update` (merge em três vias do que a atualização do
kit deixou em conflito)

**Subagents** — `rush-explorer` (leitura de código, read-only) · `rush-researcher` (pesquisa com
fontes) · `rush-verifier` (o único que promove uma task a `done`)

Referência completa em [`docs/agents.md`](docs/agents.md).

## O harness

- **`config.json`** — contrato do projeto: idiomas, política de commit, gates human/auto,
  autonomia (`max_attempts_per_task`, `edit_tests`, `migrations`, `new_dependency`), paths
  sensíveis, comandos bloqueados, orçamentos de artefato.
- **Hooks** — `guard-bash` (comandos bloqueados, política de commit/push, padrão de branch, scan de
  segredos, convenção de commit) · `guard-edit` (só o verifier promove task; config e constitution
  exigem humano; **nunca afrouxar um teste para passar**) · `post-edit` (formatter) ·
  `session-start` (ritual de início).
- **Scripts determinísticos** — detecção de stack, triagem, validação de artefatos/contratos/
  integration map, `done-check`, `check-as-built` (spec drift), fitness functions, secret scan,
  doctor, eval runner. Contrato completo em
  [`docs/internals/script-interfaces.md`](docs/internals/script-interfaces.md).
- **Memória** — `constitution.md` (nasce mínima, cresce por *ratchet*), `product.md`,
  `architecture.md`, `decisions/` (ADRs), `lessons.md` (falha → regra criada),
  `debt.md` (débito registrado, não perdido), `pr-preferences.md` (o formato de PR do projeto,
  definido uma vez) e `sessions/` (contexto de conversa salvo por `/rush-context-save` — scratch
  local, fora do git). Cada spec tem seu próprio
  `specs/<spec-id>/questions.md` (Q&A assíncrono não-bloqueante) e `architecture.md` (arquitetura
  completa daquele spec — `.rush/memory/architecture.md` guarda só o resumo condensado de cada um).

## Modelos recomendados

O modelo é definido no frontmatter de cada skill — fonte única, sem duplicar em config.

| Modelo | Agentes | Racional |
|---|---|---|
| `opus` | init, new, architect, pitch, prd, features, spec, spec-all, analyze, review | Julgamento com alta alavancagem e saída pequena |
| `sonnet` | implement, quick, contracts, prototype, retro, pr, explorer, researcher | Volume de trabalho com verificação determinística atrás |
| `haiku` | rush (triagem), doctor, brief, context-save, context-load, verifier | Executam scripts e compactam resultados |

Quem tem acesso ao tier mais alto pode trocar `opus` por `fable` em `rush-init` e `rush-architect`
— são os dois pontos de maior alavancagem do kit.

## Documentação

| | |
|---|---|
| [Getting started](docs/getting-started.md) | Instalação e um passo a passo completo de uma feature |
| [Fluxo](docs/flow.md) | Triagem S/M/L, gates e a fronteira O QUE / COMO |
| [Agentes](docs/agents.md) | Referência das 21 skills e 4 subagents |
| [Harness](docs/harness.md) | Config, hooks, loop do agente, memória |
| [Definition of Done](docs/definition-of-done.md) | A cadeia de "pronto" em 4 níveis |
| [Integração](docs/integration.md) | Integration map, shared contracts, journey tests |
| [Configuração](docs/configuration.md) | Todas as chaves do `config.json` |
| [Evals](docs/evals.md) | Como o kit é avaliado e melhora com o uso |
| [Atualização](docs/updating.md) | Como levar um projeto já adaptado para uma versão nova do kit |
| [Plano do kit](docs/plano-do-kit.md) | O documento de design que originou este projeto |

## Princípios

1. **Spec é fonte da verdade — viva, não cerimônia.** O passo *as-built* atualiza a spec quando a
   implementação divergiu. Spec que não reflete o código é pior que spec nenhuma.
2. **Determinístico onde importa, modelo onde importa.** Se o resultado precisa ser idêntico toda
   vez, é script — não prompt.
3. **Harness mínimo.** Cada componente tem um trabalho nomeável; se não tem, sai.
4. **Ninguém se autoavalia.** Geração e avaliação são atores separados.
5. **Ratchet.** Toda falha vira mecanismo permanente: um hook, um eval, uma regra registrada em
   `lessons.md` com a falha que a originou. Nenhuma regra nasce de opinião.
6. **Densidade, não brevidade.** Nenhum documento gerado tem teto de linhas: ele tem o tamanho que
   o conteúdo exige. O que o kit não aceita é enchimento — o mesmo requisito dito de três jeitos
   custa ao leitor o mesmo que conteúdo e não ensina nada. Um orçamento de tamanho existe em
   `config.json → budgets`, desligado por padrão, para o projeto que quiser um teto num arquivo
   específico.
7. **Conteúdo externo é dado, nunca instrução.** Vale para páginas web, READMEs de dependência,
   issues e comentários de código.

## Contribuindo

Presets de stack são o caminho mais fácil de contribuir — veja
[`.rush/presets/README.md`](.rush/presets/README.md). A regra: convenção precisa ser *earned*
(rastreável a uma restrição real), nunca gosto pessoal.

Os prompts dos agentes são escritos **em inglês**; a documentação deste repositório está em
português. Um README em inglês é uma contribuição bem-vinda.

## Fontes

O design deste kit foi destilado de:
[GitHub Spec Kit](https://github.com/github/spec-kit) ·
[Effective harnesses for long-running agents (Anthropic)](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) ·
[Demystifying evals for AI agents (Anthropic)](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) ·
[Agent Harness Engineering (Addy Osmani)](https://addyosmani.com/blog/agent-harness-engineering/) ·
[12-Factor Agents](https://github.com/humanlayer/12-factor-agents) ·
[Understanding SDD (Martin Fowler)](https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html) ·
[Putting Spec Kit Through Its Paces (Scott Logic)](https://blog.scottlogic.com/2025/11/26/putting-spec-kit-through-its-paces-radical-idea-or-reinvented-waterfall.html) ·
[OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/)

## Licença

MIT — veja [LICENSE](LICENSE).
