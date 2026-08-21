# Configurações do nginx do VPS

Correspondem a `/etc/nginx/` do VPS (`ubuntu@163.176.214.214`).

**Instalado em 2026-08-21** e conferido no ato: HTTP/2 negociado nos quatro
domínios, `content-encoding: gzip` num `.js` real, `Host` desconhecido recusado
no aperto de mão TLS, e o `limit_req` deixando 12 de 12 `GET /login` passarem
enquanto o `POST` cai para 429 depois do estouro.

Para reinstalar depois de mudar algo aqui: copie para `/home/ubuntu/nginx/` e
rode `~/instalar-nginx.sh` no servidor. Ele faz backup, valida com `nginx -t`,
**restaura sozinho sem recarregar** se reprovar, e confere o resultado no fim.

## O que é cada coisa

| Arquivo | Vai para | Para quê |
|---|---|---|
| `conforto-termico`, `controle-bancario`, `controle-renda-variavel`, `megasena` | `sites-available/` | um vhost por aplicativo; estrutura idêntica, só mudam domínio, porta e `client_max_body_size` |
| `recusa-host-desconhecido` | `sites-available/` + link em `sites-enabled/` | servidor padrão da 443, que corta no aperto de mão TLS quem chega com `Host` desconhecido |
| `conf.d/00-comum.conf` | `conf.d/` | compressão de verdade e a zona do limitador de login |
| `snippets/proxy-app.conf` | `snippets/` | os cabeçalhos de proxy, incluídos por todos os `location` |

O prefixo `00-` do `conf.d` não é enfeite: `map` e `limit_req_zone` precisam
ser lidos antes dos `sites-enabled/*` que os usam.

O `sites-enabled/` é só link simbólico para `sites-available/`.

## Por que existe um snippet em vez de repetir

Cada vhost passou a ter dois `location` — a raiz e o login com limitador. Sem o
snippet, o mesmo bloco de seis linhas de `proxy_set_header` ficaria repetido
oito vezes em quatro arquivos, e a próxima alteração seria feita em sete dos
oito lugares. É o mecanismo de deriva que estas rodadas existem para eliminar.

`proxy_pass` fica de fora do snippet de propósito: é a única linha que muda
entre os aplicativos, e é ela que precisa ficar visível em cada vhost.

## Duas coisas conferidas no servidor que contrariavam o plano

1. **O `default_server` já existia na porta 80** — vem no site `default` do
   pacote do Ubuntu. O buraco era só o HTTPS, e é só isso que
   `recusa-host-desconhecido` trata. Por isso ele não conflita com o site do
   pacote.
2. **`gzip on;` já estava ligado** no `nginx.conf`, mas com `gzip_types`
   comentado — e o padrão do nginx nesse caso é comprimir só `text/html`. A
   diretiva parecia resolvida e CSS e JS saíam sem compressão nenhuma.

## Não tem segredo dentro

Só domínio, porta e caminho de certificado. Não é artefato do BackupRestore —
atualizar à mão sempre que mudar rota ou domínio no servidor:

```
scp -i "C:\Users\MSPA\Downloads\OracleKeys\ssh-key-2026-08-17.key" ubuntu@163.176.214.214:/etc/nginx/sites-available/<nome> .
```

Ver decisão D5 em `PLANO_BACKUPRESTORE_VPS.md`.
