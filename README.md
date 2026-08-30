# Manutenção da infraestrutura

Este repositório versiona a fonte da infraestrutura compartilhada do VPS. Os
arquivos que executam no servidor ficam em [`vps/`](vps/); cada aplicação
mantém seu próprio código, Compose, migrações e documentação operacional.

Editar este repositório não implanta nem altera o VPS. A instalação é um passo
deliberado e separado: [`vps/instalar.sh`](vps/instalar.sh), executado no
servidor a partir do clone local, entrega os artefatos declarados no inventário
e confere o resultado.

## Operação atual

| Componente | Fonte | Contrato operacional |
|---|---|---|
| Instalação da infraestrutura | [`vps/instalar.sh`](vps/instalar.sh) | Entrega no servidor os 19 artefatos do inventário a partir do clone de `main`, por rename atômico e com modo explícito. Recusa checkout sujo e fonte com CR, recarrega o systemd e reinicia apenas os timers cujas unidades mudaram, e relê tudo ao final — só sai com sucesso quando o servidor espelha o checkout. `--check` responde "em dia ou à deriva" sem escrever, saindo diferente de zero quando há diferença. |
| Deploy | [`vps/deploy.sh`](vps/deploy.sh) | Atualiza somente por fast-forward de `main`, recusa checkout sujo, reconstrói com Compose e confirma `/health` público. Falha após atualizar aciona rollback automático de código e imagem. O último SHA saudável é gravado atomicamente em `/home/ubuntu/.local/state/mspa-deploy/`. |
| Limite do rollback | [`vps/deploy.sh`](vps/deploy.sh) | Migrações e dados não são revertidos automaticamente. Deploy com mudança de schema exige backup verificado, compatibilidade retroativa ou procedimento manual de reversão. |
| Backup dos bancos | [`vps/backup-db.sh`](vps/backup-db.sh), [`vps/backup-db.service`](vps/backup-db.service), [`vps/backup-db.timer`](vps/backup-db.timer) | Produz dumps PostgreSQL em formato custom, relê com `pg_restore --list`, publica por troca atômica, grava SHA-256 e aplica retenção sem remover o dump mais recente. O timer agenda o ciclo diário. |
| Acesso ao backup | [`vps/backup-agent.sh`](vps/backup-agent.sh) | Agente SSH preso por `command=` a quatro verbos: listar, enviar, apagar e consultar estado. Não oferece shell, restringe projetos/caminhos e nunca permite apagar o dump mais recente. |
| Alerta | [`vps/alerta.sh`](vps/alerta.sh), [`vps/alerta@.service`](vps/alerta@.service), [`vps/certbot.service.d/alerta.conf`](vps/certbot.service.d/alerta.conf) | Envia falhas ao Telegram, inclui logs de unidades systemd e suprime repetições. O notificador sempre termina com sucesso para não criar cascata de falhas. |
| Vigia | [`vps/vigia.sh`](vps/vigia.sh), [`vps/vigia.service`](vps/vigia.service), [`vps/vigia.timer`](vps/vigia.timer) | Verifica disco, `/health` público, certificados e frescor dos backups; alerta condições persistentes. |
| Autocura | [`vps/autocura.sh`](vps/autocura.sh), [`vps/autocura.service`](vps/autocura.service), [`vps/autocura.timer`](vps/autocura.timer) | Reinicia contêineres `unhealthy` com teto de tentativas e alerta quando a recuperação automática não resolve. |
| Limpeza do Docker | [`vps/docker-prune.sh`](vps/docker-prune.sh), [`vps/docker-prune.service`](vps/docker-prune.service), [`vps/docker-prune.timer`](vps/docker-prune.timer) | Poda semanalmente o cache de build acumulado pelos deploys; nunca toca imagem em uso por contêiner ativo. |
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

## Instalação da infraestrutura

O servidor mantém um clone deste repositório em `~/manutencao`, com chave de
deploy própria (`github-manutencao` no `~/.ssh/config`) — mesmo padrão dos
quatro aplicativos. A interface é:

```bash
cd ~/manutencao && git pull --ff-only
./vps/instalar.sh --check   # o que está diferente, sem escrever
./vps/instalar.sh           # instala e confere
```

`--check` sai diferente de zero quando há deriva, para que uma verificação
periódica consiga distinguir "em dia" de "à deriva" sem interpretar texto.

**Por que isto existe.** Até 30/08/2026 os artefatos chegavam ao servidor por
cópia manual, e não havia nada garantindo que o instalado fosse o versionado.
Uma comparação arquivo a arquivo mostrou o `deploy.sh` do servidor 160 linhas
de código atrás — sem o registro do último SHA saudável que a tabela acima já
descrevia como se existisse, e sem as variáveis de ambiente pelas quais
`tests/deploy_test.sh` dirige o script. **A suíte do deploy validava um arquivo
que não era o que rodaria num incidente.** Os demais artefatos coincidiam por
sorte: ninguém tinha mexido no código deles desde a cópia.

Teste hermético do instalador, sem rede nem acesso ao VPS:

```powershell
docker run --rm -v "${PWD}:/repo:ro" bash:5.2 bash /repo/vps/tests/instalar_test.sh
```

O Nginx fica fora do inventário de conteúdo de propósito: tem instalador
próprio, [`vps/nginx/instalar.sh`](vps/nginx/instalar.sh), que salva a
configuração atual, executa `nginx -t`, restaura o backup se a validação falhar
e só então recarrega o serviço. O `instalar.sh` apenas o entrega em
`~/instalar-nginx.sh`; o procedimento continua em
[`vps/nginx/README.md`](vps/nginx/README.md).

## Observabilidade

Depois de instalar, confira estado das unidades e logs no `journalctl`. O
`vigia.timer` verifica disco, `/health` público, certificados e frescor dos
backups; o `autocura.timer` reinicia contêiner `unhealthy` com teto de
tentativas.

## Segredos

Tokens, senhas, chaves e arquivos de autenticação não pertencem ao Git. Os
scripts leem credenciais dos arquivos protegidos que indicam no VPS; este
repositório contém apenas o contrato e a configuração sem valores secretos.
