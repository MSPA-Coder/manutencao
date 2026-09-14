#!/bin/sh
# Recarrega o nginx depois que o certbot instala um certificado renovado.
#
# Instalado em `/etc/letsencrypt/renewal-hooks/deploy/recarregar-nginx.sh`, que
# é o diretório de onde o certbot executa TODO arquivo executável após uma
# renovação bem-sucedida -- e só então. Numa execução que não renovou nada, ele
# não roda.
#
# POR QUE ESTE ARQUIVO EXISTE. Até 14/09/2026 não havia hook nenhum em nenhum
# dos dois servidores. Sem ele, a renovação grava o certificado novo em disco e
# o nginx continua apresentando o ANTIGO, porque um processo já rodando não
# relê o certificado sozinho. Como nada falha, não há o que notificar: o
# `certbot renew` roda todo dia e reporta sucesso, o `OnFailure=` não dispara,
# e o sintoma só aparece na data de vencimento -- com o site apresentando
# certificado vencido para todo mundo.
#
# O `vigia.sh` avisaria antes (alerta abaixo de 15 dias restantes), mas avisar
# não é a mesma coisa que não quebrar.
#
# `sh` e não `bash`: o certbot executa isto num ambiente mínimo, e não há aqui
# nada que precise de bash.

set -e

# Servidor sem nginx ativo não é erro -- pode ser uma máquina que só emite
# certificado. Sair com sucesso evita marcar a renovação como falha.
systemctl is-active --quiet nginx || exit 0

# `nginx -t` ANTES do reload. Recarregar com configuração inválida derruba
# todos os sites da máquina de uma vez, e este script roda sozinho, de
# madrugada, sem ninguém olhando. Se a configuração estiver quebrada por outro
# motivo, o certificado novo esperar é melhor do que o site cair.
nginx -t

systemctl reload nginx
