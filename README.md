# Manutenção da infraestrutura

Este repositório versiona a fonte da infraestrutura compartilhada do VPS. Os
arquivos que executam no servidor ficam em [`vps/`](vps/); cada aplicação
mantém seu próprio código, Compose, migrações e documentação operacional.

Editar este repositório não implanta nem altera o VPS. A instalação é um passo
deliberado e separado: [`vps/instalar.sh`](vps/instalar.sh), executado no
servidor a partir do clone local, entrega os artefatos declarados no inventário
e confere o resultado.

[`docs/TESTES.md`](docs/TESTES.md) é o texto-base das diretrizes de teste.
[`validacao/README.md`](validacao/README.md) descreve a medição reproduzível de
cobertura dos projetos locais pelos seus serviços Docker de qualidade.
[`higiene/README.md`](higiene/README.md) descreve a limpeza local de caches,
a conferência de ignores e a preservação de migrações e dados.
Repositórios que carregam uma cópia devem mantê-la alinhada; nem todos têm uma.
Para mudar uma regra, atualize o texto-base e as cópias existentes na mesma
rodada.

[`docs/contratos/`](docs/contratos/) guarda a cópia canônica do JSON Schema do
contrato `patrimonio/v4` entre o CB, o CRV e o Wealthfolio, com a lista das
cópias idênticas e quem as valida. Mesma regra: mude aqui e copie para todos.

[`docs/VERSIONAMENTO.md`](docs/VERSIONAMENTO.md) fixa a regra de versão de cada
aplicativo (SemVer por projeto, desde a primeira versão) e guarda a tabela de
releases e a correspondência com as tags antigas.

## Operação atual

