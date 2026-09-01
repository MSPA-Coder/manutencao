# Teste funcional pelo navegador — os 4 sistemas

Rodada iniciada em 2026-08-30. Objetivo: exercitar os quatro sistemas como um
usuário real os usa — menu por menu, item por item, incluindo, alterando,
excluindo, gerando relatórios, fechamentos e sorteios — e registrar tudo o que
aparecer de defeito, inconsistência ou oportunidade de melhoria.

Quatro agentes trabalham em paralelo, um por sistema. Cada um escreve o próprio
relatório neste diretório. Ao final, o orquestrador lê os quatro e produz
`CONCLUSOES_TRANSVERSAIS.md`: o que é específico de um sistema e o que deve ser
aplicado nos quatro.

## Decisões do mantenedor (30/08/2026)

1. **Autenticação:** o mantenedor faz os quatro logins no painel do navegador
   antes de começar. Os agentes herdam a sessão por origem. **Nenhum agente
   digita senha em tela de login.**
2. **Alvo:** somente as instâncias locais em Docker. **Nada toca o VPS.**
3. **Backup:** não foi feito backup prévio. A regra de ouro (item 4 abaixo)
   é a única proteção dos dados — cumprir ao pé da letra.

## Ambiente

| Sistema | URL local | Stack | Dados presentes em 30/08 |
|---|---|---|---|
| ConfortoTermico | http://127.0.0.1:5001 | Flask + SharedAuth | 5 zonas, 42 equipamentos, 44.642 leituras, 65.088 medições |
| MegaSena | http://127.0.0.1:5101 | Flask + SharedAuth | 3.046 concursos, 0 apostas geradas |
| ControleBancario | http://127.0.0.1:5201 | Django + HTMX | 714 lançamentos, 10 contas, 3 titulares, 21 categorias |
| ControleRendaVariavel | http://127.0.0.1:5301 | Flask + SharedAuth | 21 posições, 19 transações, 100 proventos, 7.329 cotações |

Contas ativas nos quatro: `mspa` (admin) e `Admin` (admin). O Bancário tem
ainda `Claudia` e `Esther` (perfil comum). MegaSena e CRV guardam três contas
`valida-*` **desativadas**, resíduo da rodada de reset de senha.

## Contrato de execução — vale para os quatro agentes

1. **Alvo fixo.** Só `http://127.0.0.1:<porta>` do seu sistema. Nunca endereço
   público, nunca o VPS, nunca a porta de outro agente.
2. **Aba própria.** Criar a própria aba (`tabs_create`, `foreground:false`),
   guardar o `tabId` e **passar `tabId` em toda chamada** de `navigate`,
   `computer`, `read_page`, `find`, `form_input`, `get_page_text`,
   `read_console_messages`, `read_network_requests`. Nunca chamar
   `tabs_select`, nunca fechar aba que não seja a sua. Quatro agentes dividem
   o mesmo navegador: sem essa disciplina um pisa no outro.
3. **Sessão emprestada.** A aba já entra autenticada como `mspa` (cookie por
   origem). **Não fazer logout. Não digitar senha em tela de login.** Se cair
   em `/login`, parar o bloco, anotar no relatório e reportar no resumo final:
   o mantenedor reloga.
4. **Regra de ouro dos dados.** Só criar, alterar e excluir **registros que o
   próprio agente criou**, sempre com o prefixo `ZZTESTE` no primeiro campo de
   texto que aceitar (se não couber, usar o valor mais reconhecível possível e
   anotar o identificador exato no relatório). **Nunca editar nem excluir
   registro preexistente.** Ao terminar cada bloco, apagar o que criou. O que
   não puder ser apagado pela tela vira pendência de limpeza no relatório, com
   o identificador exato.
5. **Rotas destrutivas: não acionar.** Cada prompt lista as do seu sistema.
   Registrar que existem, que foram deliberadamente evitadas, e por quê.
6. **Nada de mexer no produto.** Nenhum agente edita código, arquivo de
   repositório de aplicação, contêiner, banco por SQL ou configuração de
   Docker. As únicas escritas permitidas são o próprio relatório e o
   `ANDAMENTO.md`.
