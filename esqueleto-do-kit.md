# Rush DevKit — Esqueleto do Kit (v0.6)

> Plano-esqueleto do kit de SDD + Harness. Docs em pt-BR; prompts dos agentes em inglês. Alvo: Claude Code first (skills, subagents, hooks, CLAUDE.md). Distribuição: git clone (template copiável).
>
> **v0.2**: incorporadas críticas reais ao SDD colhidas em campo (bloat de markdown, waterfall reinventado, spec drift, checklist theater) e práticas de harness engineering (ratchet pattern, generator/evaluator split, verificação silenciosa, orçamento de artefatos). Agente de arquitetura com especialidades completas.
>
> **v0.3**: Definition of Done executável (fonte da verdade de "pronto" que a IA consegue verificar); agent loop engineering explícito no implementer (critérios de parada, escalação, orçamento de tentativas); segurança do próprio kit (prompt injection via conteúdo não-confiável); disciplina de Integração de IA no arquiteto (condicional); princípios do 12-Factor Agents aplicados ao design dos agentes.
>
> **v0.4**: adicionados `questions.md` (Q&A assíncrono), `/rush-brief` (handoff entre pessoas/sessões), worktrees paralelos para features independentes, débito técnico estruturado (`debt.md`), `rush-doctor` (diagnóstico da instalação) e presets de stack contribuíveis no `rush-init`.
>
> **v0.5**: corrige dois buracos apontados em revisão crítica: (1) **camada de integração entre features** — provides/consumes, integration map, journey tests e checagem cross-feature no analyze (specs isoladas geram features que funcionam sozinhas mas não se grudam); (2) **fronteira O QUE / COMO** — regra explícita de qual artefato pode dizer o quê, e a decisão de que processo (rodar testes, commitar) NUNCA vive em spec, vive no harness. Detalhada a Fase 0 (fluxo do `rush-init`, perguntas da entrevista, schema do config.json).
>
> **v0.6**: modo **greenfield** (`rush-new`) — criar um projeto do zero a partir da ideia do produto: descoberta → escolha de stack com trade-offs → scaffold determinístico validado → fundação do harness → PRD do MVP → todas as specs do MVP prontas para implementar, na ordem do grafo.

---

## 1. Visão

Um kit que qualquer pessoa clona para dentro do repositório e roda um comando de inicialização. O kit **se adapta ao projeto** (stack, arquitetura, convenções, produto e preferências) em vez de impor processo genérico. A partir daí, oferece SDD com um harness que garante segurança e rastreabilidade — e que o humano **entenda tudo que foi feito**, em vez de só aceitar código.

### Princípios de design

1. **Spec é a fonte da verdade — mas viva, não cerimônia.** O kit é *spec-anchored* (na taxonomia do Martin Fowler): a spec acompanha o código pelo ciclo de vida da feature e é atualizada quando a implementação diverge ("as-built"). Spec que não reflete o código é pior que não ter spec.
2. **Determinístico onde importa, modelo onde importa.** Scripts fazem o reproduzível (criar pastas, numerar, validar estrutura, gates); o modelo faz o que exige julgamento. Nunca pedir ao LLM o que um script de 10 linhas faz melhor.
3. **Harness mínimo.** "What can I stop doing?" (Anthropic): estrutura só onde paga — UX, custo, segurança, reprodutibilidade. Cada componente do harness tem um trabalho nomeável; se não tem, sai.
4. **Processo proporcional ao problema.** A maior crítica real ao spec-kit é tratar toda mudança como grande. Aqui, **triagem é a porta de entrada**: o fluxo completo é para o que é grande; o resto pega atalho.
5. **Ninguém se autoavalia.** Split geração/avaliação: quem implementa nunca declara "pronto" — agentes se autoavaliam com viés positivo sistemático. Só o `verifier` promove status.
6. **Ratchet pattern.** Toda falha vira mecanismo permanente: uma regra no CLAUDE.md, um hook, um caso de eval. Nenhuma regra existe sem uma falha ou restrição que a justifique.
7. **Orçamento de artefatos.** Casos reais reportam 2.500+ linhas de markdown para uma feature — 4x o tamanho do código gerado. Todo artefato do kit tem teto de tamanho. Rever markdown é mais cansativo que rever código; o kit não pode transferir o custo do código para a prosa.
8. **"Pronto" é executável, não prosa.** A definição de done de toda task/feature precisa ser algo que uma máquina consegue verificar (comando + resultado esperado). Se o critério só existe em texto, o agente vai se convencer de que atendeu. Ver seção "Definition of Done executável".
9. **Agentes pequenos e focados (12-Factor Agents).** Cada agente faz uma coisa; contexto é propriedade nossa (curado por artefatos, não acumulado); erros voltam compactados ao loop; contatar o humano é uma ferramenta explícita do agente, não um acaso; controle de fluxo crítico vive em script/hook, não na vontade do modelo.

---

