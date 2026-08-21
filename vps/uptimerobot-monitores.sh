#!/usr/bin/env bash
# Configura no UptimeRobot os quatro monitores externos dos domínios.
#
#   ./uptimerobot-monitores.sh --estado    mostra o que existe
#   ./uptimerobot-monitores.sh --aplicar   cria o que falta, corrige o que diverge
#
# POR QUE EXISTE UM VIGIA DE FORA: o `vigia.sh` roda no próprio VPS. Ele cobre
# aplicação fora, banco fora, certificado vencendo, DNS quebrado e disco cheio
# — tudo, menos o VPS inteiro inalcançável. Sem observador externo, a
# monitoração não consegue relatar a própria morte, e silêncio fica idêntico a
# "está tudo bem".
#
# POR QUE O ALERTA DAQUI VAI POR E-MAIL E NÃO PELO TELEGRAM: o `alerta.sh`
# depende de o VPS ter saída para a internet. Este vigia existe justamente
# para funcionar quando aquele caminho está morto; repeti-lo herdaria a mesma
# falha. É a única exceção deliberada à regra de canal único.
#
# POR QUE TIPO KEYWORD E NÃO HTTP: um monitor HTTP aprova qualquer 200. A rota
# `/health` responde 200 com `"status":"ok"` quando o banco atende e 503 com
# `"status":"erro"` quando não. Só o keyword distingue os dois — que é
# exatamente a diferença que este monitor existe para enxergar.
#
# POR QUE A API v3 E NÃO A v2: a v2 recusa QUALQUER criação de monitor nesta
# conta ("not allowed to use some settings with your current plan"), inclusive
# HTTP simples no intervalo mínimo. A v3 aceita a mesma chave como Bearer e
# cria sem reclamar. Descoberto sondando a conta real, não por documentação: a
# página pública da v3 não traz o esquema do POST.

set -uo pipefail

CONFIG=/home/ubuntu/.secrets/uptimerobot.env
API=https://api.uptimerobot.com/v3

# `"ok"` com as aspas: o `jsonify` do Flask serializa `"status":"ok"` e o
# `JsonResponse` do Django serializa `"status": "ok"`. A subcadeia `"ok"` está
# nas duas, e as aspas evitam casar com um "ok" solto de outra mensagem.
PALAVRA='"ok"'

# 1h, por decisão do mantenedor em 2026-08-21 (começou em 12h e desceu depois
# de saber que o UptimeRobot notifica em MUDANÇA de estado, não a cada
# verificação — baixar o intervalo não aumenta o número de mensagens, só
# antecipa as mesmas).
#
# O piso da v3 é 15s e não custaria nada, então o número é escolha de tempo de
# descoberta. 1h alinha o vigia externo ao `vigia.timer` interno: os dois
# olham na mesma cadência, um de dentro e outro de fora.
INTERVALO=3600

DOMINIOS=(
    conforto-mspa.duckdns.org
    megasena-mspa.duckdns.org
    bancario-mspa.duckdns.org
    renda-mspa.duckdns.org
)

MODO="${1:---estado}"

