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
| Instalação da infraestrutura | [`vps/instalar.sh`](vps/instalar.sh) | Entrega no servidor os 26 artefatos do inventário a partir do clone de `main`, por rename atômico e com modo explícito. Recusa checkout sujo e fonte com CR, recarrega o systemd e reinicia apenas os timers cujas unidades mudaram, e relê tudo ao final — só sai com sucesso quando o servidor espelha o checkout. `--check` responde "em dia ou à deriva" sem escrever, saindo diferente de zero quando há diferença. |
| Deploy | [`vps/deploy.sh`](vps/deploy.sh) | Atualiza somente por fast-forward de `main`, recusa checkout sujo, reconstrói com Compose e confirma `/health` público. Falha após atualizar aciona rollback automático de código e imagem. O último SHA saudável é gravado atomicamente em `/home/ubuntu/.local/state/mspa-deploy/`. |
| Limite do rollback | [`vps/deploy.sh`](vps/deploy.sh) | Migrações e dados não são revertidos automaticamente. Deploy com mudança de schema exige backup verificado, compatibilidade retroativa ou procedimento manual de reversão. |
| Backup dos bancos | [`vps/backup-db.sh`](vps/backup-db.sh), [`vps/backup-db.service`](vps/backup-db.service), [`vps/backup-db.timer`](vps/backup-db.timer) | Descobre os bancos pelos contêineres `postgres:*` rodando nesta máquina, produz dumps PostgreSQL em formato custom, relê com `pg_restore --list`, publica por troca atômica, grava SHA-256 e aplica retenção sem remover o dump mais recente. Descoberta vazia é erro, e banco com histórico em disco que não está mais de pé é acusado. O timer agenda o ciclo diário. |
| Acesso ao backup | [`vps/backup-agent.sh`](vps/backup-agent.sh) | Agente SSH preso por `command=` a quatro verbos: listar, enviar, apagar e consultar estado. Não oferece shell, restringe caminhos aos projetos que têm pasta em `~/backups` e nunca permite apagar o dump mais recente. Cada `listar` grava `~/backups/.ultima_busca`: é o batimento da cópia fora do servidor, que o vigia confere. |
| Alerta | [`vps/alerta.sh`](vps/alerta.sh), [`vps/alerta@.service`](vps/alerta@.service), [`vps/certbot.service.d/alerta.conf`](vps/certbot.service.d/alerta.conf) | Envia falhas ao Telegram, inclui logs de unidades systemd e suprime repetições. O notificador sempre termina com sucesso para não criar cascata de falhas. |
| Recarga após renovar o certificado | [`vps/certbot-recarregar-nginx.sh`](vps/certbot-recarregar-nginx.sh) | Hook de `deploy` do certbot: valida com `nginx -t` e recarrega o nginx depois de uma renovação. Sem ele o certificado renova em disco e o nginx segue apresentando o antigo — sem nada falhar, porque renovar deu certo. |
| Vigia | [`vps/vigia.sh`](vps/vigia.sh), [`vps/vigia.service`](vps/vigia.service), [`vps/vigia.timer`](vps/vigia.timer) | Verifica disco, `/health` público, certificados, frescor dos backups e se a cópia fora do servidor os buscou nas últimas 72 h; alerta condições persistentes. Os domínios saem dos vhosts habilitados nesta máquina, então cada servidor vigia o que ele mesmo serve — e um vigia sem nenhum domínio alerta a própria cegueira. |
| Sentinela de erro de aplicação | [`vps/sentinela.sh`](vps/sentinela.sh), [`vps/sentinela.service`](vps/sentinela.service), [`vps/sentinela.timer`](vps/sentinela.timer) | Lê a cada cinco minutos o log que o nginx escreve **só** com respostas 5xx, agrupa por host e alerta. Cobre a quebra que o `/health` não vê: rota que devolve 500 com o banco saudável, worker morto (502) e requisição estourada (504). Lê de forma incremental por inode, tamanho e assinatura do prefixo; se não conseguir ler o log, alerta a própria cegueira em vez de calar. |
| Retenção de contatos | [`vps/expurgo-contatos.sh`](vps/expurgo-contatos.sh), [`vps/expurgo-contatos.service`](vps/expurgo-contatos.service), [`vps/expurgo-contatos.timer`](vps/expurgo-contatos.timer) | Roda uma vez por dia `manage.py expurgar_contatos` no contêiner `web` de cada checkout em `~/apps` que traz o comando, cumprindo o prazo de retenção que o aviso de privacidade do portal publica. Máquina sem o portal sai com sucesso; portal presente sem contêiner para rodar o expurgo é falha, e alerta. |
| Autocura | [`vps/autocura.sh`](vps/autocura.sh), [`vps/autocura.service`](vps/autocura.service), [`vps/autocura.timer`](vps/autocura.timer) | Reinicia contêineres `unhealthy` com teto de tentativas e alerta quando a recuperação automática não resolve. |
| Limpeza do Docker | [`vps/docker-prune.sh`](vps/docker-prune.sh), [`vps/docker-prune.service`](vps/docker-prune.service), [`vps/docker-prune.timer`](vps/docker-prune.timer) | Poda semanalmente o cache de build acumulado pelos deploys; nunca toca imagem em uso por contêiner ativo. |
| Monitor externo | [`vps/uptimerobot-monitores.sh`](vps/uptimerobot-monitores.sh) | Consulta ou aplica monitores UptimeRobot do tipo keyword para os endpoints públicos `/health` dos domínios desta máquina, usando e-mail como canal independente do VPS. Cria e ajusta; nunca apaga monitor de domínio que este servidor não serve, então rodá-lo num VPS não mexe nos monitores do outro. |
| Entrada HTTP/TLS | [`vps/nginx/`](vps/nginx/) | Mantém os vhosts dos aplicativos, TLS, HSTS com uma fonte só (o vhost; o da aplicação é descartado no proxy), proxy central, gzip, rejeição de host desconhecido, limite compartilhado somente para `POST /login` e o registro separado das respostas 5xx que alimenta o sentinela. O instalador entrega os vhosts que existirem na origem e recusa origem sem nenhum. |