## 2. Modos de falha conhecidos do SDD — e a defesa do kit

Esta seção existe porque a v0.1 assumia que o fluxo SDD clássico funciona. A evidência de campo diz que ele falha de formas previsíveis:

| Modo de falha (documentado em campo) | Defesa do Rush DevKit |
|---|---|
| **Bloat de markdown** — "ilusão de trabalho", docs 4x maiores que o código | Orçamento por artefato (pitch ≤ 1 pág; spec ≤ 150 linhas; plan ≤ 100). Script de validação rejeita excesso. Templates pedem densidade, não completude |
| **Waterfall reinventado** — sequência rígida mata a iteração | Triagem na entrada (S/M/L); loop interno curto (task → verify → commit); spec é atualizável durante a implementação via processo explícito, não congelada |
| **10x mais lento em tarefas simples** | `/rush-quick` é caminho de primeira classe, não exceção. Fluxo completo só para o que a triagem classifica como L |
| **Spec drift** — spec e código divergem e ninguém percebe | Passo "as-built" obrigatório no fim da implementação: diff spec ↔ código; a review checa a sincronia; spec desatualizada bloqueia o fechamento da feature |
| **Checklist theater** — checklists que o agente preenche sem valor | Toda regra/checklist item precisa rastrear para uma falha real (ratchet). Retro aposenta itens que nunca pegam nada |
| **Agente ignora a spec** | Verificação executável > prosa: critérios de aceite viram testes; fitness functions da arquitetura viram checks do verifier; hooks bloqueiam, prompts apenas pedem |
| **Auto-relato de "pronto" sem estar** | Generator/evaluator split + "contrato de pronto" negociado antes de codar (done-conditions escritas antes da primeira linha) |

---

## 3. Estrutura de pastas

```
seu-repo/
├── CLAUDE.md                  # curto (~60 linhas): regras "earned", aponta para .rush/
├── .claude/
│   ├── skills/                # comandos /rush-*
│   ├── agents/                # subagents (explorer, researcher, verifier)
│   └── hooks/                 # gates automáticos
├── .rush/
│   ├── config.json            # preferências e permissões (contrato do harness)
│   ├── memory/
│   │   ├── constitution.md    # princípios inegociáveis (curto, earned)
│   │   ├── product.md         # contexto de produto
│   │   ├── architecture.md    # mapa da arquitetura real
│   │   ├── decisions/         # ADRs leves
│   │   ├── lessons.md         # ratchet log: falha → regra criada
│   │   ├── questions.md       # Q&A assíncrono: dúvidas não-bloqueantes p/ o humano
│   │   └── debt.md            # débito técnico estruturado (atalhos conscientes)
│   ├── presets/               # presets de stack (contribuíveis pela comunidade)
│   ├── templates/             # com orçamento de tamanho embutido
│   ├── scripts/               # determinísticos
│   └── evals/                 # casos + graders por agente
└── specs/
    ├── integration-map.md     # o "cimento": provides/consumes de cada feature + journeys
    ├── shared-contracts/      # contratos compartilhados entre features (fonte única)
    └── NNN-nome-da-feature/
        ├── pitch.md · prd.md · spec.md · plan.md · tasks.md
        ├── contracts/         # contratos exclusivos desta feature
        ├── done-contract.md   # condições de pronto, escritas ANTES de codar
        └── progress.md        # diário de sessões
```

---

## 4. O fluxo — com triagem na entrada

```
                         ┌── S (trivial) ──► edita direto + verifier + micro-review
usuário ──► /rush ───────┤
        (TRIAGEM)        ├── M ──► /rush-quick: spec enxuta ──► implement ──► review
                         │
                         └── L ──► fluxo completo:
                              pitch ──► architect ──► prd ──► features ──► spec+plan
                                 │                                  │
                                 │          contracts ──► prototype (opcional)
                                 │                                  │
                              [gates humanos]      analyze ──► implement ⇄ verifier
                                                                    │
                                                       as-built ──► review ──► retro
```

**Critérios de triagem** (determinísticos primeiro, julgamento depois):

- **S**: 1–3 arquivos, sem mudança de contrato/API, sem migration, sem dependência nova, fora de paths sensíveis (auth, pagamento, dados pessoais — lista no config). Ex.: fix de bug localizado, ajuste de copy, refactor pequeno.
- **M**: escopo claro mas multi-arquivo, ou toca 1 endpoint/contrato existente sem quebra. Spec enxuta (1 arquivo só: mini-spec + tasks) direto para implementação.
- **L**: feature nova, mudança de contrato com quebra, migration, dependência nova, path sensível, ou incerteza de produto ("não sei bem o que quero"). Fluxo completo.
- Em dúvida entre dois níveis, o agente propõe o nível e o humano bate o martelo (1 pergunta, não um questionário).

### A fronteira O QUE / COMO — o que cada artefato pode dizer

