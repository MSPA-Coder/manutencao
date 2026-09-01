# Prompt do agente — MegaSena (sigla MS)

Alvo: `http://127.0.0.1:5101`. Relatório: `RELATORIO_MegaSena.md`.
Ler `README.md` deste diretório antes de começar: o contrato de execução vale
integralmente e não se repete aqui.

Ferramenta de apoio para importar resultados da Mega-Sena, consultar
estatísticas e organizar apostas e fechamentos. O banco tem **3.046 concursos
importados e nenhuma aposta gerada** — o gerador está com a mesa limpa, e é
onde há mais a testar.

Aviso de domínio que o próprio sistema faz: frequências e filtros descrevem o
histórico carregado, **não preveem sorteio nem aumentam chance**. Conferir se a
interface mantém esse aviso onde ele importa e se nenhum rótulo promete
previsão. Se prometer, é achado.

## Bloco 1 — Varredura do menu

Menu superior: **Dashboard · Gerar apostas · Concursos · Configurações ·
Usuários · Minha senha** (+ sair). Abrir cada um, confirmar carga, rótulo
coerente e marcação do item ativo. Registrar a estrutura real encontrada.

## Bloco 2 — Dashboard e estatísticas

Com 3.046 concursos, os números têm de fazer sentido.

- Conferir totais: quantidade de concursos, faixa de números de concurso,
  data do primeiro e do último.
- Frequência por dezena: a soma das frequências deve bater com
  `6 × nº de concursos`. Fazer essa conta e registrar o resultado — é o teste
  mais barato de sanidade estatística que existe aqui.
- Números atrasados, pares/ímpares, distribuição por faixa: conferir
  coerência interna entre os painéis.
- Trocar filtro de período, se houver, e ver se os números acompanham.

## Bloco 3 — Concursos (importação e consulta)

- Listagem: paginação, ordenação, busca por número de concurso, filtro
  "somente premiados" (`winners_only`). Pedir concurso inexistente (por
  exemplo, 999999) e ver o que a tela responde.
- Importação por arquivo: montar um arquivo pequeno e válido com **concursos
  de número muito alto e inexistente** (por exemplo, a partir de 900001) para
  não colidir com o acervo real, importar, conferir que entrou, e **apagar
  depois se a tela permitir**. Se não permitir apagar, registrar como pendência
  de limpeza com os números exatos importados.
- Testar a importação com arquivo malformado: coluna faltando, data inválida,
  dezena fora de 1..60, seis dezenas repetidas, arquivo vazio, arquivo de outro
  tipo. Cada recusa (ou aceitação indevida) é um achado.
- Importação por link (`/contests/import-link`): conferir a validação da URL.
  Se a tela tentar buscar de fato na internet, registrar o comportamento e o
  que acontece sem rede — **não usar URL arbitrária de terceiros**; usar a que
  já estiver configurada no sistema.
- Reimportar um concurso já existente: duplica, atualiza ou recusa? O que a
  tela promete é o que faz?

## Bloco 4 — Gerar apostas, fechamentos e sorteios

O coração do sistema, e a área com mais superfície de teste.

- Filtros: soma mínima e máxima, pares mínimo e máximo, consecutivos, mínimo
  de faixas ocupadas, máximo por faixa, quantidade de apostas, percentual
  alvo (`target_percentage`), dezenas de fechamento (`closure_numbers`).
- Para cada filtro, testar a fronteira: valor mínimo, valor máximo, mínimo
  maior que o máximo, zero, negativo, campo vazio, texto onde espera número.
- **Combinação impossível** (por exemplo, soma mínima 300 com 6 dezenas, ou
  pares mínimo 7): a tela deve explicar que nada satisfaz, não travar nem
  devolver lista vazia sem aviso.
- Prévia (`/bets/preview`): conferir que a prévia respeita os filtros. Pegar
  três apostas da prévia e **verificar na mão**: soma dentro da faixa, contagem
  de pares dentro da faixa, dezenas entre 1 e 60, sem repetição, quantidade de
  dezenas correta. Divergência aqui é Defeito, não Melhoria.
- Fechamento: gerar com dezenas de fechamento definidas e conferir que **todas
  as apostas contêm as dezenas fixadas**. Testar fechamento com mais dezenas
  do que cabe numa aposta.
- Justificativa (`/rationale`): conferir que explica de fato o critério usado
  e que não afirma vantagem probabilística.
- Salvar as apostas geradas, conferir que aparecem em "Gerações realizadas",
  e depois **limpar** (`/bets/clear`) — o banco tinha zero apostas antes desta
  rodada, então o estado final deve voltar a zero. Confirmar que voltou.
- Alvos de filtro (fragmento `/bets/filter-targets/fragment`): conferir que o
  fragmento HTMX atualiza sem recarregar e sem erro de console.

## Bloco 5 — Configurações

Tela `/settings`, com a URL de origem dos resultados
(`results_source_url`) entre os campos. **Anotar o valor original antes de
mexer e restaurá-lo ao final do bloco.** Testar URL malformada, campo vazio e
esquema não-http. Conferir se a configuração afeta a importação por link.

**Rota destrutiva — não acionar:** `/reset`. Apaga o acervo. Registrar onde ela
aparece na interface, se pede confirmação e se avisa do risco. **Inspecionar
sem clicar.**

## Bloco 6 — Usuários e senha

Telas: `/usuarios`, `/usuarios/<id>/ativo`, `/usuarios/<id>/papel`,
`/usuarios/<id>/senha`, `/minha-senha`.

- Listar: devem aparecer `mspa` e `Admin` ativos, e `valida-admin`,
  `valida-usuario` e `valida-next` **desativados** (resíduo de rodada anterior;
  não excluir, só registrar que continuam ali).
- Criar `ZZTESTE-ms` como operador. Conferir se a criação devolve senha
  temporária mostrada uma única vez e se ela **não** passa por mensagem flash,
  não fica no HTML de páginas seguintes e não aparece na URL — a sessão do
  Flask é assinada, não cifrada. Segredo vazado aí é achado grave.
- Alternar papel (operador ↔ admin) e estado ativo de `ZZTESTE-ms`.
- Redefinir a senha de `ZZTESTE-ms` pelo botão do admin: senha temporária
  aparece uma vez só, recarregar não mostra de novo, conta fica com troca
  pendente.
- Tentar rebaixar ou desativar a **própria** conta (`mspa`): a tela deve
  recusar. Registrar o que faz.
- **Não fazer login como `ZZTESTE-ms`.** Registrar como não verificado o que
  depender disso.
- `/minha-senha` como `mspa`: abrir e conferir validação, **sem concluir a
  troca**.
- Excluir ou desativar `ZZTESTE-ms` ao final, conforme a tela permitir.

## Bloco 7 — Bateria transversal

Conforme a seção "Bateria transversal" do `README.md`. Aqui, atenção especial
ao volume: a listagem de 3.046 concursos é a maior tabela dos quatro sistemas —
medir a resposta da primeira página, da última página e da ordenação.
