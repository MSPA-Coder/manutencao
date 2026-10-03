#!/usr/bin/env bash
# Vigia horário: disco, endereços públicos, certificado, frescor do backup,
# busca do backup pela cópia fora do servidor e frescor dos dados (cotações do
# CRV, sincronização e importação do Wealthfolio).
#
#   ./vigia.sh            faz o ciclo e alerta
#   ./vigia.sh --estado   mostra tudo, sem alertar
#
# Cada verificação aqui cobre uma falha que hoje não tem quem a perceba.
#
# A de frescor do backup fecha um buraco do `OnFailure=`: ele só dispara se o
# serviço RODAR e falhar. Timer desabilitado por engano, systemd que não
# disparou, máquina desligada na hora — em nenhum desses casos existe falha
# para notificar, e o backup simplesmente para em silêncio. Só a idade do
# último backup detecta isso.
#
# A de busca fecha o mesmo buraco do outro lado: o dump pode estar em dia aqui
# e ninguém estar levando a cópia para fora do servidor.
#
# A de frescor dos dados é a mesma ideia para o que o `/health` não vê: ele só
# diz se o processo responde. Se o agente RTD ou a sincronização do Wealthfolio
# parar, o app segue "ok" e o número fica cada dia mais velho. O alerta de
# frescor NÃO vai para o `/health`, de propósito: a autocura reinicia contêiner
# `unhealthy`, e uma cotação velha reiniciaria o CRV sem motivo. Por isso o vigia
# lê a idade por fora e só avisa.

set -uo pipefail

# `ALERTA`, `BACKUPS` e `DOCKER` aceitam sobreposição pelo ambiente para a suíte
# hermética (`tests/vigia_test.sh`), como `NGINX_HABILITADOS` já aceitava.
ALERTA=${ALERTA:-/home/ubuntu/alerta.sh}
BACKUPS=${BACKUPS:-/home/ubuntu/backups}
NGINX_HABILITADOS=${NGINX_HABILITADOS:-/etc/nginx/sites-enabled}
DOCKER=${DOCKER:-docker}
DISCO_TETO=80          # % de uso a partir do qual alerta
BACKUP_MAX_HORAS=36    # ciclo é diário; 36h já é atraso, não variação
BUSCA_MAX_HORAS=72     # quem busca é uma máquina Windows; tolera um fim de semana desligada
CERT_MIN_DIAS=15       # certbot renova aos 30; 15 significa que falhou 2x
REBOOT_MAX_DIAS=3      # tolera o fim de semana; não deixa acumular semanas
# Frescor dos dados. Limites largos de propósito: mercado fecha no fim de semana
# e em feriado, então "velho" tem de querer dizer "parou", não "é sábado".
COTACAO_DIARIA_MAX_DIAS=5     # série diária do Yahoo; cobre fim de semana + Carnaval
COTACAO_VIVA_MAX_HORAS=120    # RTD vem de um PC Windows; 5 dias cobre o feriado mais longo
WF_MERCADO_MAX_HORAS=8        # o Wealthfolio sincroniza cotações a cada 6h
WF_IMPORTACAO_FALHAS_MAX=3    # a importação roda a cada 15 min: 3 falhas na última hora é persistente

# Os domínios são lidos dos vhosts habilitados NESTE servidor.
#
# POR QUE DEIXOU DE SER UMA LISTA (13/09/2026): a lista fixa dizia "a frota", o
# que era sinônimo de "esta máquina" enquanto havia uma só. Com um segundo VPS
# ela passa a descrever, em parte, a OUTRA máquina — o vigia de um servidor
# alertaria sobre aplicações que não são dele, e a pergunta "de qual máquina
# veio este alerta?" viraria adivinhação. O nginx desta caixa já sabe a
# resposta certa.
#
# É a mesma decisão que o `tests/nginx_test.sh` deste repositório já tinha
# tomado, pelo mesmo motivo, e que está escrita lá: "acrescentar um projeto à
# frota não pode exigir que alguém lembre de editar este teste também".
#
# `grep -R` e NÃO `-r`: `sites-enabled/` é um diretório de LINKS, e o `-r` não
# os segue. Conferido no VPS — com `-r` a saída é VAZIA, e um vigia cego não
# teria como se queixar da própria cegueira.
#
# `server_name _` fica de fora: são o `default` do pacote do Ubuntu e o
# `recusa-host-desconhecido`, que existem justamente para tratar o que não é
# domínio nosso.
descobrir_dominios() {
    grep -RhE '^[[:space:]]*server_name[[:space:]]' "$NGINX_HABILITADOS"/ 2>/dev/null \
        | sed -E 's/^[[:space:]]*server_name[[:space:]]+//; s/;.*$//' \
        | tr ' ' '\n' \
        | sed '/^$/d; /^_$/d' \
        | sort -u
}

