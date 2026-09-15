#!/usr/bin/env bash
# Agente restrito de backup — um verbo por conexão SSH.
#
# Instalado com uma chave dedicada em authorized_keys, presa por `command=`
# a este script: quem conecta com essa chave só executa um dos quatro verbos
# abaixo, nunca um shell. A cópia executável vive em
# /home/ubuntu/backup-agent.sh.
#
#   listar               nomes, tamanhos e SHA-256 dos dumps disponíveis;
#                        registra a busca em $DEST/.ultima_busca
#   enviar <slug/nome>    despeja um dump na saída padrão
#   apagar <slug/nome>    remove um dump — recusa o mais recente
#   estado                último backup de cada projeto + saúde do timer
#
# O comando real do cliente SSH chega em $SSH_ORIGINAL_COMMAND — este script
# ignora qualquer outra coisa que o cliente tente passar como argv, porque é
# isso que o `command=` do authorized_keys garante: só este script roda,
# sempre, e só ele decide o que $SSH_ORIGINAL_COMMAND autoriza.

set -euo pipefail

# `DEST` aceita sobreposição pelo ambiente só para a suíte hermética
# (`tests/backup-agent_test.sh`), no mesmo formato do `backup-db.sh`. Isso não
# abre porta pelo SSH: o sshd só repassa ao processo as variáveis de
# `AcceptEnv` (conferido em 15/09/2026: `LANG` e `LC_*` nos dois servidores,
# mais `COLORTERM` e `NO_COLOR` no do portal), e `PermitUserEnvironment` está
# desligado nos dois — quem conecta com a chave do agente não escolhe `DEST`.
DEST=${DEST:-/home/ubuntu/backups}
BACKUP_DB_SH=/home/ubuntu/backup-db.sh

# Batimento da cópia fora do servidor (Camada 2). Ver `verbo_listar` e a seção
# "Busca do backup" do `vigia.sh`.
MARCA_BUSCA="$DEST/.ultima_busca"

erro() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