A zona cinzenta clássica do SDD ("posso especificar endpoints? layout? que a suíte rode ao fim da task?") é resolvida aqui por **propriedade em camadas**: cada artefato é dono de uma pergunta e está proibido de responder as outras. O analyze rejeita vazamentos entre camadas.

| Artefato | Dono de | Proibido de |
|---|---|---|
| pitch / PRD | **O QUE** e **POR QUÊ** (produto): problema, valor, requisitos, critérios de sucesso | Qualquer tecnologia, endpoint, tela |
| arquitetura | **COMO estrutural**: decisões, restrições, trade-offs, fronteiras, fitness functions | Passo a passo de implementação; requisitos de produto novos |
| spec | **O QUE técnico**: comportamento observável, interfaces/contratos, dados, edge cases, critérios de aceite | Detalhe interno de implementação (nome de variável, estrutura interna de classe); processo do agente |
| plan / tasks | **COMO da implementação**: sequência, arquivos afetados, abordagem | Redefinir comportamento (se precisa, volta à spec) |
| **harness** (config + hooks + constitution) | **COMO o agente trabalha**: rodar testes ao fim da task, commitar, quando parar, o que pedir aprovação | — |

A linha mais importante é a última: **"rodar a suíte e commitar ao finalizar" nunca vai em spec — é harness.** Processo do agente é configurado uma vez por projeto (config + hooks, impostos mecanicamente) e não re-escrito em cada feature. É exatamente assim que o foco da spec não escorrega do sistema para o comportamento do agente — o problema que mata a maioria dos processos SDD.

Teste rápido para saber onde algo pertence: *se a resposta muda quando muda a feature, é spec; se muda quando muda o projeto ou o time, é harness/constitution; se não muda nunca, é o próprio kit.* Endpoints e layout podem ser especificados — endpoints na spec (são interface observável), layout como referência anexa (protótipo) — mas sempre respondendo "o que o sistema faz", nunca "o que o agente deve fazer agora".

---

## 5. Os agentes

### Fase 0 — Adaptação

| Agente | O que faz | Gatilho |
|---|---|---|
| **`rush-init`** | Script determinístico detecta stack (lockfiles, frameworks, CI, testes) e, se houver **preset de stack** correspondente em `.rush/presets/` (NestJS+Prisma, Next.js, Laravel... — contribuíveis pela comunidade), usa-o para acelerar convenções e defaults; `explorer` mapeia arquitetura real; entrevista o usuário sobre produto e convenções não-visíveis no código; gera CLAUDE.md (**≤ 60 linhas**, só regras com justificativa), constitution, product.md, architecture.md, config.json | Manual, 1x por repo; re-executável |
| **`rush-new`** | Modo **greenfield**: em vez de se adaptar a um repo existente, cria o projeto do zero a partir da ideia do produto — descoberta de produto, escolha de stack com trade-offs, scaffold determinístico, fundação do harness, PRD do MVP e **todas as specs do MVP prontas para implementar**. Detalhe na subseção "Modo greenfield" abaixo | Manual, em diretório vazio (ou `rush-init` detecta diretório vazio e oferece) |
| **`rush-doctor`** | Diagnóstico da instalação e da saúde do processo: specs órfãs (sem código), código sem spec, config inválido, hooks quebrados, drift acumulado, orçamentos estourados, questions.md e debt.md esquecidos há muito tempo. Reporta e sugere correção — não corrige sozinho | Manual ou periódico (início de sessão / CI) |

**`config.json`** — contrato do harness, lido por todos e **imposto por hooks** (não só sugerido em prompt). Schema na subseção abaixo.

### Fase 0 em detalhe — como o kit determina o harness de cada projeto

O princípio do `rush-init`: **detectar tudo que é detectável, confirmar em vez de perguntar, e só entrevistar sobre o que o código não revela.** Um onboarding que faz 40 perguntas morre no segundo uso.

**Fluxo (6 passos):**

1. **Detecção determinística** (script, zero LLM): linguagem e versão; framework; package manager; test runner e comando de teste; linter/formatter; CI existente; monorepo?; banco/ORM e migrations; uso de LLM no produto (SDKs de IA nos lockfiles → ativa disciplina 13); **histórico de commits** (o padrão de mensagem que o time *realmente* usa, não o que diz usar); estrutura de pastas. Se houver preset compatível em `.rush/presets/`, aplica os defaults dele.
2. **Exploração** (`explorer`): mapa da arquitetura real — camadas, módulos, padrões recorrentes, convenções implícitas (ex.: "todos os services retornam Result<T>"), pontos de entrada.
3. **Confirmação**: apresenta o que detectou em bloco ("achei isso — corrija o que estiver errado"). Humano corrige exceções; nada detectável vira pergunta.
4. **Entrevista** — só o invisível ao código, em dois blocos curtos:
   - *Produto*: o que é o produto e para quem? O que importa mais neste momento (velocidade de entrega vs robustez — muda os defaults de gate)? O que **nunca pode quebrar** (vira paths sensíveis + fitness functions)? Estágio (MVP / produção / legado em manutenção)?
   - *Convenções invisíveis*: decisões "estranhas" que são intencionais (para o agente não "consertar" o que é escolha — cada uma vira nota no architecture.md); áreas do código proibidas de tocar; dívidas conhecidas que não devem ser pagas agora; quem aprova o quê (se há time).