7. **Ler antes de fotografar.** Preferir `read_page` e `get_page_text` ao
   screenshot: o painel pode estar oculto e o texto é evidência melhor.
   Screenshot só quando a evidência for visual — gráfico, layout quebrado,
   sobreposição.
8. **Quando falhar, olhar por baixo.** `read_console_messages` com
   `onlyErrors:true` e `read_network_requests` para capturar 4xx/5xx. Erro de
   console e status HTTP entram na evidência.
9. **Gravação incremental.** Atualizar `RELATORIO_<sistema>.md` **ao fim de
   cada bloco**, nunca só no fim do trabalho. A sessão pode ser interrompida
   por limite a qualquer momento; o que não estiver em disco se perde.
   Atualizar também a linha do sistema em `ANDAMENTO.md`.
10. **Observar, não consertar.** Nenhuma correção, nenhuma sugestão aplicada.
    Achado bem descrito vale mais que conserto improvisado.

## Severidades

- **Bloqueio** — impede concluir a operação; tela quebra, 500, dado some.
- **Defeito** — resultado errado, cálculo incorreto, validação que não valida,
  permissão que não barra.
- **Inconsistência** — comportamento divergente entre telas do mesmo sistema
  ou entre os quatro sistemas (formato de data, número, mensagem, rótulo).
- **Melhoria** — funciona, mas custa mais do que devia a quem usa.
- **Observação** — fato registrado sem juízo; contexto para a análise final.

## Formato do achado

```
### [SIGLA-NN] Título curto
- **Severidade:** Bloqueio | Defeito | Inconsistência | Melhoria | Observação
- **Onde:** menu > submenu > item — rota
- **Passos:** 1. ... 2. ... 3. ...
- **Esperado:**
- **Obtido:**
- **Evidência:** trecho do texto da página, erro de console, status HTTP
- **Vale para os outros sistemas?** sim/não/talvez — por quê
```

Siglas: `CT` ConfortoTermico, `MS` MegaSena, `CB` ControleBancario,
`RV` ControleRendaVariavel.

## Bateria transversal — os quatro agentes fazem, no fim

Depois dos blocos específicos, cada agente cobre estes pontos e registra o
resultado numa seção própria do relatório. É o que permite comparar os quatro.

- **Console limpo:** navegar por todas as telas principais e conferir se sobra
  erro de console (CSP, HTMX, script bloqueado, 404 de asset).
- **HTMX:** telas que trocam fragmento sem recarregar — conferir se atualizam
  de fato, se o histórico do navegador continua coerente, se o botão Voltar
  não deixa a tela num estado impossível.
- **Formato pt-BR:** datas `dd/mm/aaaa`, números `1.234,56`, moeda `R$`,
  primeiro dia da semana, fuso `America/Sao_Paulo`. Anotar toda tela que fuja.
- **`/health`:** abrir e conferir 200 e o corpo.
- **Validação de formulário:** enviar vazio, com valor negativo onde não cabe,
  data inválida, texto onde espera número, texto longo demais. A mensagem
  aparece? É compreensível? Está em português?
- **Filtro, ordenação e paginação:** existem? Funcionam? Sobrevivem ao Voltar?
- **F5 depois de gravar:** reenviar formulário duplica registro?
- **Autorização:** alguma tela de administração abre para quem não deveria?
  (Testar sem trocar de conta: conferir o que o menu esconde e tentar a rota
  direta apenas em telas cujo acesso o próprio `mspa` não tem.)
- **Responsividade:** `resize_window` no preset `mobile` em duas ou três telas
  principais — menu, tabela grande e formulário. O que quebra?
- **Acessibilidade rasa:** campo sem rótulo, botão sem nome acessível,
  contraste obviamente ruim, foco invisível.

## Estado e retomada

`ANDAMENTO.md` é o ponto de retomada. Quem reabrir esta rodada lê aquele
arquivo primeiro, vê em que bloco cada sistema parou, e continua daí.
