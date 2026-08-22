# Nginx central do VPS

Esta pasta é a fonte versionada da configuração compartilhada em
`/etc/nginx/`. Editar os arquivos aqui não altera o servidor. A instalação é
uma operação explícita e deve usar [`instalar.sh`](instalar.sh), que salva a
configuração atual, instala os arquivos, executa `nginx -t`, restaura o estado
anterior se a validação falhar e só recarrega o Nginx quando a sintaxe é válida.

## Arquivos

| Fonte | Destino em `/etc/nginx/` | Função |
|---|---|---|
| `conforto-termico`, `controle-bancario`, `controle-renda-variavel`, `megasena` | `sites-available/` | Vhosts TLS dos aplicativos; variam por domínio, porta e `client_max_body_size`. |
| `recusa-host-desconhecido` | `sites-available/`, com link em `sites-enabled/` | Servidor padrão da porta 443 que recusa o handshake de nomes desconhecidos. |
| `conf.d/00-comum.conf` | `conf.d/` | Tipos gzip, chave por método e zona compartilhada do limitador de login. |
| `snippets/proxy-app.conf` | `snippets/` | Cabeçalhos e timeout comuns aos proxies. |

O prefixo `00-` garante que `map` e `limit_req_zone` sejam carregados antes dos
vhosts. `proxy_pass` permanece em cada vhost porque a porta é específica de
cada aplicação.

## Contratos

- HTTP redireciona para HTTPS, preservando o desafio ACME.
- TLS usa os certificados do Certbot e emite HSTS.
- Hosts desconhecidos são recusados durante o handshake TLS.
- Os cabeçalhos `Host`, `X-Real-IP`, `X-Forwarded-For` e
  `X-Forwarded-Proto` são encaminhados às aplicações.
- Gzip cobre texto, CSS, JavaScript, JSON, XML, SVG e WASM; WOFF2 permanece de
  fora porque já é comprimido.
- A zona `login` é compartilhada pelo Nginx. Somente `POST /login` consome o
  limite; `GET /login` permanece livre. O limite é `10r/m`, com burst 5 sem
  atraso, e rejeições respondem 429.
- Os vhosts mantêm `listen ... ssl http2` por compatibilidade com Nginx 1.24.

## Instalação

Disponibilize esta pasta no VPS em um diretório controlado pelo operador e
execute, a partir dele:

```bash
sudo -v
./instalar.sh "$(pwd)"
```

O script precisa de `sudo` para escrever em `/etc/nginx` e recarregar o
serviço. Ao final, ele verifica `/health` dos quatro domínios, negociação
HTTP/2, compressão e recusa de host desconhecido. Se alguma conferência
operacional falhar apesar de `nginx -t` passar, use o caminho de backup exibido
pelo próprio instalador para restaurar a configuração anterior.

Não inclua neste repositório credenciais, chaves privadas ou caminhos pessoais
para arquivos de autenticação.
