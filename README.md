# Manutenção da infraestrutura

Este repositório versiona a fonte da infraestrutura compartilhada do VPS. Os
arquivos que executam no servidor ficam em [`vps/`](vps/); cada aplicação
mantém seu próprio código, Compose, migrações e documentação operacional.

Editar este repositório não implanta nem altera o VPS. A instalação exige
copiar deliberadamente o artefato para o destino indicado, validar a cópia e
executar o procedimento correspondente no servidor.

## Operação atual

| Componente | Fonte | Contrato operacional |
|---|---|---|
| Deploy | [`vps/deploy.sh`](vps/deploy.sh) | Atualiza somente por fast-forward de `main`, recusa checkout sujo, reconstrói com Compose e confirma `/health` público. Falha após atualizar aciona rollback automático de código e imagem. O último SHA saudável é gravado atomicamente em `/home/ubuntu/.local/state/mspa-deploy/`. |
| Limite do rollback | [`vps/deploy.sh`](vps/deploy.sh) | Migrações e dados não são revertidos automaticamente. Deploy com mudança de schema exige backup verificado, compatibilidade retroativa ou procedimento manual de reversão. |
| Backup dos bancos | [`vps/backup-db.sh`](vps/backup-db.sh), [`vps/backup-db.service`](vps/backup-db.service), [`vps/backup-db.timer`](vps/backup-db.timer) | Produz dumps PostgreSQL em formato custom, relê com `pg_restore --list`, publica por troca atômica, grava SHA-256 e aplica retenção sem remover o dump mais recente. O timer agenda o ciclo diário. |
| Acesso ao backup | [`vps/backup-agent.sh`](vps/backup-agent.sh) | Agente SSH preso por `command=` a quatro verbos: listar, enviar, apagar e consultar estado. Não oferece shell, restringe projetos/caminhos e nunca permite apagar o dump mais recente. |
| Alerta | [`vps/alerta.sh`](vps/alerta.sh), [`vps/alerta@.service`](vps/alerta@.service), [`vps/certbot.service.d/alerta.conf`](vps/certbot.service.d/alerta.conf) | Envia falhas ao Telegram, inclui logs de unidades systemd e suprime repetições. O notificador sempre termina com sucesso para não criar cascata de falhas. |
| Vigia | [`vps/vigia.sh`](vps/vigia.sh), [`vps/vigia.service`](vps/vigia.service), [`vps/vigia.timer`](vps/vigia.timer) | Verifica disco, `/health` público, certificados e frescor dos backups; alerta condições persistentes. |
| Autocura | [`vps/autocura.sh`](vps/autocura.sh), [`vps/autocura.service`](vps/autocura.service), [`vps/autocura.timer`](vps/autocura.timer) | Reinicia contêineres `unhealthy` com teto de tentativas e alerta quando a recuperação automática não resolve. |
| Monitor externo | [`vps/uptimerobot-monitores.sh`](vps/uptimerobot-monitores.sh) | Consulta ou aplica monitores UptimeRobot do tipo keyword para os quatro endpoints públicos `/health`, usando e-mail como canal independente do VPS. |
| Entrada HTTP/TLS | [`vps/nginx/`](vps/nginx/) | Mantém os quatro vhosts, TLS/HSTS, proxy central, gzip, rejeição de host desconhecido e limite compartilhado somente para `POST /login`. |

## Deploy

No VPS, a interface é:

```bash
~/deploy.sh <bancario|conforto|megasena|renda> --check
~/deploy.sh <bancario|conforto|megasena|renda>
~/deploy.sh --status
```

O servidor é espelho de `main`: não edite nem faça commit nele. O rollback
automático devolve o checkout ao SHA anterior, reconstrói a imagem e só registra
o estado depois que o endpoint público confirma saúde. Mesmo quando a reversão
recupera o site, o deploy original termina com erro e o commit defeituoso
permanece em `main` até ser corrigido.

Teste hermético do fluxo, sem rede ou acesso ao VPS:

```powershell
docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/deploy_test.sh
```

## Instalação e observabilidade

Os scripts e unidades declaram no próprio arquivo o destino esperado no VPS.
Copiar uma nova versão não habilita timers nem recarrega serviços por si só.
Após instalação deliberada, confira permissões, sintaxe, estado das unidades e
logs no `journalctl` antes de considerar a operação concluída.

Para Nginx, siga o procedimento de [`vps/nginx/README.md`](vps/nginx/README.md).
O instalador salva a configuração atual, executa `nginx -t`, restaura o backup
se a validação falhar e só então recarrega o serviço.

## Segredos

Tokens, senhas, chaves e arquivos de autenticação não pertencem ao Git. Os
scripts leem credenciais dos arquivos protegidos que indicam no VPS; este
repositório contém apenas o contrato e a configuração sem valores secretos.