mapfile -t DOMINIOS < <(descobrir_dominios)

MODO="${1:-alertar}"
falhas=0

registrar() { logger -t vigia -- "$*"; }

# Janela larga: estas condições duram horas. Com a janela padrão de 15 min o
# vigia apitaria a cada execução até alguém agir.
alertar() {
    if [ "$MODO" = "--estado" ]; then
        echo "  ALERTARIA: $1"
        return 0
    fi
    ALERTA_JANELA=21600 "$ALERTA" "$1" "${2:-}" || true
    falhas=$(( falhas + 1 ))
}

# --------------------------------------------------------------------------
# Disco
# --------------------------------------------------------------------------
uso=$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')
[ "$MODO" = "--estado" ] && echo "disco: ${uso}% usado (teto ${DISCO_TETO}%)"
if [ -n "$uso" ] && [ "$uso" -ge "$DISCO_TETO" ]; then
    alertar "DISCO em ${uso}%" \
"Uso da raiz passou de ${DISCO_TETO}%.

$(df -h / | tail -1)

Maiores consumidores do Docker:
$(docker system df 2>/dev/null || echo '(docker indisponível)')

Cache de build costuma ser o culpado — o deploy constrói no servidor.
Para recuperar:  docker builder prune -f"
fi

# --------------------------------------------------------------------------
# Endereços públicos
#
# Bate no /health pela URL pública de propósito: assim o teste atravessa DNS,
# TLS, nginx, aplicação e banco. Uma sonda em 127.0.0.1 aprovaria um site que
# o mundo não alcança.
#
# `-L` porque os quatro não concordam sobre a barra final: os três Flask
# servem `/health`, o ControleBancario serve `/health/` e o `APPEND_SLASH` do
# Django responde 301 ao caminho sem barra. Seguir o redirecionamento não
# afrouxa a verificação — o critério de aprovação é o corpo conter
# `"status":"ok"`, que uma tela de login redirecionada não produziria.
# --------------------------------------------------------------------------
# Vigia que não vigia nada precisa dizer isso em voz alta. Silêncio aqui seria
# lido como "tudo bem" — que é exatamente o modo de falha que este script
# existe para não ter.
if [ "${#DOMINIOS[@]}" -eq 0 ]; then
    [ "$MODO" = "--estado" ] && echo "dominios: NENHUM encontrado em $NGINX_HABILITADOS"
    alertar "VIGIA CEGO: nenhum domínio para verificar" \
"Nenhum \`server_name\` foi encontrado em $NGINX_HABILITADOS.

Ou o nginx desta máquina não serve nenhum vhost, ou o diretório mudou de
lugar. Enquanto isto durar, nenhuma aplicação está sendo verificada aqui.

  ls -l $NGINX_HABILITADOS
  nginx -T | grep server_name"
fi

