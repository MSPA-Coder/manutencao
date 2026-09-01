# STATUS_MS.md

**Bloco atual:** concluído — todos os 7 blocos executados
**Blocos concluídos:** 1 (menu), 2 (dashboard), 3 (concursos), 4 (gerar apostas), 5 (configurações), 6 (usuários/senha), 7 (bateria transversal)
**Achados por severidade:** Bloqueio 1 (MS-10) | Defeito 2 (MS-11, MS-14) | Inconsistência 7 (MS-01, MS-03, MS-06, MS-12, MS-16, MS-17, MS-18) | Melhoria 2 (MS-05, MS-07) | Observação 5 (MS-02, MS-04, MS-08, MS-09, MS-13)
**Limpeza pendente:** SIM (uma crítica, uma leve) — ver abaixo. Estado final verificado por leitura direta em 31/08/2026.

## PENDÊNCIA DE LIMPEZA 1 (crítica) — apostas salvas, sem forma de remover pela tela
`/bets/clear` ("Limpar filtros") não remove apostas salvas — só reseta o
formulário (MS-14). Não existe botão de excluir gerações na interface. A
única rota que remove apostas é `/reset`, que também apaga os 3.046
concursos reais — não posso acioná-la.
**Resíduo exato confirmado no banco (verificado por último em 31/08/2026):**
- Geração #5 — 3 apostas: `05-16-20-22-26-59`, `12-22-32-39-46-47`,
  `01-06-14-40-43-57` (salva 31/08/2026 02:34)
- Geração #6 — 2 apostas: `04-21-30-44-45-52`, `01-07-30-34-47-51` (salva
  31/08/2026 02:37)
- Total: 5 apostas de teste (números aleatórios, sem ligação a concurso
  real). **Resolução exata:** só é removível via acesso direto ao banco
  (`DELETE` nas tabelas de apostas geradas para as gerações 5 e 6), fora do
  escopo deste agente ("nada de... banco por SQL").

## PENDÊNCIA DE LIMPEZA 2 (leve) — usuário de teste não pode ser excluído
`ZZTESTE-ms` (id=13) existe na tabela de usuários, estado final
"Operador, Inativo" — sem acesso possível (inativo), mas não há botão de
excluir usuário na interface, só ativar/desativar. **Resolução exata:**
remover a linha do usuário id=13 diretamente no banco, se o mantenedor
quiser eliminar o registro por completo; do contrário, pode ficar como o
resíduo `valida-*` de rodadas anteriores (mesmo padrão, inofensivo).

## Não verificado por bloqueio da própria ferramenta de automação
Tentativa de `mspa` rebaixar/desativar a própria conta foi bloqueada pelo
classificador de segurança do Claude Code antes de sair do agente. Não
contornei o bloqueio. Não sei se o Mega Sena AI recusaria essa ação.

## Não verificado por limitação de ferramenta de navegador
Toda a bateria de importação por arquivo (planilha válida com concursos
≥900001, e os 6 casos malformados) não pôde ser testada: as ferramentas
`mcp__Claude_Browser__*` desta rodada não expõem upload de arquivo local, e
não há forma seguraa de contornar isso sem trocar de navegador/sessão
(MS-09).

## Os três achados mais graves
1. **MS-10 (Bloqueio):** "Calcular parâmetros" (`/bets/filter-targets/fragment`)
   retorna 500 Internal Server Error em 100% das tentativas, mesmo com os
   valores padrão do formulário — recurso inteiramente inutilizável.
2. **MS-11 (Defeito):** combinação de filtros impossível ou contraditória
   (ex.: mínimo de pares 7, ou mínimo > máximo) não é detectada — o sistema
   gera apostas "com sucesso" e sem aviso, mas elas **violam o próprio
   filtro pedido** (ex.: pediu no máximo 4 pares, saiu aposta com 6 pares).
3. **MS-14 (Defeito):** não existe, pela tela, nenhuma forma de excluir
   apostas já salvas — só a rota destrutiva `/reset`, que também apaga os
   concursos reais. É a causa direta da pendência de limpeza crítica acima.

## Pontos fortes confirmados (para o resumo final)
Fechamento matemático (closure_numbers) correto e bem testado em 3
fronteiras; `/rationale` matematicamente honesto, sem prometer vantagem
probabilística; validação de URL em Configurações correta; segurança de
senha sólida (senha atual incorreta sempre barra; senha temporária mostrada
uma única vez, sem vazar); responsividade mobile sem quebras nas 3 telas
testadas; acessibilidade rasa sem falhas encontradas (labels, alt, foco
visível); console organicamente limpo.

## Nota de método (relevante para os outros agentes/orquestrador)
`computer{action:"left_click"}` (coordenada ou ref) **não funciona** numa
aba em segundo plano deste navegador compartilhado — o clique "executa" sem
erro mas não navega nem envia formulário. Solução usada: `javascript_tool`
com `elemento.click()` real (dispara os mesmos listeners nativos, inclusive
HTMX) e `fetch()` direto às rotas para testes em lote. `screenshot` e
`read_page` também falham em segundo plano, MAS **voltam a funcionar depois
de qualquer chamada a `resize_window`** (usada para o teste de
responsividade) — descoberta útil se outro agente tiver o mesmo problema.

## Remediação das prioridades imediatas — 01/09/2026

- **MS-10 — resolvido:** o fragmento de cálculo agora transforma a renderização
  em uma resposta HTTP antes de adicionar cabeçalhos HTMX; a rota deixa de
  tentar acessar `.headers` em uma string.
- **MS-11 — resolvido:** entradas externas passam por validação estrita.
  Intervalos inválidos, mínimo maior que máximo, valores fora da faixa e
  critérios contraditórios retornam **HTTP 400 com mensagem visível**, sem
  correção silenciosa nem aposta apresentada como sucesso.
- **Defesa adicional:** o serviço de geração repete a validação estrita, para
  que chamadas fora da rota web também não contornem o contrato.
- **Validação:** Ruff aprovado, **115 testes** aprovados e aplicação/PostgreSQL
  reconstruídos e saudáveis na porta 5101.
