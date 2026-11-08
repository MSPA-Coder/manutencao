# Manutenção VPS — guia de trabalho

<!-- comum: início. Cópia de _manutencao/compartilhados/AGENTS-comum.md; mude lá e rode sincronizar.py --aplicar. -->
## Regras comuns aos repositórios

**O que espera o "sim" do mantenedor:** commit e push (quando ele pedir),
deploy, qualquer ação no VPS, e apagar dados, volumes ou backups
(`docker compose down -v` inclusive). Na dúvida sobre algo irreversível,
pergunte; no resto, decida e diga o que decidiu.

**Ciclo.** Altere, rode a verificação completa deste repositório (seção
"Validação"), commite direto no `main` e dê `git push`: sem PR, sem push
forçado, sem rebase do `main` publicado. A CI roda depois, só como aviso, mas
vermelho no `main` se investiga. O Dependabot chega por PR, com merge manual. O
deploy é `~/deploy.sh <app>` no VPS1: monta a imagem a partir do `main`,
confere `/health` e volta sozinho se falhar. O VPS só espelha o `main`; nada se
edita lá. Imagem-base nova (correção do Debian ou do Python) só quando ele
pedir: testa na máquina e depois `~/deploy.sh <app> --refresh`. Ao terminar,
diga o que rodou, o resultado e o que deixou de validar.

**Dados e segredos.** Mudança destrutiva ou conversão de dados reais começa por
backup conferido no BackupRestore. Segredos ficam fora do Git (`.secrets/` ou
configuração do usuário) e não aparecem em código, imagem, log, diff,
documento nem relatório.

**Dependências.** Alargue o teto e preserve o piso já verificado: elevar o piso
afirma uma incompatibilidade, e isso exige prova. Vulnerabilidade se corrige
atualizando; exceção só explícita, com motivo e data. Enquanto o Dependabot não
aceitar Python 3.15, ele não propõe atualização de `uv` e o grafo do GitHub fica
parado no lock de 13/10/2026: confira alerta pela versão do `uv.lock`, e
atualize à mão (`uv lock --upgrade-package <pacote>`) quando o `pip-audit` ou o
Trivy apontarem.

**Testes.** `docs/TESTES.md` diz o que testar e como. Diante de vermelho,
decida de quem é o defeito; nunca escreva código para um teste passar. Não
rode duas verificações do mesmo repositório ao mesmo tempo: a segunda recria o
banco de teste e derruba a primeira.

**Cópias.** Este bloco, `docs/TESTES.md` e os arquivos listados em
`_manutencao/compartilhados/sincronizar.py` são cópias: mude a canônica lá e
rode `python compartilhados/sincronizar.py --aplicar` no `_manutencao`.

**Este arquivo.** Guarde aqui só o que o código não diz: limites, decisões com
o motivo, armadilhas e comandos. História fica no `git log`; decisão com
alternativas vira ADR; detalhe de implementação fica no código. Para
acrescentar uma regra, retire ou funda outra: `sincronizar.py` reprova este
arquivo acima de 900 palavras fora deste bloco.
<!-- comum: fim -->

## Escopo

Este repositório é a fonte única dos scripts, unidades e runbooks do VPS. Leia
`README.md` e o script afetado em `vps/` antes de alterar deploy, backup,
monitoramento ou instalação. Teste os scripts exclusivamente pela suíte Docker
em `vps/tests/`; nunca teste contra o VPS durante desenvolvimento.

## Invariantes operacionais

- O VPS espelha `main`: não recebe commits, builds ou edições manuais.
- `deploy.sh` é o único caminho para atualizar aplicações. Cada aplicação usa
  o lock compartilhado para excluir deploy, timer e snapshot de volume.
- Rollback restaura código e imagem, nunca migrações ou dados. Uma mudança de
  schema precisa de compatibilidade ou de um procedimento explícito de retorno.
- Não crie backup local por rotina de alteração. O backup diário de produção é
  a recuperação normal; exija uma validação adicional apenas para migração,
  transformação persistente ou alteração de backup/criptografia. Essa validação
  usa `~/backup-db.sh --forcar`: dump feito à mão não tem `.sha256` e reprova a
  sincronização do BackupRestore.
- Segredos, chaves privadas e conteúdo de backups não entram no Git nem nos
  logs de testes.

## Validação proporcional

| Mudança | Validação mínima |
| --- | --- |
| Documento ou unidade systemd | `git diff --check` e conferência de caminhos/comandos. |
| Script de deploy, backup ou vigia | A suíte Docker específica em `vps/tests/`. |
| Instalação ou inventário | Testes de `instalar.sh` e `--check` no ambiente de teste. |
| Mudança que altera dados/volumes | Teste de backup e restauração no sandbox; não use o VPS como laboratório. |
| Bloco comum, `docs/TESTES.md` ou outra cópia | `python compartilhados/sincronizar.py --aplicar` e o mesmo sem argumento, que precisa sair 0. |

Essa validação roda completa antes do commit. Não adicione retries, locks,
backups ou serviços sem descrever a falha concreta que eles evitam e como a
suíte a reproduz.
