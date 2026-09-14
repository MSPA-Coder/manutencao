# Nginx central do VPS

Esta pasta é a fonte versionada da configuração compartilhada em
`/etc/nginx/`. Editar os arquivos aqui não altera o servidor. A instalação é
uma operação explícita e deve usar [`instalar.sh`](instalar.sh), que salva a
configuração atual, instala os arquivos, executa `nginx -t`, restaura o estado
anterior se a validação falhar e só recarrega o Nginx quando a sintaxe é válida.

## Arquivos

| Fonte | Destino em `/etc/nginx/` | Função |
|---|---|---|
| `conforto-termico`, `controle-bancario`, `controle-renda-variavel`, `megasena`, `portal` | `sites-available/` | Vhosts TLS dos aplicativos; variam por domínio, porta e `client_max_body_size`. O `portal` (domínio `mp-solucoes.duckdns.org`) substituiu o vhost `mp-solucoes` do site estático na virada de 10/09/2026 — mesmo domínio e certificado, agora com o limitador de `/login` porque a aplicação tem autenticação. Esta pasta é a fonte de TODOS os vhosts da frota; quais deles vão para um servidor é decidido pelo diretório de origem usado na instalação (abaixo). |
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

Disponibilize no VPS um diretório controlado pelo operador contendo
`conf.d/00-comum.conf`, `snippets/proxy-app.conf`, `recusa-host-desconhecido` e
**os vhosts que esta máquina serve** — e execute, a partir dele:

```bash
sudo -v
./instalar.sh "$(pwd)"
```

O conteúdo desse diretório é o que declara quais sites o servidor atende: o
instalador entrega os vhosts que encontrar ali, lista quais são antes de tocar
em qualquer coisa, e recusa rodar se não houver nenhum ou se faltar uma das
peças compartilhadas. Num VPS que serve só o portal, copie só o `portal`; num
que serve os cinco, copie os cinco. Até 13/09/2026 o script exigia os cinco
nomes fixos e simplesmente não rodava em qualquer outra combinação.

O script precisa de `sudo` para escrever em `/etc/nginx` e recarregar o
serviço. Ao final, ele verifica `/health` de cada domínio que acabou de
instalar (lidos dos próprios vhosts, não de uma lista), negociação HTTP/2,
compressão e recusa de host desconhecido — esta última contra `127.0.0.1` com
um nome inexistente, para provar o `default_server` desta máquina e não o de
outra. Se alguma conferência operacional falhar apesar de `nginx -t` passar,
use o caminho de backup exibido pelo próprio instalador para restaurar a
configuração anterior.

Não inclua neste repositório credenciais, chaves privadas ou caminhos pessoais
para arquivos de autenticação.
