# Estudo: SharedAuth 0.14 como versão única da frota

09/10/2026. Pedido do mantenedor:
1. a trava contra envio duplo da 0.14, como foi escrita, tem cara de quebra-galho;
2. todos os sistemas devem passar a usar a mesma versão, mesmo que isso exija mudanças.

## Conclusão

1. **Refazer a 0.14 antes de publicar.** A versão escrita hoje
   (`feat/envio-unico`, ainda não publicada) resolve o sintoma por um caminho
   escondido:
   - uma marca invisível no formulário;
   - destrave por tempo fixo de 15 segundos;
   - só cobre o envio comum, enquanto cada app tem a sua própria trava para o
     HTMX.

   A proposta abaixo troca isso por um **componente de envio único**, com
   estado visível, um mecanismo só para envio comum e HTMX, e liberação por
   evento, sem relógio.
2. **Levar os cinco sistemas ativos para a v0.14.0.** De v0.11 a v0.13 não há
   mudança incompatível de API (detalhe abaixo), então a subida é segura do lado
   da biblioteca. O trabalho de cada app é pequeno, salvo no MpPortal, que hoje
   não usa o componente visual.

## Onde cada sistema está

| Sistema | Framework | Versão hoje | Componente visual | Como confirma | Formulários POST / HTMX |
|---|---|---|---|---|---|
| ControleBancario | Django | **v0.13.0** | sim | `data-sa-confirmar` (24 telas) | 67 / 11 |
| ControleRendaVariavel | Flask | **v0.13.0** | sim | `data-sa-confirmar` (14) | 49 / 16 |
| MegaSena | Flask | **v0.11.0** | sim | `hx-confirm`, interceptado pela SharedAuth | 16 / 10 |
| ConfortoTermico | Flask | **v0.11.0**, fixado por *commit*, não por tag | sim | `data-sa-confirmar` (3) | 8 / 0 |
| MpPortal | Django | **v0.11.0** | **não** | nenhuma | 11 / 0 |
| NetWorth | — | v0.12.0 | — | — | fora: prova de conceito retirada em 29/09 |

## O que muda de v0.11 até v0.13 (sem quebra)

| Versão | O que trouxe | Afeta quem sobe? |
|---|---|---|
| entre 0.11 e 0.12 | pacote movido para `src/` | não: o nome de importação é o mesmo e o pip resolve |
| 0.12.0 | CSS de componentes visuais reutilizáveis | não: é acréscimo |
| 0.13.0 | `sanitizar_log` cerca de 20× mais rápido; cache opcional dos assets (`registrar_ui(..., max_age_segundos=)`) | não: o parâmetro é opcional |

Conferido no histórico (`git log v0.11.0..main`) e nos arquivos alterados de
cada tag: nenhuma assinatura pública mudou.

## Por que a 0.14 atual parece improvisada

1. **É invisível.** A pessoa clica de novo justamente porque nada indica que o
   envio está em curso. A marca escondida impede o segundo envio, mas não
   comunica nada; a causa do clique duplo continua.
2. **Tem um relógio arbitrário.** "Destrava em 15 s" é um número sem razão de
   domínio: curto demais numa importação lenta e longo demais num download.
3. **Cobre só metade.** Pega o POST comum. O HTMX ficou com cada app: o CB tem
   `data-enviando` e `hx-disabled-elt`, os outros não têm nada. Seriam três ou
   quatro travas diferentes na frota.
4. **Confunde cliente com garantia.** Uma trava no navegador reduz a duplicata,
   mas não a impede: duas abas, rede que reenvia, JavaScript que não carregou.
   A garantia está no servidor, e lá cada app está num estágio. O CB tem token
   de uso único; o CRV tem chave única, mas devolve **500** em vez de mensagem
   (L09).

## Proposta: componente "envio único" na 0.14

### No navegador (SharedAuth)

- **Um mecanismo para os dois caminhos.** Envio comum: o `submit` que ninguém
  segurou. HTMX: `htmx:beforeRequest` de um formulário ou de um elemento dentro
  dele. Os dois levam ao mesmo estado.
- **Estado visível.**
  - O formulário recebe `aria-busy="true"`.
  - Os botões de envio ficam `disabled`, com a classe `sa-enviando` (indicador
    no CSS da própria SharedAuth).
  - Há um texto opcional para o botão (`data-sa-enviando-texto="Salvando…"`).
  - Leitor de tela e olho veem a mesma coisa.
- **Liberação por evento, sem relógio.**
  - HTMX: `htmx:afterRequest`, com sucesso ou erro (o formulário com erro volta
    a ser editável).
  - Envio comum: a página troca.
  - Volta pelo cache do navegador: `pageshow`.
  - Formulário que **baixa arquivo**, onde a página não troca, declara
    `data-sa-envio-livre`. Opt-out explícito e documentado, no lugar do timer.
