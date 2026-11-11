# Nginx central do VPS

Esta pasta é a fonte versionada da configuração compartilhada em
`/etc/nginx/`. Editar os arquivos aqui não altera o servidor. A instalação é
uma operação explícita e deve usar [`instalar.sh`](instalar.sh), que salva a
configuração atual, instala os arquivos, executa `nginx -t`, restaura o estado
anterior se a validação falhar e só recarrega o Nginx quando a sintaxe é válida.

## Arquivos

| Fonte | Destino em `/etc/nginx/` | Função |
|---|---|---|
| `conforto-termico`, `controle-bancario`, `controle-renda-variavel`, `megasena`, `wealthfolio`, `viva-passo`, `villa-rica` | `sites-available/` | Vhosts TLS da frota. O arquivo `wealthfolio` serve `wealthfolio-mspa.duckdns.org` e encaminha para o Wealthfolio na porta 18088. `viva-passo` e `villa-rica` servem checkouts estáticos privados em `/home/ubuntu/apps/`, exigem autenticação HTTP por arquivo protegido no VPS e respondem `{"status":"ok"}` em `/health` sem autenticação, para o deploy e o vigia. Os vhosts variam por domínio, porta e `client_max_body_size`; os do CB e do CRV fecham `/patrimonio/` e o do CRV também `/fechamento/`. Os dois sites estáticos servem só uma lista de arquivos (o resto do checkout dá 404 antes da senha: arquivo novo do site entra na lista do vhost), mandam cabeçalhos de segurança e limitam tentativas pela zona `basica` (30r/m, burst 120). Esta pasta é a fonte de TODOS os vhosts da frota; quais deles vão para um servidor é decidido pelo diretório de origem usado na instalação (abaixo). |
| `recusa-host-desconhecido` | `sites-available/`, com link em `sites-enabled/` | Servidores padrão: na 443 recusa o handshake de nomes desconhecidos; na 80 fecha a conexão (444), exceto o desafio ACME em `/var/www/html`. O instalador desabilita o `default` do pacote e põe `server_tokens off` no `nginx.conf`. |
| `conf.d/00-comum.conf` | `conf.d/` | Tipos gzip, chave por método e zona compartilhada do limitador de login e a zona `basica` da autenticação básica dos sites estáticos. |
| `snippets/proxy-app.conf` | `snippets/` | Cabeçalhos e timeout comuns aos proxies. |

O prefixo `00-` garante que `map` e `limit_req_zone` sejam carregados antes dos
vhosts. `proxy_pass` permanece em cada vhost porque a porta é específica de
cada aplicação.

## Contratos

- HTTP redireciona para HTTPS, preservando o desafio ACME.
- TLS usa os certificados do Certbot e emite HSTS por uma fonte só: o
  `add_header` do vhost. O HSTS que a aplicação mandar é descartado pelo
  `snippets/proxy-app.conf`, e o instalador confere que cada domínio responde
  com exatamente um cabeçalho.
- Hosts desconhecidos são recusados durante o handshake TLS e, na porta 80,
  com a conexão fechada sem resposta.
- Os cabeçalhos `Host`, `X-Real-IP`, `X-Forwarded-For` e
  `X-Forwarded-Proto` são encaminhados às aplicações.
- Gzip cobre texto, CSS, JavaScript, JSON, XML, SVG e WASM; WOFF2 permanece de
  fora porque já é comprimido.
- A zona `login` é compartilhada pelo Nginx. Somente `POST /login` consome o
  limite; `GET /login` permanece livre. O limite é `10r/m`, com burst 5 sem
  atraso, e rejeições respondem 429.
- `/patrimonio/` responde 404 nos vhosts do ControleBancario e do
  ControleRendaVariavel, sem chegar à aplicação. O contrato de patrimônio é
  máquina a máquina e o único consumidor, o Wealthfolio, lê pela rede Docker
  interna `patrimonio-internal`. `tests/nginx_test.sh` prova a recusa com
  pedidos de verdade, e o instalador confere o 404 em cada domínio que fecha a
  rota.
- Os vhosts usam `listen ... ssl;` seguido de `http2 on;` (Nginx 1.25.1 ou
  superior, o que vale no VPS1: Ubuntu 26.04, Nginx 1.28). A forma
  antiga `listen ... ssl http2` está obsoleta e gera aviso no `nginx -t`.

## Instalação

Disponibilize no VPS um diretório controlado pelo operador contendo
`conf.d/00-comum.conf`, `snippets/proxy-app.conf`, `recusa-host-desconhecido` e
**os vhosts que esta máquina serve** — e execute, a partir dele:

```bash
sudo -v
./instalar.sh "$(pwd)"
```

O conteúdo desse diretório é o que declara quais sites o servidor atende: o
instalador entrega **e habilita** os vhosts que encontrar ali, lista quais são
antes de tocar em qualquer coisa, e recusa rodar se não houver nenhum ou se
faltar uma das peças compartilhadas. Copie só os vhosts do que aquela máquina
serve (hoje só o VPS1, com todos os aplicativos; um servidor futuro, só o que
ele hospedar).

O script precisa de `sudo` para escrever em `/etc/nginx` e recarregar o
serviço. Ao final, ele verifica `/health` de cada domínio que acabou de
instalar (lidos dos próprios vhosts, não de uma lista), negociação HTTP/2,
compressão e recusa de host desconhecido — esta última contra `127.0.0.1` com
um nome inexistente, para provar o `default_server` desta máquina e não o de
outra. Se alguma conferência operacional falhar apesar de `nginx -t` passar,
use o caminho de backup exibido pelo próprio instalador para restaurar a
configuração anterior.

No VPS1, use `instalar-vps1-villa-rica.sh`. Ele entrega os cinco aplicativos
já ativos, o Viva Passo e o Villa Rica, preservando a seleção explícita de
vhosts desta máquina.

Não inclua neste repositório credenciais, chaves privadas ou caminhos pessoais
para arquivos de autenticação.
