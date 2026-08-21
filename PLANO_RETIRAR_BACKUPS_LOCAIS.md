# Plano — retirar os backups locais dos 4 projetos

Iniciado e **concluído** em 2026-08-20: o único backup local dos quatro
projetos passou a ser o BackupRestore.

Documento irmão: [PLANO_BACKUPRESTORE_VPS.md](PLANO_BACKUPRESTORE_VPS.md) (o
mesmo raciocínio de "uma ferramenta, um dono" aplicado à produção).

---

## 1. A pergunta tem duas respostas diferentes

Levantei os quatro projetos. **Três têm um mecanismo que é puro duplicado do
BackupRestore** — mesma coisa, escrita de novo, sem o catálogo, sem verificação
de artefato (na maioria), sem retenção coordenada. Esses podem sair.

**Um não é duplicado.** O `criar_backup_banco` do ConfortoTermico é um mecanismo
de natureza diferente: roda **dentro do contêiner da aplicação**, acionado por
uma rota HTTP autenticada (`POST /api/backup-banco`), sem precisar de `docker`
no host de quem aciona. É o único dos quatro que funciona **sem acesso de linha
de comando ao host** — inclusive em produção, onde o BackupRestore não roda e
provavelmente nunca vai rodar. Ver seção 3.

---

## 2. O que existe hoje, por projeto

| Projeto | Mecanismo | Onde roda | Verifica o dump? | Agendado? |
|---|---|---|---|---|
| **ControleRendaVariavel** | `scripts/backup.ps1` | host, via `docker compose exec` | não | **sim** — tarefa `ControleRendaVariavel Backup`, diária 02:00 |
| **MegaSena** | `scripts/backup_postgres.ps1` | host, via `docker compose exec` | não | não — manual, antes de mudança de schema |
| **ControleBancario** | `scripts/backup_postgres.ps1` | host, via `docker compose exec` | **sim**, `pg_restore --list` | não — manual, antes de mudança de schema |
| **ConfortoTermico** | `POST /api/backup-banco` → `criar_backup_banco` | **dentro do próprio contêiner**, via rede | não | não — botão na área autenticada |

Os três primeiros gravam num `backups/` ou `instance/backups/` dentro do
próprio projeto, fora do Git, sem catálogo, sem SHA-256, sem retenção
coordenada (só o do Renda Variável tem retenção própria: 30 dias).

### A tarefa do ControleRendaVariavel está falhando

Não é suposição — é o que o Agendador de Tarefas registra: a última execução
retornou o código **`0x800710E0`**, um erro. Isso não foi percebido, porque
nada olha essa tarefa. É exatamente o modo de falha que o BackupRestore existe
para evitar (regra 2: "código de saída zero não prova nada" — aqui nem isso
havia, e o erro passou em silêncio mesmo assim).

### Arquivos avulsos já espalhados

Cada `backups/`/`instance/backups/` já acumulou dumps não catalogados:

| Projeto | O que tem lá |
|---|---|
| ConfortoTermico | 1 dump de 6,8 MB (16/08, "pre_hardening") |
| MegaSena | 2 dumps de 130 KB (16/08) |
| ControleBancario | 1 dump de 214 KB (16/08) + pasta `migration-vps/` |
| ControleRendaVariavel | 6 dumps de ~160 KB (15/08 a 19/08) |

Todos `.gitignore`d, nenhum no catálogo do BackupRestore, nenhuma verificação.
Não é urgente, mas é o tipo de coisa que esse projeto existe para não deixar
acontecer. Ver seção 6.

---

## 3. Por que o ConfortoTermico fica de fora

Três motivos, e o terceiro é o decisivo:

1. **Mecanismo diferente.** Não é `docker exec` disparado do host — é a própria
   aplicação rodando `pg_dump` contra o Postgres pela rede interna do Compose.
2. **Não precisa de CLI no host.** Um operador autenticado na tela aciona pelo
   navegador. Ninguém mais nos quatro projetos oferece isso.
3. **É a única coisa parecida com backup que existe em produção hoje**, fora do
   que acabamos de montar no VPS (Camada 1, `backup-db.sh`, diário). E os dois
   não competem: o `backup-db.sh` é agendado e cego ao que está acontecendo; o
   botão do ConfortoTermico é acionado por um humano no instante exato antes de
   uma ação arriscada — o mesmo papel que a regra 5 do BackupRestore cumpre
   para restauração ("todo restauração começa por um dump de segurança"). Tirar
   isso não sobra em lugar nenhum a mesma garantia.