for dominio in "${DOMINIOS[@]}"; do
    corpo=$(curl -sSL --max-time 15 "https://$dominio/health" 2>&1)
    codigo=$(curl -sSL --max-time 15 -o /dev/null -w '%{http_code}' "https://$dominio/health" 2>/dev/null || echo 000)

    if [ "$MODO" = "--estado" ]; then
        echo "$dominio: HTTP $codigo  $(printf '%s' "$corpo" | head -c 80)"
    fi

    # Regex e não texto literal: o `jsonify` do Flask serializa compacto
    # (`"status":"ok"`) e o `JsonResponse` do Django põe espaço depois dos
    # dois-pontos (`"status": "ok"`). Espaço em JSON não é parte de contrato,
    # portanto o verificador aceita as duas serializações.
    #
    # O Wealthfolio (domínio `networth-mspa`) responde o texto puro `ok`, sem
    # JSON; o `deploy.sh` o aceita pelo mesmo critério (`PADRAO_SAUDE='^ok$'`).
    # Sem isto o vigia alertava "FORA DO AR" para um serviço no ar desde 29/09.
    if ! printf '%s' "$corpo" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' \
        && [ "$(printf '%s' "$corpo" | tr -d '[:space:]')" != ok ]; then
        alertar "FORA DO AR: $dominio" \
"GET https://$dominio/health devolveu HTTP $codigo.

Resposta:
$(printf '%s' "$corpo" | head -c 500)