5. **Geração + revisão**: monta CLAUDE.md (≤ 60 linhas), constitution (só princípios que o humano confirmou como inegociáveis — constitution nasce curta e cresce pelo ratchet, não nasce gorda), product.md, architecture.md, config.json — e apresenta tudo para aprovação antes de gravar.
6. **Smoke test**: roda o verifier baseline (test, lint, build com os comandos detectados). O harness só é declarado instalado se os comandos funcionam — harness que nasce quebrado é pior que nenhum.

**Schema do `config.json` (opções iniciais):**

```jsonc
{
  "language":  { "docs": "pt-BR", "code_comments": "en", "commits": "en" },
  "git":       { "allow_commit": true, "allow_push": false,
                 "commit_convention": "conventional",       // detectado, confirmado
                 "branch_pattern": "feat/NNN-slug" },
  "code":      { "comments_policy": "minimal",              // none | minimal | didactic
                 "test_first": false },
  "gates":     {                                            // "human" | "auto"
                 "architecture": "human", "spec": "human",
                 "feature_close": "human", "implement_start": "auto" },
  "autonomy":  { "max_attempts_per_task": 3,
                 "new_dependency": "ask",                   // ask | allow | deny
                 "migrations": "ask", "edit_tests": "ask" },
  "security":  { "sensitive_paths": ["src/auth/", "src/payments/"],
                 "blocked_commands": ["rm -rf", "git push --force", "DROP TABLE"],
                 "secret_scan_before_commit": true },
  "triage":    { "sensitive_forces_L": true, "max_files_for_S": 3 },
  "ai_features": false                                      // ativa disciplina 13 do arquiteto
}
```

Regra de manutenção: opção que ninguém muda em nenhum projeto é removida do schema (harness mínimo vale para o config também). O `rush-doctor` valida o config contra o schema a cada rodada.

### Modo greenfield — `rush-new`, do zero à fila de specs

O `rush-init` **se adapta** a um projeto; o `rush-new` **cria** um. Os dois coexistem e convergem para o mesmo estado final: harness instalado + specs prontas. A diferença é que no greenfield não há nada para detectar — então detecção vira decisão, e exploração vira criação. Fluxo em 7 passos, reusando os agentes do fluxo L em sequência orquestrada:

1. **Descoberta de produto** (mecânica do `/rush-pitch`): o que é o produto, para quem, que problema resolve, o que é sucesso, e — crítico — **o corte do MVP**: o que fica de fora da primeira versão (apetite explícito). Researcher entra para benchmarks e referências.
2. **Definição de stack** (mecânica do `/rush-architect` + researcher): 2–3 opções de stack com trade-offs explícitos (maturidade, fit com o produto, familiaridade do usuário — pergunta-se!, custo de infra, ecossistema); humano escolhe; a escolha vira o primeiro ADR do projeto. Presets aceleram: escolher um preset = herdar convenções, scripts e defaults testados.
3. **Scaffold determinístico**: script gera o esqueleto usando os geradores oficiais da stack escolhida (ex.: `nest new`, `create-next-app`) — nunca o LLM inventando boilerplate à mão. Git init, CI mínimo, test runner, linter/formatter configurados. **Smoke test obrigatório**: build + teste vazio + lint rodam verdes antes de qualquer outra coisa (mesma regra do init: harness que nasce quebrado é pior que nenhum).
4. **Fundação do harness**: gera CLAUDE.md, constitution, product.md, architecture.md (aqui ela é *intencional* — descreve a arquitetura decidida, e os "as-built" da implementação vão corrigindo-a para a real), config.json. **Cuidado central: a constitution greenfield nasce mínima** — só os princípios que o humano confirmou + defaults do preset. Não inventar 50 regras para um projeto que ainda não tem código; o ratchet engorda a constitution com regras *earned*, como no brownfield.
5. **PRD do MVP** (`/rush-prd`): requisitos, critérios de sucesso e journeys da primeira versão, dentro do corte definido no passo 1.
6. **Breakdown + specs** (`/rush-features` → `/rush-spec` em lote): integration map completo do MVP (provides/consumes/journeys) e spec + plan + tasks + done-contract de **cada feature do MVP**, validados pelo `/rush-analyze`. Gate humano único ao final do lote: revisar a fila antes de codar.
7. **Fila pronta**: features ordenadas pelo grafo de dependências; `/rush-implement` começa pela primeira. A partir daqui, greenfield e brownfield são indistinguíveis — mesmo fluxo, mesmos gates, mesma DoD.