- **API para quem envia por conta própria.**
  - `window.sharedauth.travarEnvio(form)` e
    `window.sharedauth.liberarEnvio(form)`.
  - O CB usa as duas no envio por `htmx.ajax` e **apaga** a trava própria
    (`data-enviando`).
  - O `hx-disabled-elt` do `nav_escrita` também fica redundante.
- **A confirmação participa:** gatilho de um formulário em envio não reabre o
  modal (já está na versão atual).

### No servidor (cada app, com padrão documentado na SharedAuth)

A biblioteca não guarda estado de app: Django e SQLAlchemy têm armazenamentos
diferentes, e cada domínio sabe o que é duplicata. O README da SharedAuth passa a
descrever o padrão, e cada app aplica onde importa:
- **Há chave natural** (provento: titular, ticker, corretora, tipo, data e
  valor): restrição única no banco, mais tratamento do `IntegrityError` como
  "já cadastrado". Nunca 500. Esse é o caso do L09 no CRV.
- **Não há chave natural** (lançamento do CB, em que dois iguais podem ser
  legítimos): token de uso único gravado na mesma transação. Já está feito no
  CB.

### Testes

- **SharedAuth:** sentinelas no padrão do repositório (nenhum teste executa
  JS). Cobrem os dois caminhos de trava, a liberação por evento, o opt-out e a
  API pública.
- **Apps:** a regressão no navegador da Fase 3 inclui duplo clique em envio
  comum e em HTMX, erro de validação (o formulário tem de voltar editável) e
  download.

## Plano de adoção: todos na v0.14.0

| Passo | Sistema | Trabalho | Risco |
|---|---|---|---|
| 1 | SharedAuth | Refazer a 0.14 como acima; PR, CI e tag `v0.14.0` | baixo |
| 2 | CB | Fixar `v0.14.0`; trocar `data-enviando` pela API; tirar o `hx-disabled-elt` redundante; `quality` e regressão | baixo; entra nos PRs desta auditoria |
| 3 | CRV | Fixar `v0.14.0`; corrigir o L09; `quality` e regressão | baixo; entra nos PRs desta auditoria |
| 4 | MegaSena | v0.11 → v0.14; conferir `registrar_ui` e CSP; o `hx-confirm` continua; `quality` e teste no navegador | baixo; PR próprio |
| 5 | ConfortoTermico | trocar o pin por *commit* pelo pin pela tag `v0.14.0` (uniformidade); `quality` | baixo; trilha própria (ADR 008), mas a SharedAuth faz parte do contrato operacional |
| 6 | MpPortal | v0.11 → v0.14 na parte de autenticação e segurança; **adotar o componente visual** (CSS, JS e CSP) para ganhar confirmação e envio único nos 11 formulários POST | médio; VPS2 dedicado; PR próprio |
| — | NetWorth | não sobe: prova de conceito retirada | — |

Cada passo segue o fluxo da frota: branch, PR, CI verde, squash merge e deploy
com autorização. Os passos 2 e 3 vão junto com a auditoria. Os passos 4 a 6
formam um lote seguinte, que pode rodar enquanto a auditoria fecha.

## Decidido em 09/10/2026

1. **A 0.14 é refeita como componente de envio único.** A versão da branch é
   descartada.
2. **O MpPortal só sobe a versão.** O componente visual fica para depois, e o
   passo 6 perde a parte de CSS, JS e CSP.
3. **O ConfortoTermico passa a fixar por tag** `v0.14.0`.

## Implementado e testado (branch `feat/envio-unico`, commit `966da3a`)

- **JS e CSS refeitos** conforme a proposta: um mecanismo só, estado visível
  com `aria-busy` e botões desabilitados com indicador, liberação por evento,
  `data-sa-envio-livre` e a API `travarEnvio`/`liberarEnvio`.
- **README** com a seção "Envio único" e o padrão de garantia no servidor.
- **Testes:** 300 passam, ruff limpo, e a sentinela proíbe destrave por tempo.
- **No navegador**, o bloco foi injetado sobre a v0.13 numa aba do
  coordenador, porque a tag ainda não existe:
  - **POST comum** (novo provento no CRV): duplo clique em "Confirmar" seguido
    de um clique em "Salvar" criou **um** registro, sem 500. Antes, o mesmo
    ataque dava 500 (L09);
  - **HTMX** (Realizar no CB): durante a requisição, o formulário fica com
    `aria-busy="true"` e o botão desabilitado; o `htmx:afterRequest` libera
    tudo.

## Decisões para o mantenedor

1. Refazer a 0.14 como componente de envio único (recomendado) ou publicar a
   versão atual?
2. O MpPortal adota o componente visual na subida (recomendado, para ficar
   igual aos outros) ou sobe só a versão?
3. O ConfortoTermico passa a fixar por tag, como os outros (recomendado)?