A rota consulta o banco. 503 aqui significa aplicação de pé e banco
inalcançável; erro de conexão significa nginx ou o contêiner fora."
    fi

    # Certificado
    fim=$(echo | openssl s_client -servername "$dominio" -connect "$dominio:443" 2>/dev/null \
          | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$fim" ]; then
        dias=$(( ( $(date -d "$fim" +%s) - $(date +%s) ) / 86400 ))
        [ "$MODO" = "--estado" ] && echo "    certificado: $dias dia(s)"
        if [ "$dias" -lt "$CERT_MIN_DIAS" ]; then
            alertar "CERTIFICADO vencendo: $dominio" \
"Faltam $dias dia(s) — vence em $fim.

O certbot renova aos 30 dias restantes. Chegar a $dias significa que a
renovação já falhou mais de uma vez.

Conferir:  sudo certbot renew --dry-run"
        fi
    fi
done

# --------------------------------------------------------------------------
# Frescor do backup — o que o OnFailure= não cobre
# --------------------------------------------------------------------------
for dir in "$BACKUPS"/*/; do
    [ -d "$dir" ] || continue
    slug=$(basename "$dir")
    marca="$dir/.ultima_conferencia"

    if [ ! -r "$marca" ]; then
        [ "$MODO" = "--estado" ] && echo "backup $slug: SEM MARCADOR"
        alertar "BACKUP sem marcador: $slug" \
"Não existe .ultima_conferencia em $dir — o ciclo nunca terminou aqui."
        continue
    fi

    horas=$(( ( $(date +%s) - $(stat -c %Y "$marca") ) / 3600 ))
    [ "$MODO" = "--estado" ] && echo "backup $slug: conferido há ${horas}h"

    if [ "$horas" -ge "$BACKUP_MAX_HORAS" ]; then
        alertar "BACKUP parado: $slug" \
"Última conferência há ${horas}h — o ciclo é diário.

Nenhuma falha foi notificada, então o serviço provavelmente não chegou a
rodar. Conferir o timer, não o script:

  systemctl status backup-db.timer
  systemctl list-timers backup-db.timer"
    fi
done

# --------------------------------------------------------------------------
# Busca do backup — a cópia fora do servidor
#
# O ciclo acima prova que o dump NASCE aqui. Levá-lo para fora é outro
# processo, em outra máquina: o BackupRestore, no Windows do mantenedor,
# conecta pelo `backup-agent.sh` e começa toda sincronização por `listar`, que
# grava `.ultima_busca` na raiz de $BACKUPS.
#
# POR QUE EXISTE (15/09/2026): a tarefa agendada que dispara essa busca foi
# achada desabilitada três vezes (02/09, 05/09 e 15/09). Tarefa desabilitada não
# roda, então não falha, e nenhum dos dois lados avisava: aqui os dumps seguiam
# em dia, e lá não havia execução para registrar erro.
#
# POR QUE `listar` E NÃO `enviar`: o `backup-db.sh` só grava dump novo quando o
# banco muda. Projeto sem movimento passa dias sem nada para buscar, e medir
# pelo `enviar` alertaria justamente o caso normal.
#
# O título é fixo e as horas vão no corpo: o `alerta.sh` reconhece repetição
# pelo título, e um título com a idade viraria alerta novo a cada hora.
#
# Máquina sem nenhuma pasta de projeto não produz backup, e não há o que buscar.
# --------------------------------------------------------------------------
produz_backup=0
for dir in "$BACKUPS"/*/; do
    if [ -d "$dir" ]; then
        produz_backup=1
        break
    fi
done

marca_busca="$BACKUPS/.ultima_busca"
conferir_busca="Conferir na máquina do BackupRestore:
  Get-ScheduledTask -TaskName BackupRestore   (State precisa ser Ready)
  ultima-execucao.txt, na pasta do BackupRestore
  tailscale status, se este servidor é alcançado pelo Tailscale"

if [ "$produz_backup" -eq 0 ]; then
    [ "$MODO" = "--estado" ] && echo "busca dos backups: sem projeto nesta máquina"
elif [ ! -r "$marca_busca" ]; then
    [ "$MODO" = "--estado" ] && echo "busca dos backups: NUNCA registrada"
    alertar "BACKUP nunca buscado" \
"Não existe $marca_busca: nenhuma busca do BackupRestore foi registrada aqui.
Os dumps estão sendo produzidos, mas nenhum saiu do servidor.

$conferir_busca"
else
    horas=$(( ( $(date +%s) - $(stat -c %Y "$marca_busca") ) / 3600 ))
    [ "$MODO" = "--estado" ] && echo "busca dos backups: há ${horas}h (limite ${BUSCA_MAX_HORAS}h)"
    if [ "$horas" -ge "$BUSCA_MAX_HORAS" ]; then
        alertar "BACKUP não buscado" \
"A última busca do BackupRestore foi há ${horas}h. Os dumps continuam
nascendo aqui; o que parou foi a cópia para fora do servidor.

$conferir_busca"
    fi
fi

# --------------------------------------------------------------------------
# Frescor dos dados -- o que o /health não diz
#
# CRV (cotações). A idade da série diária (Yahoo, timer `cotacoes-diarias`) e da
# cotação ao vivo (agente RTD, num PC Windows), lidas pelo contrato `leitura` do
# próprio banco: as views `leitura.cotacao_historico` e `leitura.cotacao`, que o
# CRV publica pelas migrações. Não lê tabela do CRV -- o que o FinancasMCP
# aprendeu em 24/09 (coluna removida, consulta quebrada em silêncio) vale para o
# vigia também. Sem o esquema, alerta: um vigia que cala sem o contrato é cego.
#
# Wealthfolio (importação e cotações). O servidor loga, a cada 6h, "Periodic
# market data sync completed: N synced, M skipped, K failed" e, quando a
# importação do CB ou do CRV falha, "Patrimonio sync failed for source X". A
# importação que dá certo NÃO deixa rastro no log, então o que se vê daqui é: o
# servidor segue vivo o bastante para sincronizar cotações, e a importação não
# está falhando em série. Um batimento próprio da importação pede uma linha de
# log nova no patch 0005 (e um rebuild do Wealthfolio, de 35 a 60 min): pendência.
#
# Títulos fixos, com os números no corpo: o `alerta.sh` reconhece repetição pelo
# título.
# --------------------------------------------------------------------------
# O servidor colore o log com sequências ANSI; tirar o ESC de forma portátil
# (o `sed` do BusyBox, nos testes, não entende `\x1b`).
ESC=$(printf '\033')
sem_cor() { sed "s/${ESC}\[[0-9;]*m//g"; }

container_do_servico() {
    "$DOCKER" ps -q --filter "label=com.docker.compose.project=$1" \
        --filter "label=com.docker.compose.service=$2" 2>/dev/null | head -1
}

crv_db=$(container_do_servico controle-renda-variavel db)
if [ -z "$crv_db" ]; then
    [ "$MODO" = "--estado" ] && echo "frescor do CRV: sem o CRV nesta máquina"
else
    consulta_frescor="select coalesce((now() at time zone 'America/Sao_Paulo')::date - (select max(data) from leitura.cotacao_historico), -1), coalesce(round(extract(epoch from now() - (select max(cotado_em) from leitura.cotacao)) / 3600), -1);"
    # shellcheck disable=SC2016  # as variáveis expandem DENTRO do contêiner, onde estão as credenciais
    comando_psql='psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF "|"'
    if resultado=$(printf '%s\n' "$consulta_frescor" \
            | "$DOCKER" exec -i "$crv_db" sh -c "$comando_psql" 2>&1) \
        && dias_diaria=${resultado%%|*} && horas_viva=${resultado##*|} \
        && case "$dias_diaria$horas_viva" in ''|*[!0-9-]*) false ;; *) true ;; esac; then
        [ "$MODO" = "--estado" ] && echo "frescor do CRV: série diária há ${dias_diaria} dia(s) (limite ${COTACAO_DIARIA_MAX_DIAS}); cotação ao vivo há ${horas_viva}h (limite ${COTACAO_VIVA_MAX_HORAS}h); -1 = sem dado"
        if [ "$dias_diaria" -lt 0 ] || [ "$dias_diaria" -ge "$COTACAO_DIARIA_MAX_DIAS" ]; then
            alertar "COTAÇÕES diárias paradas (CRV)" \