Diferenças de harness que o modo greenfield configura sozinho: triagem inicial irrelevante (tudo já nasce como fila L do MVP; a triagem S/M/L assume quando o MVP fecha), fitness functions nascem junto com a arquitetura intencional (o projeto já nasce com guardas), e `ai_features` é perguntado na descoberta (produto vai usar LLM? → disciplina 13 ativa desde a primeira spec).

### Suporte — sob demanda

| Agente | O que faz | Gatilho |
|---|---|---|
| **`explorer`** (read-only) | Explora área específica do código; devolve resumo denso com paths e convenções, sem inundar o contexto de quem chamou | Qualquer agente ou o usuário |
| **`researcher`** | Pesquisa web/docs oficiais; sempre retorna com fontes | product, architect, contracts |
| **`verifier`** | Roda testes, lint, build, type-check, fitness functions da arquitetura; quando aplicável, testa como usuário (e2e). **Sucesso é silencioso, falha é verbosa**: só o erro volta ao loop. Único que promove task a done | Fim de cada task; hooks |
| **`/rush-brief`** | Handoff entre pessoas ou sessões: gera um resumo do estado atual de uma feature (o que foi feito, o que falta, decisões tomadas, riscos abertos, próximo passo) a partir de progress.md, tasks.md e artefatos — para outro dev (ou outra sessão de agente) assumir sem re-explorar tudo | Manual, sob demanda |

### Fase 1 — Descoberta (só triagem L)

| Agente | O que faz | Gatilho |
|---|---|---|
| **`/rush-pitch`** | Conversa sobre a ideia; usa researcher (benchmarks) e explorer (viabilidade); produz pitch ≤ 1 página: problema, apetite, solução em traços largos, riscos, o que fica de fora | Manual |
| **`/rush-architect`** | Ver seção 6 — especialidades completas | Após pitch aprovado (gate) |

### Fase 2 — Especificação (L; versão condensada no M)

| Agente | O que faz | Gatilho |
|---|---|---|
| **`/rush-prd`** | Pitch + arquitetura → PRD: visão, objetivos, requisitos testáveis, critérios de sucesso mensuráveis e agnósticos de tecnologia. Máx. 3 clarificações, priorizadas por impacto | Após arquitetura |
| **`/rush-features`** | Quebra PRD em unidades de entrega e produz o **integration map**: para cada feature, o que ela **provê** (endpoints, eventos, componentes, dados) e o que **consome** (de outras features ou do sistema existente), mais as **user journeys** do PRD que atravessam múltiplas features. Script cria `specs/NNN-nome/` e valida o grafo: consumo sem provedor, provisão duplicada e ciclo de dependência são erros | Após PRD |
| **`/rush-spec`** | Por feature: spec.md (≤ 150 linhas) + plan.md (≤ 100) + tasks.md + **done-contract.md** (condições de pronto negociadas com o usuário antes de codar). A spec **referencia** o integration map e os shared-contracts — não reinventa interfaces que outra feature provê. Critérios de aceite escritos como casos de teste sempre que possível | Por feature |
| **`/rush-contracts`** | Spec → contratos (OpenAPI/JSON Schema/eventos); script valida (lint/parse). **Interface consumida por 2+ features vive em `shared-contracts/` (fonte única, dona declarada no integration map)** — cada spec referencia, nunca copia. Congelado antes da implementação; mudar contrato = atualizar contrato primeiro, e o analyze reaudita quem consome | Features com API |
| **`/rush-prototype`** | PRD + contratos → protótipo **HTML+CSS estático** (arquivo único, dados mockados respeitando contratos) só para visualizar antes de desenvolver. Descartável por definição | Manual, opcional |

### Fase 3 — Implementação

| Agente | O que faz | Gatilho |
|---|---|---|
| **`/rush-analyze`** | Gate go/no-go: consistência spec ↔ plan ↔ contracts ↔ constitution **e cross-feature**: o que esta spec consome existe no integration map e bate com o shared-contract? Ela quebra alguma interface que outra feature consome? A journey que passa por ela continua fechada de ponta a ponta? Determinístico (artefatos existem? contrato parseia? grafo válido? orçamentos respeitados?) + julgamento (contradições, buracos). Conflito com MUST da constitution = bloqueia | Hook, antes do implement |
| **`/rush-implement`** | Uma task por vez, diffs pequenos, rodando o **loop planejar → agir → observar → ajustar** com guards explícitos (ver "Agent loop engineering" na seção 7): ritual de início (progress, git log, testes-base) → implementa → verifier → commit (se config permite) → progress.md. Ao esgotar contexto, encerra limpo com handoff file; sessão seguinte retoma pelo ritual. **Passo final obrigatório: "as-built"** — compara código com spec e atualiza a spec onde divergiu (com nota do porquê) | Após analyze verde |

### Fase 4 — Revisão e aprendizado

