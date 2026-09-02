# Atualizando o kit num projeto que já se adaptou

Depois de `/rush-init`, um projeto não tem mais "o kit instalado" — tem o kit *mais* um
`config.json` gerado para a stack dele, uma constitution escrita, specs, memória, casos de eval
que o `/rush-retro` criou, às vezes um template customizado. Atualizar precisa trazer o kit novo
sem tocar em nada disso.

`install.sh` não serve para isso, e não é por descuido: ele tem dois modos e os dois estão errados
para atualizar. Sem `--force` ele pula tudo que já existe — e depois do `rush-init` existe tudo,
então um "update" copiaria zero arquivos. Com `--force` ele sobrescreve tudo, incluindo o
`config.json`, o `CLAUDE.md`, o `settings.json`, a memória e os evals do projeto. Por isso o
update é um comando separado.

## Como rodar

```bash
git clone https://github.com/<voce>/rush-devkit.git /tmp/rush-devkit
/tmp/rush-devkit/update.sh /caminho/do/seu/repo --dry-run   # o que aconteceria
/tmp/rush-devkit/update.sh /caminho/do/seu/repo             # aplica
```

Quem roda é sempre o kit **novo**, contra o projeto. Não é detalhe de conveniência: só a versão
que introduz uma mudança traz a migração que explica o que aquela mudança significa para um config
escrito antes dela. Um updater morando dentro do projeto estaria sempre uma versão atrasado demais
para saber.

Se o update terminar sem conflito, acabou. Se não:

```
2 file(s) changed both upstream and in this project.
Resolve them with /rush-update inside the project, then run:
  /tmp/rush-devkit/update.sh /caminho/do/seu/repo --finalize
```

## As três classes de arquivo

A decisão é por caminho, em `.rush/scripts/lib/kitfiles.py`, e não muda entre execuções:

| Classe | O que é | O que o update faz |
|---|---|---|
| **kit** | `.rush/scripts/`, `.rush/hooks/`, `.rush/templates/`, `.rush/presets/`, os evals e fixtures que o kit envia, `.claude/skills/`, `.claude/agents/`, `config.schema.json`, `config.default.json`, `VERSION` | Substitui quando o projeto não tocou. Se o projeto tocou **e** o kit mudou, vira conflito. |
| **seed** | `.rush/memory/**` (o exemplo de fitness function, o placeholder de `decisions/`) | Escrito uma vez, na instalação. Um update nunca volta lá — nem quando o kit mudou o arquivo. |
| **merge** | `.claude/settings.json` | Merge determinístico campo a campo: as entradas de hook do kit são atualizadas, os hooks e permissões do projeto ficam. |

Tudo o mais não é assunto do kit e nunca aparece num plano: `config.json`, `state.json`, `specs/`,
`CLAUDE.md`, `secret-scan-allow`, e qualquer caso de eval que o kit nunca enviou — que é
exatamente como os casos do `/rush-retro` sobrevivem.

## Por que existe um baseline

Para fazer merge honesto de um arquivo são precisas **três** versões, não duas: a que o kit
instalou (`base`), a que está no disco (`local`) e a que o kit novo traz (`new`). Só com a base dá
para separar "isto o usuário mudou" de "isto o kit mudou" — sem ela, um merge é adivinhação sobre
qual metade do texto é customização.

Por isso o `install.sh` grava, junto com os arquivos:

- **`.rush/manifest.json`** — por arquivo do kit: o hash do que está no disco (`sha256`), o hash do
  que o kit enviou naquela versão (`kit_sha256`) e a classe. Os dois hashes existem porque eles
  divergem de propósito assim que o projeto customiza algo: `local ≠ enviado` responde "o projeto
  mexeu", e `enviado-antes ≠ enviado-agora` responde "o kit mexeu".
- **`.rush/baseline.tar.gz`** — a cópia pristina de cada arquivo de classe `kit`.

