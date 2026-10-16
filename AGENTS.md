# Manutenção VPS — guia de trabalho

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
  transformação persistente ou alteração de backup/criptografia.
- Segredos, chaves privadas e conteúdo de backups não entram no Git nem nos
  logs de testes.

## Validação proporcional

| Mudança | Validação mínima |
| --- | --- |
| Documento ou unidade systemd | `git diff --check` e conferência de caminhos/comandos. |
| Script de deploy, backup ou vigia | A suíte Docker específica em `vps/tests/`. |
| Instalação ou inventário | Testes de `instalar.sh` e `--check` no ambiente de teste. |
| Mudança que altera dados/volumes | Teste de backup e restauração no sandbox; não use o VPS como laboratório. |

Não adicione retries, locks, backups ou serviços sem descrever a falha concreta
que eles evitam e como a suíte a reproduz.