| Agente | O que faz | Gatilho |
|---|---|---|
| **`/rush-review`** | Review assistida e interativa: percorre o diff arquivo por arquivo, explica o quê e o porquê, conecta cada trecho à spec/plan/constitution, aponta riscos, checa sincronia spec↔código, e pergunta antes de seguir. Objetivo: o usuário *entender*, não só aprovar | Manual, fim de feature |
| **`/rush-retro`** | Fecha o ratchet: falhas do ciclo → casos de eval + regras novas (registradas em lessons.md com a falha que as originou) + aposentadoria de checklist items que nunca pegaram nada + ADRs se padrão novo emergiu. Revisita também `debt.md` (cobrar ou aceitar formalmente cada débito) e audita `questions.md` (dúvidas classificadas errado como não-bloqueantes) | Após review ou periódico |

---

## 6. `/rush-architect` — especialidades completas

O arquiteto não é "um agente que dá opinião sobre arquitetura": é um conjunto de disciplinas com saídas verificáveis. Ele opera em cima de pitch + constitution + architecture.md + explorer, e **sempre entrega 2–3 arquiteturas candidatas com trade-offs explícitos** antes de recomendar uma — a rejeitada vira ADR ("consideramos X, rejeitamos porque Y").

**Disciplinas que ele cobre:**

1. **Atributos de qualidade e trade-offs** — avalia a feature contra os atributos que importam para o projeto (desempenho, segurança, manutenibilidade, confiabilidade, escalabilidade, custo — base ISO 25010), num ATAM simplificado: qual atributo essa decisão sacrifica em favor de qual?
2. **Fronteiras e domínio (DDD-lite)** — onde a feature vive? Respeita bounded contexts existentes? Cria acoplamento novo entre módulos? Define o que é domínio, o que é aplicação, o que é infra.
3. **Design de API e contratos** — estilo consistente com o projeto (REST/GraphQL/eventos), versionamento, compatibilidade retroativa, idempotência de endpoints, paginação, erros padronizados. Prepara o terreno para o `/rush-contracts`.
4. **Dados e migrations** — modelagem, estratégia de migração (expand/contract para zero-downtime), índices, retenção, o que é fonte da verdade vs derivado.
5. **Segurança por design** — threat modeling leve (STRIDE nos fluxos novos: spoofing, tampering, repudiation, info disclosure, DoS, elevation), superfície de ataque, authz/authn da feature, dados sensíveis (PII), validação de entrada, checagem contra OWASP Top 10 quando há superfície web.
6. **Resiliência e modos de falha** — o que acontece quando a dependência X cai? Timeouts, retries com backoff, idempotência de operações, circuit breakers, filas vs chamadas síncronas, estratégia de rollback.
7. **Performance com orçamento** — define budgets mensuráveis (latência p95, payload, queries por request) que o verifier pode checar, em vez de "deve ser rápido".
8. **Observabilidade** — o que logar, quais métricas expor, o que alertar; a feature nasce diagnosticável.
9. **Fitness functions (arquitetura evolutiva)** — a saída mais importante: converte decisões arquiteturais em **checks executáveis** que o verifier roda para sempre (ex.: "módulo A não importa módulo B", "endpoint X responde < 200ms no teste de integração", "nenhuma query N+1 no path Y"). Arquitetura que não vira check vira drift.
10. **Política de dependências** — dependência nova exige justificativa: o que já existe no projeto não resolve? Custo de manutenção, licença, atividade do projeto.
11. **Integrações externas** — contratos com terceiros, sandbox vs produção, chaves/segredos, limites de rate, fallbacks.
12. **Custo** — ordem de grandeza do custo de infra da decisão (armazenamento, egress, compute), quando relevante.
13. **Integração de IA** *(condicional — ativada pelo `rush-init` quando o projeto usa/vai usar LLMs)* — arquitetura de features com IA vai muito além de chamar um SDK: análise de modelos e trade-offs (latência × qualidade × custo, e qual modelo para qual tarefa); protocolos de integração (MCP, A2A, function calling); padrões de agentes (workflow vs agente, quando cada um); guardrails de entrada e saída; defesa contra prompt injection e jailbreaking em qualquer superfície que aceite texto do usuário; privacidade (o que pode ou não ir para o provedor do modelo, PII, retenção); cache de chamadas LLM (semântico e exato) para custo e latência; bancos vetoriais e estratégia de retrieval quando há RAG; streaming e mensageria para pipelines de IA; e **evals da feature de IA** como parte do done (uma feature com LLM sem eval não fecha). Base: 12-Factor Agents + OWASP LLM Top 10.

**Saídas**: seção de arquitetura da feature (≤ 100 linhas) + ADR(s) + lista de fitness functions entregue ao verifier + insumos para contracts. Nem toda feature aciona as 13 disciplinas — o arquiteto declara quais se aplicam e por quê (as demais em uma linha: "N/A porque...").

---

## 7. O Harness (transversal)

