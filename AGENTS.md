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

O conjunto completo (todas as suítes de `vps/tests/`, ShellCheck e Nginx) não
roda mais na máquina antes do PR: o job `Qualidade` da CI do PR executa
exatamente esses passos. Localmente, rode só a suíte do que mudou, e o conjunto
completo apenas para reproduzir uma falha da CI.

O `main` é protegido: toda mudança entra por PR com squash merge, histórico
linear e os checks `Qualidade` e `CodeQL` verdes. A branch não precisa estar
atualizada em relação ao `main`; não faça merge do `main` nela só para o PR
entrar. O auto-merge está ligado: depois de `gh pr create`, rode
`gh pr merge <n> --auto --squash`, e o PR entra sozinho quando os checks
passarem. Nunca `--admin`, nunca push forçado, nunca rebase em branch
publicada.

Não adicione retries, locks, backups ou serviços sem descrever a falha concreta
que eles evitam e como a suíte a reproduz.