"A série diária de cotações do CRV está parada: dias desde o último fechamento
registrado: ${dias_diaria} (limite ${COTACAO_DIARIA_MAX_DIAS}; -1 quer dizer que não há nenhum).

Ela vem do Yahoo, pelo timer cotacoes-diarias, e é o que mantém o histórico sem
buracos com o PC desligado. Conferir:
  systemctl status cotacoes-diarias.timer cotacoes-diarias.service
  journalctl -u cotacoes-diarias -n 30"
        fi
        if [ "$horas_viva" -lt 0 ] || [ "$horas_viva" -ge "$COTACAO_VIVA_MAX_HORAS" ]; then
            alertar "COTAÇÃO ao vivo parada (CRV)" \
"A cotação ao vivo mais recente do CRV tem ${horas_viva}h (limite ${COTACAO_VIVA_MAX_HORAS}h; -1 quer
dizer que não há nenhuma). Ela vem do agente RTD, no PC Windows: PC desligado,
tarefa parada ou ProfitPro fechado. O v4 segue publicando o último preço, cada
dia mais velho, e nada mais avisa.

Conferir no PC: tarefa do agente RTD (rtd-agent.ps1) e o ProfitPro aberto."
        fi
    else
        [ "$MODO" = "--estado" ] && echo "frescor do CRV: NÃO foi possível ler o contrato leitura"
        alertar "FRESCOR do CRV sem o contrato leitura" \
"Não consegui ler leitura.cotacao_historico e leitura.cotacao no banco do CRV.
Sem isso o vigia não sabe se as cotações estão em dia.

Resposta do banco: $(printf '%s' "${resultado:-}" | head -c 300)

O esquema leitura é criado pela migração 20261003_0027 do CRV. Se o CRV
implantado é anterior a ela, implante o CRV; se o esquema existe, conferir:
  docker exec $crv_db sh -c 'psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -c \"\\dv leitura.*\"'"
    fi
fi

wf=$(container_do_servico wealthfolio-teste wealthfolio)
if [ -z "$wf" ]; then
    [ "$MODO" = "--estado" ] && echo "frescor do Wealthfolio: sem o Wealthfolio nesta máquina"