# Os projetos são as pastas que existem em DEST — criadas pelo `backup-db.sh`
# a partir dos bancos que ele encontra rodando.
#
# POR QUE DEIXOU DE SER UMA LISTA AQUI (13/09/2026): era
# `(conforto_termico mega_sena controle_bancario controle_renda_variavel)`, e
# estava errada. O portal entrou na frota em 10/09, foi acrescentado à lista do
# `backup-db.sh` e não a esta — por três dias o dump do `mp_portal` foi
# produzido todo dia e NENHUM deles podia ser baixado: `enviar mp_portal/...`
# respondia "projeto desconhecido". Um backup que não se consegue buscar é
# meio backup, e nada acusou, porque as duas listas não se conversavam. A
# pasta em disco é a mesma verdade para os dois scripts.
#
# ISTO NÃO AFROUXA A DEFESA contra travessia de caminho: `resolver_dump`
# continua exigindo o formato exato do nome, que o arquivo exista, e que o
# `realpath` caia dentro de DEST/<slug>/. Quem conseguisse criar pasta em DEST
# para forjar um "projeto" já teria acesso ao disco do servidor, e aí não é
# este script que está no caminho.
projetos() {
    local dir
    for dir in "$DEST"/*/; do
        [ -d "$dir" ] || continue
        basename "$dir"
    done
}

eh_projeto_valido() {
    local slug="$1" p
    for p in $(projetos); do [ "$p" = "$slug" ] && return 0; done
    return 1
}

# Resolve "<slug>/<arquivo>.dump" para um caminho absoluto dentro de DEST,
# recusando qualquer coisa que não bata no formato exato produzido pelo
# backup-db.sh. É a defesa contra travessia de caminho e injeção — o cliente
# nunca escolhe um caminho livre, só um nome que já precisa existir no disco.
resolver_dump() {
    local entrada="$1" slug arquivo caminho real
    [[ "$entrada" =~ ^([a-z_]+)/([a-z_]+_banco_[0-9]{8}_[0-9]{6}\.dump)$ ]] \
        || erro "formato de caminho inválido"
    slug="${BASH_REMATCH[1]}"
    arquivo="${BASH_REMATCH[2]}"
    eh_projeto_valido "$slug" || erro "projeto desconhecido: $slug"
    [[ "$arquivo" == "${slug}_banco_"* ]] || erro "arquivo não pertence ao projeto"

    caminho="$DEST/$slug/$arquivo"
    [ -f "$caminho" ] || erro "arquivo não encontrado"

    # realpath confirma que não há symlink escapando de DEST/<slug>/.
    real=$(realpath "$caminho")
    [[ "$real" == "$DEST/$slug/"* ]] || erro "caminho fora da área permitida"
    printf '%s' "$real"
}

mais_recente() {
    local dir="$1"
    # shellcheck disable=SC2012  # os nomes são gerados por backup-db.sh (slug e
    # carimbo de tempo, sem espaço nem quebra de linha), então o `ls` não tem o
    # que quebrar. A alternativa com `find -printf '%T@ %p'` compraria robustez
    # contra nomes que este diretório nunca terá, ao preço de ilegibilidade na
    # linha que decide qual dump é o mais novo.
    ls -1t "$dir"/*.dump 2>/dev/null | head -1 || true
}

verbo_listar() {
    local slug dir arq tam hash
    for slug in $(projetos); do
        dir="$DEST/$slug"
        [ -d "$dir" ] || continue
        for arq in "$dir"/*.dump; do
            [ -e "$arq" ] || continue
            tam=$(stat -c %s "$arq")
            hash=$(cat "$arq.sha256" 2>/dev/null || echo "sem-hash")
            printf '%s/%s %s %s\n' "$slug" "$(basename "$arq")" "$tam" "$hash"
        done
    done

    # Batimento da cópia fora do servidor (15/09/2026). O BackupRestore começa
    # toda sincronização por `listar`, mesmo quando não há dump novo para
    # buscar, e o `vigia.sh` alerta quando este marcador envelhece. Só depois da
    # listagem, para registrar busca que de fato respondeu. `|| true` porque uma
    # medição que não grava não pode derrubar a sincronização: sem marcador, o
    # próprio vigia acusa.
    touch "$MARCA_BUSCA" 2>/dev/null || true
}

verbo_enviar() {
    local caminho
    caminho=$(resolver_dump "${1:-}")
    cat "$caminho"
}

verbo_apagar() {
    local caminho dir novo
    caminho=$(resolver_dump "${1:-}")
    dir=$(dirname "$caminho")
    novo=$(mais_recente "$dir")
    [ "$caminho" = "$novo" ] && erro "recusado: é o dump mais recente de $(basename "$dir")"
    rm -f "$caminho" "$caminho.sha256"
    printf 'apagado: %s\n' "$(basename "$caminho")"
}

verbo_estado() {
    if [ -x "$BACKUP_DB_SH" ]; then
        "$BACKUP_DB_SH" --estado
    fi
    echo
    printf 'timer backup-db.timer: %s (%s)\n' \
        "$(systemctl is-active backup-db.timer 2>/dev/null || echo desconhecido)" \
        "$(systemctl is-enabled backup-db.timer 2>/dev/null || echo desconhecido)"
}

# --------------------------------------------------------------------------
# $SSH_ORIGINAL_COMMAND é a única fonte do verbo — o que o cliente tentou
# passar como argv deste script (via `ssh host arg1 arg2`) nunca chega aqui
# por sshd já ter substituído a execução pelo `command=` forçado; ele só
# preserva a intenção original nessa variável, para o script decidir.
# --------------------------------------------------------------------------
comando="${SSH_ORIGINAL_COMMAND:-}"
read -r -a partes <<< "$comando"
verbo="${partes[0]:-}"
arg="${partes[1]:-}"

case "$verbo" in
    listar) verbo_listar ;;
    enviar) verbo_enviar "$arg" ;;
    apagar) verbo_apagar "$arg" ;;
    estado) verbo_estado ;;
    *) erro "verbo desconhecido — use: listar | enviar <arquivo> | apagar <arquivo> | estado" ;;
esac