### Uma frota, mais de uma máquina

Nenhum script guarda a lista de quais aplicações existem. Cada um pergunta à
máquina em que está rodando: o backup olha os contêineres `postgres:*`, o vigia
e o monitor externo leem os `server_name` dos vhosts habilitados, o agente de
backup olha as pastas de `~/backups`, e o instalador do nginx instala os vhosts
que encontrar na origem.

Isso existe porque a alternativa foi testada e falhou. Havia cinco listas
escritas à mão respondendo à mesma pergunta, e em 10/09/2026 o portal entrou na
frota, foi acrescentado a uma delas e não à do `backup-agent.sh`: por três dias
o dump do portal foi produzido todo dia e nenhum podia ser baixado, sem nada
acusar. Com um segundo servidor, cada uma dessas listas passaria a descrever,
em parte, a outra máquina.

Em troca, cada descoberta precisa acusar o vazio em voz alta — "não encontrei
banco nenhum" nunca pode sair como sucesso. É o que as guardas de cada script
fazem, e o que [`vps/tests/backup-db_test.sh`](vps/tests/backup-db_test.sh)
verifica.

## Deploy

No VPS, a interface é:

```bash
~/deploy.sh <bancario|conforto|megasena|renda|portal> --check
~/deploy.sh <bancario|conforto|megasena|renda|portal>
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
aplicativos. A interface é:

```bash
cd ~/manutencao && git pull --ff-only
bash vps/instalar.sh --check   # o que está diferente, sem escrever
bash vps/instalar.sh           # instala e confere
```

`--check` sai diferente de zero quando há deriva, para que uma verificação
periódica consiga distinguir "em dia" de "à deriva" sem interpretar texto.

O instalador existe para que o servidor rode exatamente o que está versionado:
sem ele, a suíte do deploy validaria um arquivo que não é o que roda num
incidente.

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