else
    log_mercado=$("$DOCKER" logs --since "${WF_MERCADO_MAX_HORAS}h" "$wf" 2>&1 | sem_cor | grep 'Periodic market data sync completed' || true)
    n_mercado=$(printf '%s\n' "$log_mercado" | grep -c 'Periodic market data sync completed' || true)
    ultima_mercado=$(printf '%s\n' "$log_mercado" | tail -1)
    falhas_mercado=$(printf '%s' "$ultima_mercado" | sed -n 's/.* \([0-9][0-9]*\) failed.*/\1/p')
    log_importacao=$("$DOCKER" logs --since 1h "$wf" 2>&1 | sem_cor | grep 'Patrimonio sync failed for source' || true)
    n_importacao=$(printf '%s\n' "$log_importacao" | grep -c 'Patrimonio sync failed for source' || true)
    fontes_importacao=$(printf '%s\n' "$log_importacao" | sed -n 's/.*Patrimonio sync failed for source \([A-Za-z-]*\).*/\1/p' | sort | uniq -c | tr '\n' ' ')
    [ "$MODO" = "--estado" ] && echo "frescor do Wealthfolio: sincronização de cotações ${n_mercado}x nas últimas ${WF_MERCADO_MAX_HORAS}h (última com ${falhas_mercado:-?} falha(s)); importação CB/CRV com ${n_importacao} falha(s) na última hora (limite ${WF_IMPORTACAO_FALHAS_MAX})"
    if [ "$n_mercado" -eq 0 ]; then
        alertar "WEALTHFOLIO sem sincronizar cotações" \
"O log do Wealthfolio não tem nenhuma sincronização periódica de cotações nas
últimas ${WF_MERCADO_MAX_HORAS}h (ela roda a cada 6h). O processo responde, mas o agendador interno
parou: é o mesmo servidor que importa o CB e o CRV a cada 15 min.

Conferir:  docker logs --since ${WF_MERCADO_MAX_HORAS}h $wf 2>&1 | grep -i 'scheduler\\|Periodic'
Reiniciar, se for o caso:  cd ~/apps/wealthfolio-teste && docker compose restart"
    elif [ -n "$falhas_mercado" ] && [ "$falhas_mercado" -gt 0 ]; then
        alertar "WEALTHFOLIO falha ao sincronizar cotações" \
"A última sincronização periódica de cotações do Wealthfolio terminou com
${falhas_mercado} falha(s):
  ${ultima_mercado}

Ativo sem cotação aparece no Data Health (/health) do Wealthfolio, com o motivo."
    fi
    if [ "$n_importacao" -ge "$WF_IMPORTACAO_FALHAS_MAX" ]; then
        alertar "WEALTHFOLIO importação do CB/CRV falhando" \
"A importação do CB/CRV falhou ${n_importacao} vez(es) na última hora (fontes: ${fontes_importacao}).
Ela roda a cada 15 min; falha em série não é um soluço de deploy.

Conferir:  docker logs --since 1h $wf 2>&1 | grep -i 'Patrimonio sync'
O estado por fonte está na tela do add-on (Settings > Addons) e em
GET /api/v1/patrimonio-sync/status (exige login)."
    fi
fi

# --------------------------------------------------------------------------
# Reboot pendente
#
# unattended-upgrades instala patches de segurança mas não reinicia sozinho
# (Automatic-Reboot fica desligado de propósito — reboot dos 4 apps junto é
# decisão de horário, não de script). Sem este aviso, um kernel corrigido
# fica parado sem rodar por tempo indefinido e ninguém percebe.
# --------------------------------------------------------------------------
if [ -f /var/run/reboot-required ]; then
    dias=$(( ( $(date +%s) - $(stat -c %Y /var/run/reboot-required) ) / 86400 ))
    [ "$MODO" = "--estado" ] && echo "reboot pendente: há ${dias} dia(s)"
    if [ "$dias" -ge "$REBOOT_MAX_DIAS" ]; then
        alertar "REBOOT pendente há ${dias} dia(s)" \
"$(cat /var/run/reboot-required.pkgs 2>/dev/null || echo '(lista de pacotes indisponível)')

Containers têm restart automático (unless-stopped). Escolha um horário de
baixo uso, reinicie e confira o menu do bot do Telegram em seguida."
    fi
else
    [ "$MODO" = "--estado" ] && echo "reboot pendente: nao"
fi

if [ "$MODO" != "--estado" ]; then
    registrar "ciclo concluído — $falhas alerta(s)"
fi
exit 0