**Recomendação: manter.** Ele nem compete pelo mesmo problema — resolve um que
o BackupRestore estruturalmente não alcança (produção, sem host, sem CLI).

---

## 4. O que precisa existir antes de tirar qualquer coisa

**O BackupRestore local também não está agendado.** Confirmei: não existe
tarefa `BackupRestore` neste computador — o `README.md` documenta o comando
`schtasks` que a cria, mas ela nunca foi criada. O artefato mais recente do
catálogo é de 16/08.

Isso é um bloqueio, não um detalhe. Hoje, dos quatro, só o Renda Variável tenta
rodar backup sozinho todo dia — e está falhando sem que ninguém veja. Tirar os
outros dois scripts manuais (MegaSena, ControleBancario) sem essa base pronta
trocaria "eu lembro de rodar o script" por nada, porque `cli.py backup --todos`
também só roda quando alguém lembra.

**Fase 0, portanto: criar a tarefa agendada do BackupRestore antes de mexer em
qualquer um dos quatro projetos.** O comando já está documentado no
`README.md`:

```powershell
schtasks /create /tn "BackupRestore" /tr "\"%LOCALAPPDATA%\Python\bin\python.exe\" \"C:\Users\MSPA\Dropbox\Programacao\VSCodeProjects\BackupRestore\cli.py\" backup --todos" /sc daily /st 03:00
```

Sem essa fase, o resto deste plano piora a situação em vez de melhorá-la.

---

## 5. Fases, depois da Fase 0

| Fase | Projeto | O que sai | O que substitui |
|---|---|---|---|
| 1 | ControleRendaVariavel | tarefa `ControleRendaVariavel Backup` + `scripts/backup.ps1` | `cli.py backup --projeto controle_renda_variavel` (já coberto pela tarefa diária do BackupRestore) |
| 2 | MegaSena | `scripts/backup_postgres.ps1` | `cli.py backup --projeto mega_sena --tipos banco` sob demanda, antes de mudança de schema |
| 3 | ControleBancario | `scripts/backup_postgres.ps1` | `cli.py backup --projeto controle_bancario --tipos banco` sob demanda |
| — | ConfortoTermico | nada | fica como está (seção 3) |

Fase 1 primeiro porque é a única coisa **ativamente quebrada** — a maior parte
do valor deste plano já vem daí sozinho. Fases 2 e 3 são limpeza, não urgência.

### O que muda em cada projeto

Por fase: apagar o script, remover a entrada de `scripts/` do README (a seção
"Scripts operacionais" do ControleBancario, por exemplo), e trocar o comando
citado em **README, AGENTS.md e, no caso do ControleBancario, TESTING.md** —
os três têm a frase "antes de mudança de schema/dado, faça backup validado
com `.\scripts\...`" como requisito do fluxo de trabalho, não como nota de
rodapé. Apagar o script sem atualizar essas três frases deixa a instrução
apontando para um arquivo que não existe mais.

Para o Renda Variável, apaga-se também a tarefa agendada:

```powershell
schtasks /delete /tn "ControleRendaVariavel Backup" /f
```

### O atrito que este plano introduz, dito sem disfarce

Hoje, antes de uma mudança de schema, o fluxo é `cd` para o projeto e rodar
`.\scripts\backup_postgres.ps1` — um comando, no diretório em que já se está
trabalhando. Depois deste plano, o mesmo passo vira `cd` para o BackupRestore e
rodar `python cli.py backup --projeto <slug> --tipos banco` — troca de pasta,
mais precisa ter o ambiente do BackupRestore pronto (`pip install -r
requirements.txt` lá). É uma perda real de conveniência para ganhar um catálogo
único, verificação e retenção coordenada. Vale a troca, mas não é de graça.

---

## 6. Arquivos avulsos (seção 2) — proposta separada, baixa prioridade

Não fazem parte das fases acima porque não têm risco de segurança nem custo —
são só desorganização. Duas opções, sem urgência:

- **Deixar como estão.** Já ignorados pelo Git, ocupam ~8 MB no total.
- **Apagar depois de confirmar** que o BackupRestore já tem cobertura
  equivalente ou mais recente no catálogo para cada projeto.