[ -r "$CONFIG" ] || { echo "ERRO: $CONFIG ausente" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONFIG"
[ -n "${UPTIMEROBOT_API_KEY:-}" ] || { echo "ERRO: chave vazia" >&2; exit 1; }

# A chave entra pelo `--config -` (stdin), nunca em argv nem em `-H`:
# argumento de linha de comando é visível em `ps` para qualquer processo do
# host. O arquivo de configuração do curl aceita `header =` justamente assim.
chamar() {
    local metodo="$1" caminho="$2" corpo="${3:-}"
    local extra=()
    [ -n "$corpo" ] && extra=(--data-binary "$corpo" -H "Content-Type: application/json")

    curl -s --max-time 30 -X "$metodo" "${extra[@]}" --config - <<EOF
url = "$API$caminho"
header = "Authorization: Bearer ${UPTIMEROBOT_API_KEY}"
EOF
    # Plano gratuito: 10 requisições por minuto. Sem esta pausa uma execução
    # com quatro monitores esbarra no limite e chamadas voltam vazias.
    sleep 7
}

# --------------------------------------------------------------------------
# Contato de alerta: descoberto, não fixado no código
# --------------------------------------------------------------------------
CONTATO=$(chamar GET /alert-contacts | python3 -c '
import json, sys
d = json.load(sys.stdin).get("data", [])
ativos = [c for c in d if c.get("status") == "Active"]
print(ativos[0]["id"] if ativos else "")' 2>/dev/null)

if [ -z "$CONTATO" ]; then
    echo "ERRO: nenhum contato de alerta ativo. Confirme o e-mail no painel." >&2
    exit 1
fi
echo "contato de alerta ativo: $CONTATO"
echo

# --------------------------------------------------------------------------
# Estado atual
# --------------------------------------------------------------------------
atuais=$(chamar GET /monitors)

mostrar_estado() {
    printf '%s' "$atuais" | python3 -c '
import json, sys
alvos = sys.argv[1:]
por_url = {}
for m in json.load(sys.stdin).get("data", []):
    por_url[m.get("url", "").rstrip("/")] = m
for alvo in alvos:
    m = por_url.get("https://%s/health" % alvo)
    if not m:
        print("%-32s (nao existe)" % alvo)
    else:
        print("%-32s id %s | %s | %ss | %s | palavra %r | %s" % (
            alvo, m["id"], m["type"], m["interval"],
            m.get("keywordType") or "-", m.get("keywordValue"), m["status"]))' "${DOMINIOS[@]}"
}

mostrar_estado

if [ "$MODO" != "--aplicar" ]; then
    echo
    echo "(--estado: nada foi alterado. Use --aplicar.)"
    exit 0
fi

# --------------------------------------------------------------------------
# Aplicar
#
# `ALERT_NOT_EXISTS`: o monitor cai quando a palavra NÃO aparece. É o sentido
# certo, e o inverso seria pior que não ter monitor — alertaria com tudo bem e
# ficaria calado na queda. Conferido depois pelo estado que a API reporta.
#
# Monitor de tipo errado é APAGADO e recriado: a API recusa trocar o tipo
# depois de criado ("Monitor type cannot be changed after creation"), e o
# cadastro cria um HTTP simples que aprovaria um 503.
# --------------------------------------------------------------------------
echo
for dominio in "${DOMINIOS[@]}"; do
    url="https://$dominio/health"

    leitura=$(printf '%s' "$atuais" | python3 -c '
import json, sys
alvo = sys.argv[1].rstrip("/")
for m in json.load(sys.stdin).get("data", []):
    if m.get("url", "").rstrip("/") == alvo:
        print(m["id"], m["type"])
        break' "$url" 2>/dev/null)

    id=$(echo "$leitura" | awk '{print $1}')
    tipo=$(echo "$leitura" | awk '{print $2}')

    if [ -n "$id" ] && [ "$tipo" != "KEYWORD" ]; then
        echo "-- $dominio: existe como $tipo e o tipo nao pode mudar; apagando id $id"
        chamar DELETE "/monitors/$id" >/dev/null
        id=""
    fi

    corpo=$(python3 -c '
import json, sys
nome, url, palavra, intervalo, contato = sys.argv[1:6]
print(json.dumps({
    "friendlyName": nome,
    "url": url,
    "type": "KEYWORD",
    "interval": int(intervalo),
    "timeout": 30,
    "keywordType": "ALERT_NOT_EXISTS",
    "keywordValue": palavra,
    "keywordCaseType": "CaseSensitive",
    "assignedAlertContacts": [
        {"alertContactId": int(contato), "threshold": 0, "recurrence": 0}
    ],
}))' "$dominio" "$url" "$PALAVRA" "$INTERVALO" "$CONTATO")

    if [ -n "$id" ]; then
        echo "-- $dominio: ajustando id $id"
        resposta=$(chamar PATCH "/monitors/$id" "$corpo")
    else
        echo "-- $dominio: criando"
        resposta=$(chamar POST "/monitors" "$corpo")
    fi

    printf '%s' "$resposta" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("   resposta ilegivel"); sys.exit()
if d.get("id"):
    print("   ok — id", d["id"], "|", d.get("status"))
elif d.get("data", {}).get("id"):
    print("   ok — id", d["data"]["id"])
else:
    print("   FALHOU:", d.get("message") or d)' 2>/dev/null
done

echo
echo "Estado final:"
atuais=$(chamar GET /monitors)
mostrar_estado