- **Scripts determinísticos**: detecção de stack; criação/numeração de features; validação estrutural e de orçamento dos artefatos; validação de contratos; triagem (parte determinística); rituais de sessão; `rush eval`.
- **Hooks**: gates automáticos — bloquear commit se config nega; rodar formatter pós-edição; disparar verifier pós-implement; impedir implement sem analyze verde; bloquear comandos destrutivos da blocklist. **Hook impõe; prompt apenas pede** — regra de segurança nunca vive só em prosa.
- **Progresso e memória**: tasks.md (tudo nasce pending; só o verifier promove) + progress.md + git como memória de longo prazo + handoff files para troca de sessão + lessons.md (ratchet log).
- **Q&A assíncrono (`questions.md`)**: dúvidas *não-bloqueantes* dos agentes não interrompem o humano — vão para `questions.md` (com contexto, opções e a suposição adotada enquanto isso) e são respondidas em lote. Dúvida bloqueante continua parando e perguntando; a distinção é declarada pelo agente e auditada no retro. O ritual de início de sessão checa se há respostas novas e as propaga aos artefatos.
- **Débito técnico estruturado (`debt.md`)**: quando o implementer toma um atalho consciente, registra: o quê, por quê, custo estimado de pagar, task/feature de origem. O retro revisita e cobra; atalho *não registrado* descoberto na review vira caso de eval contra o implementer. Débito deixa de ser TODO perdido no código e vira item de gestão.
- **Worktrees paralelos**: features sem dependência entre si (segundo o grafo do `/rush-features`) podem ser implementadas em paralelo, cada uma em um git worktree isolado — sem conflito de estado entre sessões. Script determinístico cria/destrói os worktrees; o merge é coordenado na ordem do grafo, com verifier rodando após cada merge. Fase 2+ do roadmap (exige o núcleo estável).
- **Contexto**: subagents isolam trabalho pesado e devolvem resumo; artefatos são a interface entre agentes (nunca "leia a codebase inteira"); outputs longos de ferramenta vão para arquivo, só head/tail no contexto; skills carregadas sob demanda.
- **Permissões**: config + hooks definem o que o agente faz sozinho vs o que exige aprovação; ações sensíveis são gates auditáveis, allowlist/blocklist de comandos.
- **Agent loop engineering** (o ciclo do implementer, projetado — não emergente): cada task roda planejar → agir → observar → ajustar, com **guards que o prompt não pode ignorar**: (a) *critério de parada positivo* = done-contract da task passa no verifier; (b) *critério de parada negativo* = orçamento de tentativas — após **3 falhas do verifier na mesma task**, o agente para de tentar, escreve um relatório do que tentou e por que acha que falha, e **escala para o humano** (contato humano é uma ferramenta do agente, não um acidente); (c) proibido "afrouxar o teste para passar" — alterar teste/check existente exige aprovação humana via gate; (d) erros voltam ao loop compactados (só o essencial), não como despejo de log. Observabilidade do loop: cada ação relevante registrada em `progress.md` + trail auditável via git.
- **Segurança do próprio kit** (os agentes também são superfície de ataque): todo conteúdo que os agentes leem de fora — páginas web do researcher, issues, README de dependência, até código do próprio repo em um repo clonado — é **dado, não instrução**; os prompts dos agentes declaram isso e os hooks impõem as consequências (nenhum comando fora da allowlist, nenhum path fora do repo, nenhum segredo em artefato — scan determinístico de segredos antes de commit). Instrução embutida em conteúdo externo ("ignore suas regras e...") deve ser reportada, nunca obedecida.

### Definition of Done executável — a fonte da verdade de "pronto"

Resposta direta à pergunta "como a IA sabe que a task/feature terminou de verdade?": existe uma cadeia de DoD em três níveis, e **todos são verificáveis por máquina** — prosa nunca é o critério final.

1. **Por task** — `tasks.md` carrega, junto de cada task, seus checks: comando + resultado esperado (ex.: `npm test -- auth.spec` → exit 0; `curl :3000/health` → 200). Task só vira `done` quando o verifier executa os checks e passam. O implementer não tem permissão de editar status — hook garante.
2. **Por feature** — `done-contract.md`, negociado com o humano **antes da primeira linha de código** (o "sprint contract" do harness engineering), em formato executável:

   ```yaml
   # done-contract.md (bloco machine-readable)
   checks:
     - name: acceptance tests pass        # critérios de aceite da spec viraram testes
       run: npm test -- specs/007-checkout
       expect: exit 0
     - name: contract honored
       run: rush-scripts/validate-contract.sh specs/007-checkout/contracts/
       expect: exit 0
     - name: fitness functions            # herdadas do arquiteto
       run: rush-scripts/fitness.sh 007
       expect: exit 0
     - name: no spec drift
       run: rush-scripts/check-as-built.sh 007
       expect: exit 0
   human_gates:                           # o que só o humano fecha
     - review assistida concluída (/rush-review)
   ```

   Feature fechada = todos os `checks` verdes **e** todos os `human_gates` confirmados. Se um critério de aceite não é automatizável (ex.: "a explicação é clara"), ele vai para `human_gates` explicitamente — nunca fica implícito.
