# Protocolo dos executores (leia inteiro antes de começar)

Você testa, no navegador embutido, se uma operação **perde filtros** ou **recarrega a
página sem necessidade**. Você **não corrige nada**, não lê nem altera código, e não
tira conclusão sobre causa. Você mede e registra.

Pasta de trabalho: `C:\Dev\VSCodeProjects\_manutencao\AUDITORIA_FILTROS_REFRESH\`
Seu lote: `lotes/LOTE_<SEU_ID>.md`. Seus arquivos de saída (só os seus):
`status/STATUS_<SEU_ID>.md` e `status/ACHADOS_<SEU_ID>.csv`.

## 1. Navegador: sua aba, só a sua

- Ferramentas `mcp__Claude_Browser__*`. **Primeira ação:** `tabs_create`, anote o
  `tabId` e passe esse `tabId` em **toda** chamada. Nunca use a aba da frente nem
  `tabs_select`; outros agentes estão usando o mesmo navegador ao mesmo tempo.
- Logo depois: `resize_window` com `width: 1366, height: 900` e o seu `tabId`. Se o
  retorno de alguma chamada deixar de dizer `emulating 1366x900`, aplique de novo.
- O login já está feito (CB em `http://127.0.0.1:5201`, CRV em
  `http://127.0.0.1:5301`). Se cair na tela de login, **pare** e registre no STATUS:
  você nunca digita senha.
- Clique **por `ref`** (de `find`/`read_page`), nunca por coordenada: a aba emulada
  aparece reduzida na captura. Screenshot só como evidência de achado, `scale: 0.5`.
- Economize contexto: `get_page_text` com `max_chars` ≤ 1500; `find` em vez de
  `read_page` completo; `read_page` com `filter: "interactive"` e `max_chars` ≤ 4000
  quando precisar. Use `browser_batch` para encadear passos previsíveis.
- Escrita de dado **só** por clique real e `form_input`. O `javascript_tool` serve só
  para a sonda e para ler o DOM.
- Muitas operações têm **dois diálogos** (o formulário e depois "Confirmar …"). Depois
  de cada clique de envio, rode `find` com o texto do botão esperado ("Confirmar",
  "Realizar", "Desfazer", "Excluir", "Salvar") até a operação de fato sair.

## 2. A sonda

Arquivo: `sonda.min.js`. Leia o arquivo (Read) **uma vez** e reutilize o texto.

- **Antes da operação:** `javascript_tool` com `<conteúdo de sonda.min.js>` seguido de
  `__sonda.instalar("<ID>-<caso>")`. Injete uma vez por carga de página. Depois de
  uma troca HTMX a sonda continua lá; basta `__sonda.instalar(...)` de novo.
- **Depois da operação:**
  `await new Promise(r=>setTimeout(r,1500)); typeof __sonda==="undefined" ? "SEM SONDA" : __sonda.ler()`
  - Se voltar `"SEM SONDA"`, **a página recarregou inteira**. Injete o conteúdo de
    novo e chame `__sonda.ler()` para obter o restante (o "antes" fica guardado na
    aba).
- **Leitura do resultado:**
  - `recarregou: true` ou evento `UNLOAD` indicam **R** (recarga cheia).
  - `url_perdeu` não vazio indica **F** (filtro perdido na URL). URL que só mudou a
    *ordem* dos parâmetros não é perda.
  - `filtros_mudaram`: um controle de filtro que mudou de valor ou sumiu também é
    **F**, ou **P** se só parte dos filtros se perdeu. Exceção: o próprio filtro que
    você mexeu de propósito.
  - `trocas` traz o alvo do HTMX. Se for `appMain`, `BODY` ou a página inteira
    quando bastava a linha ou a tabela, é **M**.
  - Eventos com `HX-Redirect`, `HX-Refresh` ou `HX-Location`: anote o cabeçalho.
  - `scroll`, `foco` e `abertos` que mudaram sem motivo indicam **S** (perda de
    rolagem, foco ou seção aberta).

## 3. Cada caso do lote

1. **Preparar a tela** com filtros fora do padrão. Escolha valores **existentes nos
   selects** do seu território:
   - no mínimo **2 filtros da tela** (incluindo filtro de coluna, se houver);
   - **moeda ou grupos globais** diferentes do padrão, quando a tela tiver o menu
     "Abrir filtros globais" (CB) ou o seletor de moeda (CRV);
   - **role a página** até a linha que vai operar.
