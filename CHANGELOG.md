# Changelog

## 1.0.0

Primeira versão estável. O histórico de desenvolvimento das versões 0.x foi consolidado aqui; o
detalhe de cada mudança continua no histórico do git.

### O que a 1.0.0 entrega

- **Triagem S / M / L** (`/rush`) com sinais determinísticos, e um caminho para cada porte:
  edição direta, `/rush-quick` ou o fluxo completo.
- **Fluxo L PRD-first**: `/rush-pitch` (opcional) → `/rush-prd` → `/rush-architect` →
  `/rush-features` → `/rush-spec` / `/rush-spec-all` → `/rush-analyze` → `/rush-implement` →
  `/rush-review` → `/rush-pr` → `/rush-retro`.
- **Integration map** validado por script, com shared contracts e journey tests. Uma feature que
  cruza fronteira precisa de um check que rode essa fronteira de verdade, não só mocks.
- **`done-contract.md` executável**, negociado antes do código. Só o `rush-verifier` promove uma
  task, e hooks impedem que alguém afrouxe um teste para passar.
- **`/rush-analyze` em rodada única**: corrige o que é mecânico, pergunta o que é decisão,
  re-verifica e dá um veredito binário. Nunca pede para ser rodado de novo.
- **Harness por hooks**: política de commit e branch, comandos bloqueados, scan de segredos, paths
  sensíveis, edição de teste e de constitution.
- **Economia de contexto**: `context-pack.sh`, budgets por artefato ligados por padrão, modelo e
  `effort` por skill no frontmatter (`opus` só onde a decisão roda uma vez), e subagents de apoio
  em `haiku`, que escalam para `sonnet` quando a pergunta pede.
- **Ratchet**: `/rush-retro` transforma falhas em evals, fitness functions ou regras com origem
  rastreável, e aposenta o que nunca dispara.
- **Atualização segura**: `update.sh` com merge em três vias, migrações de config e
  `/rush-update` para os conflitos que exigem julgamento.

### Atualizando de uma versão 0.x

Projetos instalados com uma versão anterior à 1.0.0 atualizam normalmente com `update.sh`. As
migrações de config das versões 0.x continuam no kit e são aplicadas em ordem.