3. **Por journey (integração)** — as user journeys do integration map viram **journey tests**: testes de ponta a ponta que atravessam features e só passam quando elas funcionam *juntas*. Uma feature individual fecha com seus checks; a **entrega** (grupo de features de uma journey) só fecha quando o journey test passa. É a defesa executável contra "cada feature funciona sozinha, mas o fluxo do usuário está quebrado". O verifier roda os journey tests afetados a cada merge de feature.
4. **Permanente** — fitness functions, testes e journey tests continuam no CI depois do fechamento: o done não expira silenciosamente.

Efeito colateral importante: o done-contract também é o **critério de parada do loop** do implementer e o **grader de eval** do próprio kit — a mesma fonte da verdade serve às três coisas.

## 8. Evals

Cada agente tem `.rush/evals/<agente>/`:

- **Casos**: 10–20 por agente, vindos de uso real (o retro alimenta) — não 200 sintéticos.
- **Graders em camadas**: (1) código — determinístico: artefato existe? seções presentes? orçamento respeitado? contrato parseia? testes passam? (2) LLM-as-judge com rubrica calibrada contra julgamento humano — spec é testável? explicação da review é clara? (3) humano — feedback das reviews vira caso novo.
- **Pipeline**: `rush eval <agente>`; ler transcripts regularmente; eval que satura (100% sempre) é endurecido ou aposentado.
- **E2E do fluxo inteiro**: fase 2 do roadmap (caro; só depois dos evals por agente estarem rodando).

## 9. Decisões resolvidas (da v0.1)

- ✅ **Fast path**: sim — e promovido a porta de entrada via triagem S/M/L (`/rush` + `/rush-quick`).
- ✅ **Nome**: Rush DevKit, definitivo. Prefixo `.rush/`.
- ✅ **Distribuição**: git clone (template copiável).
- ✅ **Protótipo**: HTML+CSS estático, arquivo único, só para visualizar.
- ✅ **Evals e2e**: fase 2 do roadmap.

## 10. Roadmap de construção

1. **MVP do núcleo**: `rush-init` + config + triagem `/rush` + `explorer` + `/rush-quick` + `/rush-implement` + `verifier` + `/rush-review` + `questions.md` e `debt.md` (baratos e de alto valor desde o dia 1).
2. **Fluxo L completo**: pitch, architect, prd, features, spec, analyze + `/rush-brief` e `rush-doctor`.
3. **Contratos, protótipo e greenfield**: contracts, prototype, presets de stack (formato contribuível) + `rush-new` (é orquestração dos agentes do fluxo L já prontos na fase 2 — por isso entra aqui, não antes).
4. **Aprendizado e escala**: evals por agente, retro, hooks de gate completos, worktrees paralelos; depois evals e2e.

---

## Fontes estudadas

**SDD — metodologia e críticas de campo:**
- [Spec-Driven Development (github/spec-kit)](https://github.com/github/spec-kit/blob/main/spec-driven.md) — fases, constitution, artefatos
- [Putting Spec Kit Through Its Paces (Scott Logic)](https://blog.scottlogic.com/2025/11/26/putting-spec-kit-through-its-paces-radical-idea-or-reinvented-waterfall.html) — crítica empírica: bloat de markdown, 10x mais lento, waterfall
- [Understanding SDD: Kiro, spec-kit e Tessl (Martin Fowler)](https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html) — spec-first vs spec-anchored vs spec-as-source; review fatigue; agentes ignorando specs
- [SpecKit creates the illusion of work (discussão oficial)](https://github.com/github/spec-kit/discussions/1784) — checklist theater relatado por usuários

**Harness engineering:**
- [Effective harnesses for long-running agents (Anthropic)](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — feature lists, progress files, rituais, modos de falha
- [Agent Harness Design: 3 Patterns (Anthropic/Claude)](https://claude.com/blog/harnessing-claudes-intelligence) — harness mínimo, "what can I stop doing"
- [Agent Harness Engineering (Addy Osmani)](https://addyosmani.com/blog/agent-harness-engineering/) — ratchet pattern, CLAUDE.md ≤ 60 linhas earned, sucesso silencioso, generator/evaluator split, sprint contracts, permission gates, compaction
- [12-Factor Agents (HumanLayer)](https://github.com/humanlayer/12-factor-agents) — own your context/prompts/control flow, agentes pequenos e focados, erros compactados, contato humano como tool call
- [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/) — prompt injection, insecure output handling (base da disciplina 13 do arquiteto e da segurança do próprio kit)

**Evals:**
- [Demystifying evals for AI agents (Anthropic)](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) — graders em camadas, começar com 20–50 casos reais, minerar falhas

**Base prática:** seus skills em `aitr-backend/.claude/skills/speckit-*` e `.specify/` (checklists de qualidade, limite de 3 clarificações, scripts bash).