2. Injete a sonda e chame `instalar`.
3. Faça a operação por clique real.
4. Leia a sonda e classifique o caso com **um** código, o mais grave:

   | Código | Quando |
   |---|---|
   | `R` | recarga cheia |
   | `M` | troca grande demais |
   | `F` | filtro perdido |
   | `P` | parcial |
   | `U` | a tela mostra o filtro, mas a URL não o tem |
   | `S` | rolagem, foco ou seção aberta perdida |
   | `C` | corrida |
   | `OK` | nada a apontar |

5. **Variações obrigatórias** de cada operação: sucesso; **erro de validação**
   (deixe um campo obrigatório vazio ou ponha um valor inválido); **cancelar**; e,
   depois do sucesso, **F5** (`navigate` para a mesma URL) e **voltar** (`navigate`
   com `"back"`). Em cada uma, os filtros continuam?
6. **Desfaça** o que criou ou alterou: exclua o que criou e reverta o que editou.
   Tudo o que você cria leva o prefixo `[AUD-<SEU_ID>]` na descrição ou no nome. Se
   não for possível desfazer, registre e siga.

**Excluir o que você mesmo criou** (`[AUD-<SEU_ID>]`) neste app local de
desenvolvimento faz parte do teste e está autorizado pelo mantenedor no plano
aprovado. A exclusão também é uma operação a medir. **Não** exclua nada que você
não criou.

**Antes de confirmar qualquer exclusão**, leia o texto do diálogo
(`get_page_text` ou `find`). Se ele não citar um nome com `[AUD-<SEU_ID>]`,
**cancele**. Já aconteceu de um `ref` errado abrir a exclusão de um registro
real.

**Registro sem campo de texto** (posição ou provento no CRV, por exemplo):
1. logo depois de criar, anote no STATUS o **id** do registro criado (está na
   URL de edição ou no link da linha) e a combinação que o identifica, como
   carteira, corretora, ticker e data;
2. a exclusão vale se a **URL** do formulário ou do diálogo trouxer **esse id**.
   Confira antes de confirmar. Se não der para ligar a exclusão ao id
   anotado, cancele e registre.

**Grupos padrão no CB:** "todos menos Administradas" é o padrão e **não** aparece
na URL. Com 4 dos 5 grupos marcados, a URL sem `grupos` está certa.

**Parâmetro padrão:** se só sumir da URL um parâmetro que tinha o valor padrão
(`currency=BRL` no CB, por exemplo) e a tela continuar mostrando o mesmo
filtro, isso **não** é perda. Registre `OK` com essa nota.

**Nunca** opere fora do seu território (contas, carteiras ou corretoras listadas no
lote). Você pode **ler** e **filtrar** qualquer coisa.

## 4. Registro

`status/ACHADOS_<SEU_ID>.csv`, uma linha por variação, com cabeçalho:

```
caso,sistema,tela_url_antes,operacao,variacao,codigo,url_depois,url_perdeu,filtros_mudaram,trocas,cabecalhos_hx,obs
```

- Valores com vírgula vão entre aspas.
- **Não escreva valores monetários, quantidades nem nomes de ativo ou pessoa.**
  Escreva nomes de filtro, URLs, ids, alvos de swap e cabeçalhos.
- `obs` ≤ 200 caracteres, só fato observado. Nada de "a causa é".
- **Defeito fora do escopo** (regra de negócio estranha, erro 500, texto
  contraditório, dado que não bate com o que a tela prometeu): registre numa
  linha com `codigo` = `LATERAL`, descreva o sintoma em `obs` e siga. O
  coordenador abre uma investigação separada para cada um.

`status/STATUS_<SEU_ID>.md`: **regrave ao fim de cada tela** (não de cada caso) com:
- a aba (`tabId`);
- o caso atual;
- os casos feitos e quantos não-OK;
- o que falta desfazer;
- notas de método para você mesmo.

Se a sessão cair, quem retomar lê só isso.

## 5. Fim

Quando o lote acabar, confira que não sobrou nada `[AUD-<SEU_ID>]` sem desfazer,
feche a sua aba (`tabs_close`) e responda em **até 15 linhas**:
- casos feitos;
- contagem por código;
- os 5 casos mais graves (caso + código + uma frase);
- o que ficou sem testar e por quê.
