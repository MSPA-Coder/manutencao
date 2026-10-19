# Manutenção da infraestrutura

Este repositório versiona a fonte da infraestrutura compartilhada do VPS. Os
arquivos que executam no servidor ficam em [`vps/`](vps/); cada aplicação
mantém seu próprio código, Compose, migrações e documentação operacional.

Editar este repositório não implanta nem altera o VPS. A instalação é um passo
deliberado e separado: [`vps/instalar.sh`](vps/instalar.sh), executado no
servidor a partir do clone local, entrega os artefatos declarados no inventário
e confere o resultado.

[`docs/TESTES.md`](docs/TESTES.md) é o texto-base das diretrizes de teste.
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
| Instalação da infraestrutura | [`vps/instalar.sh`](vps/instalar.sh) | Entrega no servidor os 33 artefatos do inventário a partir do clone de `main`, por rename atômico e com modo explícito. Recusa checkout sujo e fonte com CR, recarrega o systemd e reinicia apenas os timers cujas unidades mudaram, e relê tudo ao final — só sai com sucesso quando o servidor espelha o checkout. `--check` responde "em dia ou à deriva" sem escrever, saindo diferente de zero quando há diferença. |
| Deploy | [`vps/deploy.sh`](vps/deploy.sh) | Atualiza somente por fast-forward de `main` e só depois de todos os check-runs de produto/segurança terminarem verdes no GitHub (nos repositórios públicos), com os grupos de teste esperados presentes. No Wealthfolio, a CI do add-on é exigida no commit candidato; a suíte de imagem é exigida no último commit que mudou Dockerfile/patches, pois o workflow tem filtro de caminhos. Checks auxiliares do Dependabot não testam o app e são excluídos. Recusa checkout sujo, reconstrói com Compose e confirma `/health` público. Falha após atualizar aciona rollback automático de código e imagem. O último SHA saudável é gravado atomicamente em `/home/ubuntu/.local/state/mspa-deploy/`. Um lock por aplicação serializa deploy manual/timer e o snapshot do volume rotulado, sem bloquear apps diferentes. |
| Limite do rollback | [`vps/deploy.sh`](vps/deploy.sh) | Migrações e dados não são revertidos automaticamente. Deploy com mudança de schema exige backup verificado, compatibilidade retroativa ou procedimento manual de reversão. |
| Backup dos bancos e volumes | [`vps/backup-db.sh`](vps/backup-db.sh), [`vps/backup-db.service`](vps/backup-db.service), [`vps/backup-db.timer`](vps/backup-db.timer) | Descobre os bancos pelos contêineres `postgres:*` e `mspa-postgres:*` rodando nesta máquina (a segunda é a imagem compartilhada da frota), produz dumps PostgreSQL em formato custom, relê com `pg_restore --list`, publica por troca atômica, grava SHA-256 e aplica retenção sem remover o dump mais recente. Contêiner com o rótulo `mspa.backup.volume=<caminho>` (hoje, o Wealthfolio e o SQLite dele) tem o diretório copiado em `.tar.gz` com o contêiner pausado por segundos, relido com `gzip -t` e `tar`, e só gravado quando difere da última cópia. Descoberta vazia de bancos é erro, e banco ou volume com histórico em disco que não está mais de pé é acusado. Só conta como backup o nome que o script produz (`<slug>_banco_<carimbo>.dump` e `<slug>_volume_<carimbo>.tar.gz`). **Dump manual mora em `~/backups-arquivados/`**, nunca em `~/backups`: lá ele não vira histórico nem entra na retenção, e o vigia acusa a pasta sem marcador. O timer agenda o ciclo diário. |
| Acesso ao backup | [`vps/backup-agent.sh`](vps/backup-agent.sh) | Agente SSH preso por `command=` a quatro verbos: listar, enviar, apagar e consultar estado. Não oferece shell, restringe caminhos aos projetos que têm pasta em `~/backups` e nunca permite apagar o dump (ou a cópia de volume) mais recente. `listar` mostra só os dumps, que é o que o BackupRestore até a versão sem volumes entende; `listar tudo` inclui as cópias de volume. Os dois só anunciam os nomes que o `backup-db.sh` produz, os mesmos que `enviar` aceita: em 10/10/2026 um dump manual na listagem fez o BackupRestore recusar a sincronização de todos os projetos. Cada listagem grava `~/backups/.ultima_busca`: é o batimento da cópia fora do servidor, que o vigia confere. |
| Alerta | [`vps/alerta.sh`](vps/alerta.sh), [`vps/alerta@.service`](vps/alerta@.service), [`vps/certbot.service.d/alerta.conf`](vps/certbot.service.d/alerta.conf) | Envia falhas ao Telegram, inclui logs de unidades systemd e suprime repetições. O notificador sempre termina com sucesso para não criar cascata de falhas. |
| Recarga após renovar o certificado | [`vps/certbot-recarregar-nginx.sh`](vps/certbot-recarregar-nginx.sh) | Hook de `deploy` do certbot: valida com `nginx -t` e recarrega o nginx depois de uma renovação. Sem ele o certificado renova em disco e o nginx segue apresentando o antigo — sem nada falhar, porque renovar deu certo. |
| Vigia | [`vps/vigia.sh`](vps/vigia.sh), [`vps/vigia.service`](vps/vigia.service), [`vps/vigia.timer`](vps/vigia.timer) | Verifica disco, `/health` público, certificados, frescor dos backups e se a cópia fora do servidor os buscou nas últimas 72 h; alerta condições persistentes. Também o **frescor dos dados**, que o `/health` não vê: a idade da série diária e da cotação ao vivo do CRV (lidas pelo esquema `leitura` do banco dele) e, nos logs do Wealthfolio, o batimento da sincronização de cotações e as falhas em série da importação do CB/CRV. Fica fora do `/health` de propósito, porque a autocura reinicia contêiner `unhealthy` e uma cotação velha reiniciaria o CRV sem motivo. Os domínios saem dos vhosts habilitados nesta máquina, então cada servidor vigia o que ele mesmo serve — e um vigia sem nenhum domínio alerta a própria cegueira. |
| Sentinela de erro de aplicação | [`vps/sentinela.sh`](vps/sentinela.sh), [`vps/sentinela.service`](vps/sentinela.service), [`vps/sentinela.timer`](vps/sentinela.timer) | Lê a cada cinco minutos o log que o nginx escreve **só** com respostas 5xx, agrupa por host e alerta. Cobre a quebra que o `/health` não vê: rota que devolve 500 com o banco saudável, worker morto (502) e requisição estourada (504). Lê de forma incremental por inode, tamanho e assinatura do prefixo; se não conseguir ler o log, alerta a própria cegueira em vez de calar. |
| Cotações diárias do CRV | [`vps/cotacoes-diarias.sh`](vps/cotacoes-diarias.sh), [`vps/cotacoes-diarias.service`](vps/cotacoes-diarias.service), [`vps/cotacoes-diarias.timer`](vps/cotacoes-diarias.timer) | De terça a sábado, às 06:40, roda `flask import-position-history --estrito` no contêiner `web` de cada checkout em `~/apps` que traz o importador do Yahoo. Preenche os fechamentos que o agente RTD não gravou, por exemplo com o PC Windows desligado, sem sobrescrever a leitura dele. Depois, no mesmo contêiner, `flask expurgar-outbox-v4` mantém o outbox do contrato patrimônio v4 em 30 dias (só onde o comando existe). Máquina sem o CRV sai com sucesso. CRV sem contêiner, sem `--estrito` ou com ticker detido sem série é falha, e alerta. |
| Autocura | [`vps/autocura.sh`](vps/autocura.sh), [`vps/autocura.service`](vps/autocura.service), [`vps/autocura.timer`](vps/autocura.timer) | Reinicia contêineres `unhealthy` com teto de tentativas e alerta quando a recuperação automática não resolve. Poupa o contêiner pausado e o que não teve nenhuma sonda reprovada, que é como o Docker mostra, por segundos, o contêiner que o backup pausou para copiar o volume. |
| Limpeza do Docker | [`vps/docker-prune.sh`](vps/docker-prune.sh), [`vps/docker-prune.service`](vps/docker-prune.service), [`vps/docker-prune.timer`](vps/docker-prune.timer) | Poda semanalmente o cache de build acumulado pelos deploys; nunca toca imagem em uso por contêiner ativo. |
| Monitor externo | [`vps/uptimerobot-monitores.sh`](vps/uptimerobot-monitores.sh) | Consulta ou aplica monitores UptimeRobot do tipo keyword para os endpoints públicos `/health` dos domínios desta máquina, usando e-mail como canal independente do VPS. Cria e ajusta; nunca apaga monitor de domínio que este servidor não serve, então rodá-lo num VPS não mexe nos monitores do outro. |
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
~/deploy.sh <projeto> --sem-ci   # emergência: implanta sem CI verde e alerta
~/deploy.sh --status
```

Antes do fast-forward, o deploy pergunta à API do GitHub se os check-runs de
produto e segurança do commit novo terminaram verdes (`neutral` e `skipped`
contam como verdes) e se os grupos de teste do aplicativo estão presentes.
Checks auxiliares do Dependabot são ignorados porque não
validam o código que será implantado. No Wealthfolio, o teste do add-on precisa
estar verde no commit candidato e a suíte lenta da imagem precisa estar verde
no commit mais recente que alterou Dockerfile, `.dockerignore`, `patches/` ou
o próprio workflow da imagem. Assim, um commit posterior só do add-on não
precisa repetir meia hora de testes do upstream; o gate ainda valida ambos os
componentes e recusa se qualquer execução relevante estiver ausente, pendente,
vermelha ou se a API não responder. O Wealthfolio agora é público e usa o
mesmo gate. O portal saiu da frota em 19/10/2026 (virou site estático, entregue
a um cliente). `--sem-ci` existe para quando a API estiver fora
justo na hora de um conserto, e avisa pelo alerta.

O `atualizar-stacks.timer` verifica commits diariamente às 12:00 UTC. Quando
algum `main` avança, valida o backup completo com `backup-db.sh --forcar` e
chama o `deploy.sh` em série para cada app; cada deploy exige CI verde e
confirma `/health` público. O `reconstruir-bases.timer` faz o mesmo a cada
quarta-feira, para reconstruir as tags móveis das imagens-base mesmo sem
mudança de código. Se uma imagem nova falhar, o deploy restaura os IDs exatos
que estavam no ar, sem rebuild durante o rollback. Migrações de banco não são
revertidas automaticamente; por isso o backup validado é obrigatório antes de
qualquer reconstrução automática. Cada chamada de `deploy.sh` toma um lock do
respectivo aplicativo; `backup-db.sh` toma o mesmo lock apenas enquanto pausa e
copia um volume rotulado. Assim um deploy do Wealthfolio não disputa o SQLite
com seu snapshot, mas backup e deploy dos demais aplicativos continuam
independentes. Se a outra operação não terminar em cinco minutos, a chamada
termina sem tocar no app e informa a contenção.

### Imagens validadas: bancário, renda, Mega-Sena e Conforto

Quando o commit candidato contém `compose.release.yaml`, estes quatro apps
não são reconstruídos no VPS. O deploy consulta o run completo `CI`
bem-sucedido de `main`, no SHA exato, e baixa as tags
`run-<run_id>-<tentativa>` do GHCR (aplicação e PostgreSQL). Confere os
labels de revisão/run da aplicação **e do PostgreSQL** e resolve os dois digests antes de tocar
código ou contêineres. Confere também SO/arquitetura das duas imagens contra
o daemon Docker e a disponibilidade dos IDs locais do snapshot de rollback;
qualquer incompatibilidade/ID ausente recusa antes do fast-forward e da subida.
A subida usa `--no-build --pull never`; registra
`<app>.images` junto do SHA saudável.

A CI semanal fornece a nova base testada; `--refresh` a baixa mesmo sem
novo commit. Os demais apps mantêm seu caminho anterior. Uma imagem
indisponível, inclusive por falta de acesso a pacote privado, aborta sem
alterar o app. `--sem-ci` não contorna a identidade do artefato.

Rollout: instalar esta versão da infraestrutura **antes** dos commits de
aplicativo que acrescentam `compose.release.yaml`; aguardar a CI de
`main` publicar as duas imagens e confirmar acesso do VPS aos dois pacotes.
O GHCR cria pacotes privados por padrão: definir explicitamente a visibilidade
ou provisionar leitura pelo mecanismo de credenciais Docker, sem tokens nos
scripts/Git. Não atualizar aplicações pelo comando Compose de build neste
caminho. Repositórios/pacotes: `sistema-financeiro[-postgres]` e
`controlerendavariavel[-postgres]`, `mega-sena[-postgres]` e
`conforto-termico[-postgres]`, sob `ghcr.io/mspa-coder`.

No Mega-Sena e no Conforto, `Qualidade` reúne domínio, tipos, Chromium e
scanners. `Runtime contracts` recebe as mesmas candidatas nativas ARM64 como
artefatos, sem rebuild, e testa smoke/papel restrito. Publicação depende dos
dois jobs. O check obrigatório do Conforto permanece preservado.

O rollback captura os IDs locais de aplicação e banco e gera uma override temporária
também para migrate/provisionamento; não tenta retaguear referências
`@sha256`, buscar outra tag ou reconstruir. O arquivo temporário é removido
ao final. Migrações/dados continuam sem reversão automática.

Os papéis são explícitos: `web/migrate` para CB/CRV, `app/migrate` para Mega
e `ict/coletor/schema` para Conforto. Antes do fast-forward, este último exige
snapshot recuperável tanto do ICT quanto do coletor. Cada papel restaurado
conserva seu ID anterior; `schema` usa a imagem anterior do ICT.

Só o servidor de banco declara `mspa.backup.postgres=true`; o backup o
descobre mesmo quando Config.Image é um digest do GHCR ou ID local de
rollback, sem depender de nomes de projetos. O fallback de imagem legado
permanece. A override de rollback mantém o rótulo inclusive ao restaurar um
checkout anterior à adoção dele; web/migrate/db-provision não o recebem.

O servidor é espelho de `main`: não edite nem faça commit nele. O rollback
automático devolve o checkout ao SHA anterior, restaura as imagens anteriores e
só registra o estado depois que o endpoint público confirma saúde. Mesmo
quando a reversão recupera o site, o deploy original termina com erro e o
commit defeituoso permanece em `main` até ser corrigido.

#### Manutenção: PostgreSQL legado sem imagem recuperável

Se o image store perdeu a imagem de um banco ainda em execução, o deploy normal
recusa sem tocar no serviço. Não retagueie uma imagem diferente como se fosse a
antiga, não faça `docker commit` (pode incorporar estado/segredos) e não desative
essa guarda nos timers. Uma recuperação exige autorização específica para a
janela de manutenção e um **novo** ponto de retorno, não a alegação de que o ID
perdido foi recuperado.

Somente Mega-Sena/Conforto oferecem a opção explícita abaixo. Antes de usá-la:

1. Confirme a mesma versão principal PostgreSQL e ausência de alteração de
   schema/migrações; preserve os volumes e os segredos existentes.
2. Confira o backup e restaure uma cópia em banco descartável isolado, conforme
   `BackupRestore/RESTAURAR.md`, usando a candidata PostgreSQL publicada pela CI.
   Confira tabelas/linhas e a compatibilidade do código anterior com esse banco.
   Nunca restaure sobre o banco operacional durante esse ensaio.
3. Registre o digest/ID exato testado e a evidência da restauração. O argumento
   abaixo é a declaração deliberada do operador de que concluiu esses passos.
4. Execute `~/deploy.sh megasena --postgres-baseline=sha256:<ID-completo>` (ou
   `conforto`). O script exige CI, identidade/run/arquitetura da candidata,
   correspondência do ID informado e nenhuma diferença em `migrations` ou
   `alembic.ini`. Só substitui o ponto de retorno do serviço `postgres` cuja
   imagem esteja ausente; runtime/ICT/coletor ainda precisam de seus IDs antigos.

O rollback desta manutenção conserva código/runtime antigos e usa o PostgreSQL
**novo, validado no ensaio**, inclusive no provisionamento. Não desfaz dados ou
schema. A saída identifica explicitamente a substituição. ID incorreto, imagem
antiga ainda disponível, migrações alteradas, `--sem-ci` ou outro aplicativo
recusam antes do fast-forward. Se um run mais novo mudar a candidata, é preciso
revalidar o novo ID, não trocar o argumento por conveniência.

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
