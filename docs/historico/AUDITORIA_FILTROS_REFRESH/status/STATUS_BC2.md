# STATUS BC2 (CRV) - lote concluido

- Aba: tab-20 (viewport 1366x900; fechada ao final)
- Casos: R001 a R037. Executados: 33. Nao executados: R002 (botao bloqueado), R015 e R022 (nao testados no lote), R017 (sem botao excluir na lista para a transacao de acao de teste).
- Contagem: OK 17; F 7 (R001, R006, R009, R011, R012, R020, R032); R 9 (R005, R013, R021, R026, R027, R028, R033, R034, R035); NE 4.
- LATERAL: 3 linhas (botao Adicionar do bloco de ticker de carteira sem clique em 1366x900; lista de transacoes sem excluir para acao; modo discreto ligado sem clique meu).
- Desfeito: carteira [AUD-BC2] (criada R003, excluida R019); corretora [AUD-BC2] (criada R027, excluida R035); transacao de teste (id 35, excluida R018); provento de teste (id 146, excluido ao fim); posicao de opcao de teste (id 9, excluida ao fim); contrato de opcao de teste (id 8, criado no R033 e excluido R034).
- Pendente: ticker de teste AUDBC2A (id 33). A exclusao virou arquivamento (tinha historico) e a tela nao oferece exclusao definitiva. Fica arquivado, sem a tag visivel, para o coordenador decidir.
- Nao tocados: carteira 2, carteira 1, corretora 1-5, tickers 1 e 32 (outros agentes), contrato 7, transacoes 16-18, opcao 4-6, 8.
- Filtro global de moeda e modo discreto: revertidos para o estado inicial (BRL, modo discreto desligado). Discreto apareceu ligado em algum ponto sem clique meu (ver LATERAL).
- Metodo: sonda reinjetada em cada pagina; navegacoes completas e POST com redirecionamento (F5, toggle, filtros globais) comparadas por URL e controles. Um clique por ref caiu em outro link do menu (R012), contornado com clique de link via JS, sem escrita.