| Componente | Fonte | Contrato operacional |
|---|---|---|
| Instalação da infraestrutura | [`vps/instalar.sh`](vps/instalar.sh) | Entrega no servidor todos os artefatos do inventário a partir do clone de `main`, por rename atômico e com modo explícito. Recusa checkout sujo e fonte com CR, recarrega o systemd e reinicia apenas os timers cujas unidades mudaram, e relê tudo ao final — só sai com sucesso quando o servidor espelha o checkout. `--check` responde "em dia ou à deriva" sem escrever, saindo diferente de zero quando há diferença. |
| Deploy | [`vps/deploy.sh`](vps/deploy.sh) | Só quando o usuário manda. Atualiza somente por fast-forward de `main`, monta as imagens no servidor a partir do código (sem `--pull` num deploy comum) e confirma `/health` público; não consulta a CI do GitHub, porque a validação é feita na máquina antes do commit. `--refresh` remonta a versão no ar com bases novas e nunca aplica commits. Recusa checkout sujo. Montagem que falha devolve o código sem trocar contêineres; falha depois de subir aciona rollback automático de código e imagem. O último SHA saudável é gravado atomicamente em `/home/ubuntu/.local/state/mspa-deploy/`. Um lock por aplicação serializa deploy e o snapshot do volume rotulado, sem bloquear apps diferentes. |
| Limite do rollback | [`vps/deploy.sh`](vps/deploy.sh) | Migrações e dados não são revertidos automaticamente. Deploy com mudança de schema exige backup verificado, compatibilidade retroativa ou procedimento manual de reversão. |
| Backup dos bancos, volumes, sites e configuração | [`vps/backup-db.sh`](vps/backup-db.sh), [`vps/backup-db.service`](vps/backup-db.service), [`vps/backup-db.timer`](vps/backup-db.timer) | **Sites (desde 25/10/2026):** tudo o que o nginx publica nesta máquina é descoberto dos vhosts habilitados — a pasta de `root`/`alias`, ou a pasta do Compose do contêiner que publica a porta de um `proxy_pass` — e copiado em `site_<pasta>`, sem segredos (`.env*`, `.secrets/`, `*.key`, `*.pem`), Git, dependências e caches; site que sai do nginx é aviso, não falha. **Configuração** (`configuracao_servidor`): vhosts e demais arquivos do nginx, unidades do systemd, renovação do certbot, fail2ban, sshd, iptables, sudoers, cron e `~/.ssh/config`/`authorized_keys`, com um `INVENTARIO.txt` que diz domínio, pasta, repositório e commit de cada site, contêineres, timers, pacotes, os nomes dos segredos que ficaram de fora e um roteiro de reconstrução. As duas cópias só são gravadas quando mudam. Máquina sem banco nenhum é normal; Docker que não responde é erro. Descobre os bancos pelos contêineres `postgres:*` e `mspa-postgres:*` rodando nesta máquina (a segunda é a imagem compartilhada da frota), produz dumps PostgreSQL em formato custom, relê com `pg_restore --list`, publica por troca atômica, grava SHA-256 e aplica retenção sem remover o dump mais recente. Contêiner com o rótulo `mspa.backup.volume=<caminho>` (hoje, o Wealthfolio e o SQLite dele) tem o diretório copiado em `.tar.gz` com o contêiner pausado por segundos, relido com `gzip -t` e `tar`, e só gravado quando difere da última cópia. Banco ou volume com histórico em disco que não está mais de pé é acusado. Só conta como backup o nome que o script produz (`<slug>_banco_<carimbo>.dump` e `<slug>_volume_<carimbo>.tar.gz`). **Dump manual mora em `~/backups-arquivados/`**, nunca em `~/backups`: lá ele não vira histórico nem entra na retenção, e o vigia acusa a pasta sem marcador. O timer agenda o ciclo diário. |
| Acesso ao backup | [`vps/backup-agent.sh`](vps/backup-agent.sh) | Agente SSH preso por `command=` a quatro verbos: listar, enviar, apagar e consultar estado. Não oferece shell, restringe caminhos aos projetos que têm pasta em `~/backups` e nunca permite apagar o dump (ou a cópia de volume) mais recente. `listar` mostra só os dumps, que é o que o BackupRestore até a versão sem volumes entende; `listar tudo` inclui as cópias de volume. Os dois só anunciam os nomes que o `backup-db.sh` produz, os mesmos que `enviar` aceita: em 10/10/2026 um dump manual na listagem fez o BackupRestore recusar a sincronização de todos os projetos. Cada listagem grava `~/backups/.ultima_busca`: é o batimento da cópia fora do servidor, que o vigia confere. |
| Alerta | [`vps/alerta.sh`](vps/alerta.sh), [`vps/alerta@.service`](vps/alerta@.service), [`vps/certbot.service.d/alerta.conf`](vps/certbot.service.d/alerta.conf) | Envia falhas ao Telegram, inclui logs de unidades systemd e suprime repetições. O título leva o nome curto da máquina (`[VPS1]`, `[VPS2]`) em vez do hostname da Oracle. O notificador sempre termina com sucesso para não criar cascata de falhas. |
| Recarga após renovar o certificado | [`vps/certbot-recarregar-nginx.sh`](vps/certbot-recarregar-nginx.sh) | Hook de `deploy` do certbot: valida com `nginx -t` e recarrega o nginx depois de uma renovação. Sem ele o certificado renova em disco e o nginx segue apresentando o antigo — sem nada falhar, porque renovar deu certo. |
| Vigia | [`vps/vigia.sh`](vps/vigia.sh), [`vps/vigia.service`](vps/vigia.service), [`vps/vigia.timer`](vps/vigia.timer) | Verifica disco, `/health` público, certificados, frescor dos backups e se a cópia fora do servidor os buscou nas últimas 72 h; alerta condições persistentes. Também o **frescor dos dados**, que o `/health` não vê: a idade da série diária e da cotação ao vivo do CRV (lidas pelo esquema `leitura` do banco dele) e, nos logs do Wealthfolio, o batimento da sincronização de cotações e as falhas em série da importação do CB/CRV. Fica fora do `/health` de propósito, porque a autocura reinicia contêiner `unhealthy` e uma cotação velha reiniciaria o CRV sem motivo. Os domínios saem dos vhosts habilitados nesta máquina, então cada servidor vigia o que ele mesmo serve — e um vigia sem nenhum domínio alerta a própria cegueira. |
| Bot de status (Telegram) | [`vps/telegram-bot-status.py`](vps/telegram-bot-status.py), [`vps/telegram-bot-status.service`](vps/telegram-bot-status.service), [`vps/status-coletor.py`](vps/status-coletor.py) | Menu `/status` com botões (contêineres, VPS, disco do Docker, backups, fail2ban, certificados, endpoints, autocura, reboot). **Menu unificado:** cada resposta traz um bloco do VPS1 e um do VPS2. O bot roda só no VPS1 (o Telegram entrega os cliques a um processo por bot; nas duas máquinas eles brigariam com HTTP 409); lê o VPS1 pelo `status-coletor.py` local e o VPS2 pelo mesmo coletor, por SSH no Tailscale, com a chave `~/.ssh/status-agente` presa por `restrict,from="100.94.82.91",command="/home/ubuntu/status-coletor.py"` no `authorized_keys` do VPS2. O coletor só lê e só aceita as categorias da lista; os domínios vêm dos vhosts do nginx. O instalador instala nas duas máquinas, mas só reinicia o bot onde ele já está rodando. |
| Sentinela de erro de aplicação | [`vps/sentinela.sh`](vps/sentinela.sh), [`vps/sentinela.service`](vps/sentinela.service), [`vps/sentinela.timer`](vps/sentinela.timer) | Lê a cada cinco minutos o log que o nginx escreve **só** com respostas 5xx, agrupa por host e alerta. Cobre a quebra que o `/health` não vê: rota que devolve 500 com o banco saudável, worker morto (502) e requisição estourada (504). Lê de forma incremental por inode, tamanho e assinatura do prefixo; se não conseguir ler o log, alerta a própria cegueira em vez de calar. Descarta o 5xx do domínio que estava em deploy naquele momento (janela gravada pelo `deploy.sh` em `~/.local/state/mspa-deploy/janelas.log`, com 30 s de margem antes e 90 s depois): é a troca de contêiner, e o deploy que dá errado alerta por conta própria. |
| Cotações diárias do CRV | [`vps/cotacoes-diarias.sh`](vps/cotacoes-diarias.sh), [`vps/cotacoes-diarias.service`](vps/cotacoes-diarias.service), [`vps/cotacoes-diarias.timer`](vps/cotacoes-diarias.timer) | De terça a sábado, às 06:40, roda `flask import-position-history --estrito` no contêiner `web` de cada checkout em `~/apps` que traz o importador do Yahoo. Preenche os fechamentos que o agente RTD não gravou, por exemplo com o PC Windows desligado, sem sobrescrever a leitura dele. Depois, no mesmo contêiner, `flask expurgar-outbox-v4` mantém o outbox do contrato patrimônio v4 em 30 dias (só onde o comando existe), e por último `flask importar-proventos-cb --rotina` traz para o CRV os proventos que o CB já tem (só onde o comando aceita `--rotina`). Máquina sem o CRV sai com sucesso. CRV sem contêiner, sem `--estrito`, com ticker detido sem série ou com provento na fila de revisão é falha, e alerta. |
| Autocura | [`vps/autocura.sh`](vps/autocura.sh), [`vps/autocura.service`](vps/autocura.service), [`vps/autocura.timer`](vps/autocura.timer) | Reinicia contêineres `unhealthy` com teto de tentativas e alerta quando a recuperação automática não resolve. Poupa o contêiner pausado e o que não teve nenhuma sonda reprovada, que é como o Docker mostra, por segundos, o contêiner que o backup pausou para copiar o volume. |
| Limpeza do Docker | [`vps/docker-prune.sh`](vps/docker-prune.sh), [`vps/docker-prune.service`](vps/docker-prune.service), [`vps/docker-prune.timer`](vps/docker-prune.timer) | Poda semanalmente o cache de build acumulado pelos deploys; nunca toca imagem em uso por contêiner ativo. |
| Monitor externo | [`vps/uptimerobot-monitores.sh`](vps/uptimerobot-monitores.sh) | Consulta ou aplica monitores UptimeRobot do tipo keyword para os endpoints públicos `/health` dos domínios desta máquina, usando e-mail como canal independente do VPS. Cria e ajusta; nunca apaga monitor de domínio que este servidor não serve, então rodá-lo num VPS não mexe nos monitores do outro. A palavra que prova saúde vem da resposta atual do `/health`: `"ok"` com aspas nos aplicativos com JSON, `ok` no Wealthfolio e nos sites estáticos. |
| Entrada HTTP/TLS | [`vps/nginx/`](vps/nginx/) | Mantém os vhosts dos aplicativos, TLS, HSTS com uma fonte só (o vhost; o da aplicação é descartado no proxy), proxy central, gzip, rejeição de host desconhecido, limite compartilhado somente para `POST /login` e o registro separado das respostas 5xx que alimenta o sentinela. O instalador entrega os vhosts que existirem na origem e recusa origem sem nenhum. |