Os dois devem ser **commitados**: quem clonar o projeto precisa deles para atualizar. Já
`.rush/backups/` e `.rush/.update/` são temporários e ficam fora do git.

Projeto instalado antes disso existir não tem manifesto. `update.sh --adopt` gera um a partir do
estado atual, avisando que nessa primeira vez não há como detectar edições locais em arquivo do
kit — não existe contra o que comparar. Todos são tratados como pristinos e substituídos, com
backup de cada um em `.rush/backups/<timestamp>/`.

## Migrações de config

Onde o `config.json` do projeto encontra uma mudança de semântica do kit, uma migração decide — e
a pergunta que ela faz não é "qual é o novo default", é **"o projeto escolheu esse valor ou só
herdou o default de uma versão anterior?"**. Um valor igual ao default antigo nunca foi decisão:
acompanha o kit. Um valor diferente foi escolha: fica, e é reportado.

Elas vivem em `.rush/migrations/<versão>.py` **do kit novo**, e o runner aplica em ordem toda
migração cujo `VERSION` está em `(instalada, nova]`. As duas que existem hoje são exemplos reais:

- **0.5.0** — `git.branch_pattern` deixou de ser decorativo e passou a ser aplicado pelo
  `guard-bash.sh`. Um projeto carregando a string default `"feat/NNN-slug"` começaria a ter todo
  commit em `main` negado sem que ninguém tivesse escolhido isso, então a herdada vira a lista
  `["feat/NNN-slug", "main", "master"]`. Uma string diferente é escolha: fica, com um aviso de que
  agora é aplicada.
- **0.6.0** — os `budgets` viraram `null`. Cada chave igual ao default antigo é liberada; uma
  diferente (um `claude_md: 40` que alguém apertou de propósito) fica e é reportada.

## O que o script decide e o que o agente decide

O `update.sh` faz tudo que é decidível — copia, remove, faz o merge do `settings.json`, roda as
migrações — e **para** no que exige julgamento, sem tocar no arquivo de trabalho. As três versões
vão lado a lado para `.rush/.update/<stamp>/{base,local,new}/`, e o `/rush-update` faz o merge:
aplica o que o kit mudou (`base` → `new`) por cima do que o projeto mudou (`base` → `local`),
carregando a *intenção* da customização quando a versão nova reestruturou a seção onde ela morava.

Ele só faz merge de **prompt e template**. Script e hook ficam para um humano mesmo sendo
perfeitamente legíveis: um merge sintaticamente válido e semanticamente errado no `guard-edit.sh`
bloqueia toda escrita no projeto — inclusive a correção dele mesmo. Isso já aconteceu neste kit e
está registrado no eval `kit-no-bash32-breaking-constructs`.

Depois do merge o `/rush-update` roda o portão de verificação — lint de portabilidade, `doctor`,
`validate-artifacts --all` e `eval --all` — e, se algo regrediu, restaura de
`.rush/backups/<stamp>/` em vez de insistir no merge.

## O finalize não é burocracia

O manifesto e o baseline só são reescritos no `--finalize`, depois dos merges. A ordem importa: é
isso que faz o manifesto registrar o arquivo mergeado como **deliberadamente divergente** do que o
kit envia. Sem isso, no update seguinte ele pareceria pristino e seria sobrescrito — o merge se
perderia silenciosamente na atualização seguinte. Pelo mesmo motivo o `.rush/VERSION` também só é
escrito no finalize: um projeto com conflito pendente não pode anunciar a versão nova enquanto
roda prompts da antiga.

Enquanto isso não acontece, o `doctor.sh` reporta o estado como `warning` no check `kit_update`,
com o comando exato que falta.

## Ver também

- [`agents.md`](./agents.md) — `/rush-update` em detalhe.
- [`internals/script-interfaces.md`](./internals/script-interfaces.md) — contrato do
  `kitfiles.py`, do `update.sh` e do formato do manifesto.
- [`configuration.md`](./configuration.md) — as chaves que as migrações tocam.