Recomendo a segunda, mas só depois da Fase 0 — não faz sentido apagar nada
antes do backup automático estar garantido de novo.

---

## 7. Decisões — validadas em 2026-08-20

| # | Pergunta | Decisão |
|---|---|---|
| A | ConfortoTermico entra na retirada? | ✅ **Não** — não é duplicado (seção 3) |
| B | Ordem de execução | ✅ **Fase 0 primeiro, sempre** — depois 1, 2, 3 nessa ordem |
| C | Arquivos avulsos da seção 6 | ✅ **Apagar**, mas só depois da Fase 0 |

**O plano está validado.** Execução começa pela Fase 0.

---

## 8. Fase 0 — concluída em 2026-08-20

Tarefa `BackupRestore` criada:

```
Execute:   C:\Users\MSPA\AppData\Local\Python\bin\python.exe
Arguments: C:\Users\MSPA\Dropbox\Programacao\VSCodeProjects\BackupRestore\cli.py backup --todos
Trigger:   diário, 03:00, próxima execução 2026-08-21T03:00
```

O interpretador foi escolhido conferindo qual dos três `python.exe` do host
tem Flask instalado — o atalho da Microsoft Store (`WindowsApps\python.exe`)
nem resolve como arquivo real, e `Programs\Python\Python314\python.exe` não
tem Flask. Só `AppData\Local\Python\bin\python.exe` serve, batendo com o
exemplo do README (não foi coincidência: é o único caminho funcional).

Disparada manualmente para validar antes de confiar no agendamento
(`schtasks /run`). Resultado: `LastTaskResult 0`, e os oito artefatos
esperados (banco + código dos quatro projetos) entraram no catálogo como
`valido` — cada um já relido e verificado, não só "o processo terminou".

**A partir de agora o backup local dos quatro projetos volta a rodar sozinho,
todo dia, sem depender de ninguém lembrar.** As Fases 1–3 (retirar os scripts
duplicados) podem prosseguir com segurança.

## 9. Fases 1–3 e limpeza — concluídas em 2026-08-20

Todas as três fases seguiram o fluxo já validado neste projeto:
`chore/retirar-backup-local` → PR → CI → merge. Nenhuma exigiu deploy no VPS —
os três scripts eram de operador (host), nunca copiados para a imagem Docker
(`COPY scripts/` conferido ausente nos três Dockerfiles).

| Fase | Projeto | PR | CI | Merge |
|---|---|---|---|---|
| 1 | ControleRendaVariavel | [#16](https://github.com/MSPA-Coder/ControleRendaVariavel/pull/16) | pass | `40c3dca` |
| 2 | MegaSena | [#21](https://github.com/MSPA-Coder/mega-sena/pull/21) | pass | squash |
| 3 | ControleBancario | [#21](https://github.com/MSPA-Coder/sistema-financeiro/pull/21) | pass | squash |

Em cada um: script apagado; tarefa agendada removida quando existia (só o
Renda Variável tinha); README/AGENTS.md/CONTEXT.md/TESTING.md/docs atualizados
para apontar `python cli.py backup --projeto <slug> --tipos banco` no
BackupRestore, no lugar do script.

**Limpeza da seção 6 também concluída**, depois de confirmar que o catálogo do
BackupRestore já tinha cobertura mais recente (o backup de hoje, Fase 0,
`valido` para os quatro): ~7,9 MB de dumps avulsos removidos dos quatro
projetos. Preservados de propósito — não são backup, são artefatos de outro
trabalho: `ControleBancario/backups/migration-vps/` e
`ControleRendaVariavel/backups/container-hosts.txt`.

**O plano está encerrado.** Único backup local dos quatro projetos, a partir
de agora, é o BackupRestore — agendado, catalogado, verificado.

---

## Registro de sessões

- **2026-08-20** — Levantamento e plano. Descoberto: a tarefa agendada do Renda
  Variável está falhando (`0x800710E0`) sem que ninguém tenha notado; o
  BackupRestore não tem tarefa agendada própria, apesar de documentada; o
  backup do ConfortoTermico é mecanismo diferente (in-app, sem CLI), não
  duplicado. Três decisões validadas (A, B, C — seção 7), todas na opção
  recomendada. **Fase 0 executada e verificada** (seção 8). **Fases 1–3 e a
  limpeza da seção 6 executadas na mesma sessão** (seção 9), sem
  interrupções — as três CIs passaram de primeira. Plano encerrado.
