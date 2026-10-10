# STATUS A4 (CB, lote sozinho) - PARADO

- Aba: tab-5, FECHADA ao final (viewport 1366x900 foi aplicado nela; a aba foi encerrada).
- Caso atual: parado no caso 9.1 (permissoes). Motivo da parada: o classificador de permissoes negou a ferramenta javascript_tool nesta tela ("Permission for this action was denied by the Claude Code auto mode classifier"). Nenhuma outra acao foi tentada para contornar. Pedido ao coordenador: confirmar se javascript_tool volta a ser permitida antes de retomar.

## Feito (telas 1 a 9 parcial)
- Tela 1 tables/accounts: 1.F; 1.3 (validacao, sucesso); 1.2 (validacao, cancelar, sucesso, F5); 1.1 (cancelar, sucesso, voltar). Conta [AUD-A4] criada e excluida.
- Tela 2 tables/banks: 2.F; 2.3 (validacao, sucesso); 2.2 (sucesso); 2.1 (cancelar, sucesso). Criada, editada, excluida.
- Tela 3 tables/categories: 3.F; 3.3 (validacao, sucesso); 3.2 (sucesso); 3.1 (cancelar, sucesso); 3.4 (validacao, sucesso); 3.6 (sucesso); 3.5 (cancelar, sucesso). Categoria e grupo criados, editados, excluidos.
- Tela 4 tables/owners: sem filtro (N/A); 4.3 (validacao, sucesso); 4.2 (sucesso); 4.1 (cancelar, sucesso). Titular [AUD-A4] criado, editado, excluido.
- Tela 5 settings: 5.1 (validacao, salvar mesmo valor); 5.2 (salvar mesmo valor); 5.3 (salvar mesmo valor); 5.X1 data inicial (salvar mesmo valor). 5.4 NAO executado (ver abaixo).
- Tela 6 settings/profile: 6.1 tema (Dark e voltou a Corporate Blue); 6.2 rolagem (25 e voltou a 20); 6.X1 filtros globais (grupo administradas marcado, aplicado e desfeito).
- Tela 7 settings/audit-log: 7.F (dois filtros, F5, voltar).
- Tela 8 settings/database: 8.F (filtro, F5, voltar); 8.1 Health Check (confirmado). 8.2 otimizar NAO executado (regra do lote).
- Tela 9 permissions: 9.F (filtro de usuario, F5, voltar) feito. 9.1 INICIADO e NAO SALVO: desmarquei "Permitir ver Esposita" do usuario de teste (id 2) e remarquei; nao cliquei em "Salvar acessos por titular". Nada gravado. Estado do checkbox nao confirmado por DOM (javascript_tool negado).

## Nao feito
- Telas 10 (conciliacao), 11 (reclassificacao), 12 (atualizar saldo): NAO iniciadas. Sao as telas de escrita financeira do lote.
- 9.X e 9.1: restantes (Incluir, Excluir e Redefinir senha de usuario NAO devem ser executados: criam, apagam ou trocam senha de outras contas; o lote nao pede isso de forma explicita).
- 5.4 Executar Projecao Agora: nao executado (gera lancamentos em lote, sem desfazer previsto).
- 8.2 Otimizar: nao executado (regra do lote).
- Validacao e cancelar de 2.2, 3.2, 4.2 (edicao) e 5.2/5.3 (salvar) nao testados.
- 1.X "Ver posicao da conta" nao testado.

## Pendente de desfazer / verificar
- Nada [AUD-A4] sobrou criado: conta, instituicao, categoria, grupo e titular foram excluidos e verificados por DOM.
- Permissoes do usuario de teste (id 2, acesso ao titular Esposita): o checkbox foi desmarcado e remarcado sem salvar. Nada gravado no banco; conferir na tela de permissoes se a marcacao esta como antes.
- Configuracoes: senha, bloqueio, projecao e data inicial salvos com os mesmos valores (recarga R, valores iguais). Preferencias de perfil restauradas (corporate_blue, 20). Filtro global restaurado (currency=BRL).
- CONFLITO (nao executado): orcamento de teste (categoria Outros, 09/2026) sem prefixo, deixado pelo A2. Nao excluido: o protocolo proibe excluir o que nao foi criado pelo executor. Decisao do coordenador.

## Notas de metodo
- Sonda usada nas telas 1 e 2. A partir da tela 3, marcador window.__a4 + leitura de URL e DOM (desvio do protocolo, por contexto).
- Clique: ref com scroll_to; ref com centro (0,0) = fora da tela. Refs de dialogo: texto = X, Cancelar = X+1, confirmar = X+2.
- Filtros por HTMX nao recarregam; POST de cadastro, edicao, exclusao e configuracoes recarregam (R) e a URL perde os filtros.
- Voltar (historico) leva a entrada anterior sem filtro em varias telas: registrado como F.