### Uma frota, mais de uma máquina

Nenhum script guarda a lista de quais aplicações existem. Cada um pergunta à
máquina em que está rodando: o backup descobre os bancos com imagens
`postgres:*` ou `mspa-postgres:*`, ou com o rótulo
`mspa.backup.postgres=true`, e os volumes que levam o rótulo
`mspa.backup.volume`; o vigia
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
~/deploy.sh <bancario|conforto|megasena|renda|wealthfolio>
~/deploy.sh <projeto> --refresh   # remonta a versão no ar com imagens-base novas
~/deploy.sh --status
```

Desde 20/10/2026 o fluxo é o do usuário: ele valida tudo na máquina, grava
direto no `main` do GitHub e, quando quer, manda implantar. Por isso o deploy
**não consulta a CI do GitHub** (ela ficou como aviso) e **nada muda em
produção sozinho**: não há timer que implante ou remonte apps. O
`atualizar-stacks.service` continua disponível para implantar de uma vez todos
os apps cujo `main` avançou, com um backup verificado antes (`sudo systemctl
start atualizar-stacks.service`), mas só roda quando chamado.

O deploy atualiza o checkout por fast-forward de `main`, monta as imagens ali
mesmo no servidor a partir do código (~45 s no bancário) e sobe. Um deploy
comum monta **sem** `--pull`: as imagens-base continuam as que já estavam no
servidor, e só o código muda. `--refresh` remonta a versão que já está no ar
buscando bases novas (correções de segurança do Debian/Python) e **nunca**
aplica commits novos; se o `main` estiver à frente, ele só os lista.

Se a montagem falhar, o código volta para o commit anterior e nenhum contêiner
é trocado. Se a versão nova não responder em `/health`, o deploy volta código e
imagens para o que estava no ar, sem remontar nada. Migrações de banco não são
revertidas automaticamente; deploy com mudança de schema exige backup
verificado, compatibilidade retroativa ou procedimento manual de reversão.
Cada chamada de `deploy.sh` toma um lock do respectivo aplicativo;
`backup-db.sh` toma o mesmo lock apenas enquanto pausa e copia um volume
rotulado. Assim um deploy do Wealthfolio não disputa o SQLite com seu snapshot,
mas backup e deploy dos demais aplicativos continuam independentes. Se a outra
operação não terminar em cinco minutos, a chamada termina sem tocar no app e
informa a contenção.

### Imagens por ID: bancário, renda, Mega-Sena e Conforto

Quando o commit candidato contém `compose.release.yaml`, o deploy monta as
imagens com `docker compose build`, resolve o ID da imagem do app e o do
PostgreSQL (`config --images` do serviço do app, menos a do banco) e sobe por
ID com `--no-build --pull never`. Registra `<app>.images` junto do SHA
saudável. O Wealthfolio, sem esse arquivo, sobe por `up -d --build`.

O rollback captura os IDs locais de aplicação e banco antes de tocar em nada e
gera uma override temporária também para migrate/provisionamento; não tenta
retaguear referências por digest ou por ID, nem reconstruir. O arquivo
temporário é removido ao final.

Os papéis são explícitos: `web/migrate` para CB/CRV, `app/migrate` para Mega
e `ict/coletor/schema` para Conforto. Antes do fast-forward, este último exige
snapshot recuperável tanto do ICT quanto do coletor. Cada papel restaurado
conserva seu ID anterior; `schema` usa a imagem anterior do ICT.

Só o servidor de banco declara `mspa.backup.postgres=true`; o backup o
descobre mesmo quando Config.Image é um ID local, sem depender de nomes de
projetos. A override de rollback mantém o rótulo inclusive ao restaurar um
checkout anterior à adoção dele; web/migrate/db-provision não o recebem.

O servidor é espelho de `main`: não edite nem faça commit nele. O rollback
automático devolve o checkout ao SHA anterior, restaura as imagens anteriores e
só registra o estado depois que o endpoint público confirma saúde. Mesmo
quando a reversão recupera o site, o deploy original termina com erro e o
commit defeituoso permanece em `main` até ser corrigido.

Se o image store perdeu a imagem de um banco ainda em execução, o deploy
recusa sem tocar no serviço. Não retagueie uma imagem diferente como se fosse a
antiga nem faça `docker commit` (pode incorporar estado/segredos): a
recuperação é manual, com backup restaurado e conferido antes.

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
