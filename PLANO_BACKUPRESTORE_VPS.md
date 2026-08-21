# Plano — backup dos dados de produção, em duas camadas

Iniciado 2026-08-19, **concluído em 2026-08-20** (backup diário verificado,
catalogado, agendado e documentado ponta a ponta). **Reescrito em 2026-08-20** — a primeira versão punha este
computador para disparar `pg_dump` na produção pela rede. Estava errado de
desenho, não de implementação; a seção 3 explica por quê e o que entrou no lugar.

**Status: concluído em 2026-08-20 — as oito fases estão feitas e validadas.**
A produção do VPS tem backup diário verificado, buscado e catalogado sozinho
todo dia, com um ensaio de restauração real já confirmado contra a produção.
A cópia das configurações do nginx em `_manutencao/vps/nginx/` (D5), pendência
fora das oito fases, foi feita em 2026-08-20 — ver seção 22.

Documentos irmãos: [PLANO_RESSINCRONIZACAO_VPS.md](PLANO_RESSINCRONIZACAO_VPS.md)
(fluxo local → GitHub → VPS, concluído) e
[PLANO_MANUTENCAO.md](PLANO_MANUTENCAO.md).

---

## 1. O problema

Os dados que estão em produção, no VPS, **não têm backup nenhum**. Verificado no
servidor em 2026-08-19:

- não existe `crontab` — o comando nem está instalado;
- os únicos temporizadores do `systemd` são do sistema operacional e do certbot;
- o único dump de produção que existe é o de `C:\Users\MSPA\VPS-Backup-20260819\`,
  tirado à mão durante a ressincronização. Congelou no dia 19/08.

O plano de ressincronização já tinha dito o essencial: **"Verdade do código: o
`main`. Verdade dos dados: o VPS."** O código está em três lugares. Os dados de
produção, em um.

Se o VPS for perdido hoje, perdem-se 7.356 cotações, 3.045 sorteios, 860 linhas
de auditoria bancária, 717 lançamentos, e os equipamentos e leituras do conforto
térmico — tudo desde que os aplicativos entraram no ar.

### E o backup local também não roda sozinho

Conferido em 2026-08-20, e vale registrar porque sustenta a decisão da seção 3:

- **não existe tarefa agendada `BackupRestore` nesta máquina.** O `README.md`
  documenta o comando `schtasks` que a cria, mas ela nunca foi criada (ou foi
  removida);
- o artefato mais recente no catálogo é de **2026-08-16T12:34** — quatro dias
  atrás, e disparado à mão.

Não é uma crítica ao projeto; é dado. Um esquema de backup que depende de alguém
lembrar de rodar já demonstrou, aqui mesmo, o que acontece.

---

## 2. O que foi levantado

Conferido no servidor e no código. Não é estimativa.

| Item | Valor |
|---|---|
| Máquina | Ubuntu / kernel `6.17.0-1020-oracle`, ARM64, Docker 29.7.2 |
| Disco | 193 GB, 186 GB livres |
| Contêineres | 9, todos `healthy` |
| PostgreSQL | **17.11** nos quatro, imagem `postgres:17-alpine` |
| Usuário `ubuntu` | pertence aos grupos `docker` e `sudo` |
| Agendamento | `cron` **não instalado**; `systemd` disponível e em uso |
| Fuso do servidor | UTC (03:00 de São Paulo = 06:00 lá) |

Tamanho dos volumes — a ordem de grandeza do que será copiado:

| Volume | Tamanho |
|---|---|
| `controle-bancario_postgres_data` | 68,95 MB |
| `controle-renda-variavel_postgres_data` | 68,20 MB |
| `mega-sena_postgres_data` | 66,31 MB |
| `conforto-termico_postgres_data` | 49,14 MB |

O volume inclui índices e WAL; o dump comprimido é bem menor. Localmente os
quatro projetos ocupam 32 MB de artefatos. Espere **poucos MB por dump**. Espaço
e banda não são questão em lugar nenhum deste plano.

### Duas descobertas que mudam o desenho

**1. Os nomes dos contêineres do VPS são idênticos aos daqui.**

```
conforto-termico-postgres-1        controle-bancario-postgres-1
mega-sena-postgres-1               controle-renda-variavel-db-1
```

A trava que impede restaurar por cima de um projeto real
(`CONTAINERS_PROTEGIDOS`, em `projetos.py`) é hoje uma **lista de nomes**. Um
nome sozinho deixa de identificar um alvo no momento em que existem duas
máquinas. Hoje isso protege o VPS por acidente. Acidente não é trava. Ver **D3**.

**2. O ConfortoTermico não tem `.secrets/` no servidor.** Os outros três têm; ele
guarda tudo em `.env.docker`. O `KIT_RECUPERACAO.md` descreve só as pastas daqui
e está incompleto para produção. Ver **D5**.

### Achados de arrumação, sem relação com o backup

- `/home/ubuntu/resync-backup-20260819.tgz` e `/home/ubuntu/_resync_backup_20260819`
  continuam no servidor e **contêm senhas em texto puro**. Já existe cópia em
  `C:\Users\MSPA\VPS-Backup-20260819\`; a do servidor pode sair.
- `/home/ubuntu/controle-renda-variavel.conf` e `/home/ubuntu/renda-http.conf`:
  sobras de configuração do nginx soltas na pasta pessoal.
- `apps/mega-sena/.env.vps.antes-da-correcao`: sobra da Fase 2 da ressincronização.

---

## 3. O desenho: duas camadas

### Por que a primeira versão estava errada

Ela fazia este computador abrir SSH para a produção às 3h e disparar `pg_dump` lá
dentro. Funcionaria — e amarrava o backup da produção a quatro coisas que não têm
relação nenhuma com a produção: **o PC estar ligado, o Docker Desktop estar de
pé, a rede estar boa e a chave estar aqui.** Uma viagem de uma semana com o PC
desligado seria uma semana sem backup, com o servidor ligado o tempo todo sem
fazer nada a respeito. A seção 1 mostra que esse risco não é teórico.

### A correção

**Quem produz o backup é quem tem os dados.** O servidor está ligado 24 horas por
natureza — é a definição dele.

```
Camada 1   VPS produz e guarda           todo dia, sozinho, sem rede
                    ↓
Camada 2   este PC busca, verifica       quando puder — não precisa ser pontual
           e limpa o servidor
```

**A propriedade que faz o desenho funcionar: a camada 2 pode falhar à vontade.**
Se o PC ficar cinco dias desligado, nada se perde — o servidor guardou os cinco
dumps e o PC busca todos quando voltar. A camada 2 não precisa de pontualidade,
só de acontecer de vez em quando.

### Agendamento: timer do systemd, não cron

`cron` nem está instalado no servidor. O mecanismo nativo do Ubuntu é o **timer
do systemd**, e aqui ele é melhor por um motivo concreto: **`Persistent=true`**.
Se o servidor estiver desligado na hora marcada, o cron perde aquela execução em
silêncio; o timer roda assim que voltar. Ele também registra no journal e aparece
em `systemctl list-timers` — foi esse comando que provou que não existe backup
hoje.

Como o servidor está em UTC, `OnCalendar` usa `06:00` para rodar às 03:00 de
São Paulo (ou declara o fuso explicitamente).

---

## 4. Camada 1 — o servidor faz o seu backup

Um `~/backup-db.sh`, ao lado do `deploy.sh`, no mesmo padrão de infraestrutura do
servidor que já foi aprovado. Todo dia, para os quatro projetos:

1. `docker exec <contêiner> pg_dump --format=custom --no-owner --no-acl` para um
   arquivo temporário;
2. **confere o dump com `pg_restore --list`** — código de saída zero não prova
   nada, é a regra 2 do projeto;
3. só então dá o nome definitivo (regra 1, escrita atômica) e grava um `.sha256`
   ao lado;
4. aplica a retenção própria (seção 4.1).

```
/home/ubuntu/backups/<projeto>/<projeto>_banco_<carimbo>.dump
/home/ubuntu/backups/<projeto>/<projeto>_banco_<carimbo>.dump.sha256
```

O `pg_dump` roda **dentro do contêiner do próprio projeto**, então a versão da
ferramenta é sempre a do servidor. Nada de novo precisa ser instalado no VPS.

**Esta camada sozinha já resolve o acidente que de fato acontece:** uma migração
que deu errado, uma linha apagada por engano, um import que duplicou tudo. Para
todos esses, o backup estar no mesmo servidor é indiferente — e a recuperação não
depende de mais nada.

### 4.1 Retenção do servidor: rede de segurança, não o alvo

O servidor guarda **até 14 dias** por conta própria. Essa regra existe só para um
caso: **o PC nunca mais voltar.** Sem ela, uma ausência longa encheria o disco.

Na operação normal ela quase nunca age, porque a camada 2 limpa antes — é a
seção 5.2.

---

## 5. Camada 2 — o BackupRestore busca, verifica e limpa

O BackupRestore **deixa de falar com a produção**. Ele não dispara `pg_dump`, não
consulta contêiner, não liga nem desliga nada. Ele busca arquivos prontos.

Isso é uma simplificação grande e uma redução de risco maior ainda: some a
possibilidade de uma conexão caindo no meio de um dump, some a necessidade de
alcançar um contêiner de produção, e some a regra inteira de "nunca mexa no
estado dos contêineres de lá" — não há mais como.

### 5.1 O ciclo, na ordem exata

Para cada projeto, para cada dump que existe no servidor e ainda não está aqui:

1. **buscar** o arquivo e o `.sha256`;
2. **conferir o SHA-256** do arquivo recebido contra o do servidor — pega
   corrupção ou transferência cortada;
3. **reler no sandbox local** com `pg_restore --list` — é a regra 2 aplicada de
   novo, agora do lado de cá;
4. **registrar no catálogo** como artefato válido;
5. **só agora, apagar do servidor** — e apenas os que não são o mais recente.

O sandbox daqui é `postgres:17-alpine` e os quatro servidores rodam PostgreSQL
**17.11**: mesma versão principal, a releitura funciona.

**O carimbo de tempo vem do servidor, não da hora do download.** Se o PC passou
cinco dias fora, entram cinco artefatos com as datas em que os dados foram
capturados — não cinco artefatos carimbados hoje.

### 5.2 A limpeza do servidor

**Depois de um ciclo bem-sucedido, o servidor fica com exatamente um dump por
projeto: o mais recente.**

Três condições, e nenhuma é negociável:

- **Só se apaga o que já foi verificado aqui.** Baixado não basta. Um arquivo que
  falhou no SHA-256 ou no `pg_restore --list` **permanece no servidor** — é a
  regra 3 do projeto ("nunca apagar antes de ter o substituto") atravessando a
  rede.
- **O mais recente nunca é apagado**, mesmo já verificado. Assim o servidor
  continua capaz de se recuperar sozinho até o dia anterior, sem depender deste
  computador.
- **O piso é imposto no servidor, não aqui.** O agente do lado de lá recusa
  apagar o arquivo mais novo, aconteça o que acontecer. Um erro de programação ou
  um cliente comprometido não conseguem esvaziar a pasta.

**Por que apagar, já que espaço não é problema:** cada dump parado no servidor é
uma cópia completa do banco num arquivo — muito mais fácil de levar embora do que
o banco vivo. Guardar um em vez de quatorze reduz o que um invasor encontra.

---

## 6. Acesso ao servidor

### D1 — chave dedicada, travada, com quatro verbos

Uma segunda chave SSH, diferente da de administração, presa no `authorized_keys`
por `command=` a um `~/backup-agent.sh` que só sabe fazer quatro coisas:

| Verbo | O que faz |
|---|---|
| `listar` | nomes, tamanhos e SHA-256 dos dumps disponíveis |
| `enviar <arquivo>` | despeja um dump na saída padrão |
| `apagar <arquivo>` | remove um dump — **recusa o mais recente** |
| `estado` | último backup de cada projeto e se o timer está saudável |

**Por que não a chave de administração:** ela ficaria num arquivo deste
computador, usada por tarefa automática sem ninguém olhando, e o usuário `ubuntu`
está no grupo `docker` — na prática, administrador do servidor. Se vazar, vaza o
servidor inteiro.

**O que a chave dedicada pode fazer de ruim, dito sem maquiagem:** ler os dumps
(ou seja, ler os dados) e apagar dumps já verificados. Não alcança os bancos
vivos, nem os contêineres, nem o código, nem o resto do sistema de arquivos. O
`apagar` é o preço da limpeza da seção 5.2, e por isso o piso do "mais recente"
é imposto do lado de lá.

Valida com dois testes na Fase 1: a chave nova responde `estado`, e a chave nova
**não** abre um shell.

### D7 — o endereço do servidor fica fora do Git

Endereço, usuário e caminho da chave vão para `configuracao.local.json`, que já
está fora do Git — não para `projetos.py`, que é versionado.

E vale a trava que já existe para a raiz de backup: **a tela web não pode alterar
o alvo SSH.** Só exibe. Quem escreve é `python cli.py configurar-vps`. Já existe
teste garantindo isso para a raiz (`test_web_does_not_expose_root_change_post`);
ganha um irmão.

---

## 7. O que muda no código do BackupRestore

### D3 — a trava de restauração passa a ser por par (máquina, contêiner)

**Não é opcional**, é consequência dos nomes coincidirem.

Hoje: `CONTAINERS_PROTEGIDOS = {nomes}`.
Passa a: `{("local", "mega-sena-postgres-1"), ("vps", "mega-sena-postgres-1"), …}`.

O teste `test_every_operational_container_is_protected` é reescrito nessa forma.

**Continua não existindo caminho para restaurar no VPS.** O único destino de
restauração automática segue sendo o sandbox descartável desta máquina.

### D6 — oito projetos no catálogo

`projetos.py` ganha um campo `ambiente` e passa a listar oito entradas:

```
conforto_termico          conforto_termico_vps
mega_sena                 mega_sena_vps
controle_bancario         controle_bancario_vps
controle_renda_variavel   controle_renda_variavel_vps
```

Apelidos distintos dão retenção e histórico independentes **sem tocar no banco do
catálogo** — nenhuma migração, nenhum risco para os artefatos existentes. A tela
agrupa em "Neste computador" e "Produção (VPS)".

### O que o motor ganha

Um caminho novo de origem: além de "produzir a partir de um contêiner", passa a
existir "buscar de um servidor". A verificação, a promoção atômica, o catálogo, a
retenção e a restauração continuam idênticos — o artefato que chega é indistinto
de um produzido aqui.

---

## 8. O que fica de fora, e por quê

### D4 — código do servidor: não

O código do VPS é espelho do `main` do GitHub, imposto pelo `deploy.sh`, que
recusa implantar com a árvore suja. Um ZIP seria a quarta cópia. Em vez disso, o
verbo `estado` reporta o `HEAD` do servidor e se a árvore está limpa; divergência
aparece no relatório — que é justamente o problema que originou a
ressincronização de agosto.

### D5 — segredos: continuam fora dos artefatos

O `motor.py` diz em letras claras que o artefato de configuração foi retirado do
escopo de propósito e não volta sem decisão explícita. Este plano **não** o traz
de volta.

Mas o `KIT_RECUPERACAO.md` precisa de uma seção do VPS, com a lista conferida:

| Projeto (no VPS) | Fora do Git, indispensável |
|---|---|
| `controle-bancario` | `.secrets/postgres_password`, `.secrets/django_secret_key`, `.env.vps`, `.certs/local-root-ca.crt` |
| `controle-renda-variavel` | `.secrets/postgres_password`, `.secrets/secret_key`, `.secrets/rtd_control_token`, `.secrets/collector_agent_token`, `.env.vps`, `.certs/local-root-ca.crt` |
| `mega-sena` | `.secrets/postgres_password.txt`, `.secrets/secret_key.txt`, `.env.vps`, `.certs/local-root-ca.crt` |
| `conforto-termico` | **não tem `.secrets/`** — os valores estão em `.env.docker`; `.certs/local-root-ca.crt` |

As configurações do nginx (`/etc/nginx/sites-enabled/`) não existem em lugar
nenhum e são trabalho manual de refazer. Viram cópia em `_manutencao/vps/nginx/`,
ao lado do `deploy.sh` — **não** artefato do BackupRestore. Não têm segredo
dentro, só domínios e portas, a mesma informação que os `docs/deployment-vps.md`
já contêm.

Copiar os segredos para o cofre continua sendo tarefa manual sua.

---

## 9. Fases

| Fase | O que faz | Mexe onde | Como se sabe que deu certo |
|---|---|---|---|
| 0 | Levantamento | — | ✅ feito, seção 2 |
| 1 | `backup-db.sh` + timer no VPS | só servidor | ✅ **feito 2026-08-20**, seção 15 |
| 2 | Chave dedicada + `backup-agent.sh` | só servidor | ✅ **feito 2026-08-20**, seção 16 |
| 3 | `ambiente`, trava por par, `configurar-vps` | só código | ✅ **feito 2026-08-20**, seção 17 |
| 4 | Busca, verificação e catalogação | só código | ✅ **feito 2026-08-20**, seção 18 |
| 5 | **Primeiro ciclo real** | servidor (lê e apaga) | ✅ **feito 2026-08-20**, seção 19 |
| 6 | **Ensaio de um dump do VPS** no sandbox | só local | ✅ **feito 2026-08-20**, seção 20 |
| 7 | Tela agrupada + agendamento dos oito | só local | ✅ **feito 2026-08-20**, seção 21 |
| 8 | `README`, `RESTAURAR`, `KIT_RECUPERACAO`, `AGENTS` | documentação | ✅ **feito 2026-08-20**, seção 22 |

**A Fase 1 sozinha já entrega proteção real**, antes de uma linha de Python. Se o
plano parar aí, a produção passa a ter backup diário verificado — só não tem
cópia fora do servidor.

Validação obrigatória ao fim das fases 4, 5 e 6, conforme o `AGENTS.md`:

```powershell
python -m unittest discover -s tests -v
python cli.py verificar
python cli.py ensaio --projeto <apelido>
```

---

## 10. Riscos, e o que segura cada um

| Risco | O que segura |
|---|---|
| O PC ficar semanas fora | O servidor continua fazendo e guardando. Nada se perde; o PC busca o acumulado quando voltar. |
| Transferência cortada no meio | SHA-256 do servidor conferido aqui + releitura no sandbox. Arquivo reprovado não entra no catálogo **e não é apagado de lá**. |
| A limpeza apagar o que não devia | Só apaga o já verificado; nunca o mais recente; e o piso é imposto **no servidor**, não pelo cliente. |
| Restaurar produção por engano | Regra 6, agora por par (máquina, contêiner). Não existe caminho no código que restaure no VPS. |
| Roubo da chave dedicada | Limita a ler dumps e apagar dumps já verificados. Não alcança bancos vivos, contêineres nem código. **Não elimina** o risco de vazamento de dados. |
| Perder a chave dedicada | Revogar é apagar uma linha do `authorized_keys`, como as deploy keys da Fase 1b. |
| Dumps de produção no Dropbox | Consciente. O ganho é a cópia fora do local, num provedor diferente do da Oracle. |
| O disco do servidor encher | Retenção própria de 14 dias na camada 1, independente do PC. |

---

## 11. O que este plano **não** resolve

- **Não faz backup dos segredos do VPS.** Continua sendo cópia manual para o
  cofre, agora com a lista certa (D5).
- **Não faz backup dos volumes**, só do conteúdo dos bancos. Deliberado: dump é
  portável entre versões e máquinas, volume não é.
- **Não restaura para a produção.** Trabalho manual, consciente, com o
  `RESTAURAR.md` na tela.
- **Não monitora o VPS.** Se o servidor cair às 4h, você descobre pelo backup que
  falhou, não na hora.
- **Não dá recuperação a um ponto no tempo.** Voltar para "14h37 de terça" exige
  arquivamento de WAL, que é bem mais complexo e não se justifica aqui.

---

## 12. Decisões

Validadas em 2026-08-19 e ainda válidas na reescrita:

| # | Decisão |
|---|---|
| D2 | ✅ Chave dedicada e travada, não a de administração |
| D4 | ✅ Só o banco; do código, conferir e registrar o `HEAD` |
| D5 | ✅ nginx vira cópia em `_manutencao/vps/nginx/`, não artefato |
| D6 | ✅ Oito projetos no catálogo, com sufixo `_vps` |

Novas, da reescrita de 2026-08-20:

| # | Decisão |
|---|---|
| D1 | ✅ **Duas camadas.** O servidor produz; o PC busca. Substitui o `pg_dump` remoto da primeira versão |
| D8 | ✅ **Limpeza do servidor**: depois de verificado aqui, fica só o mais recente lá |

| D9 | ✅ **Retenção 14, configurável por projeto, editável na interface** com aviso de gravidade e confirmação adicional. Ver seção 14. |
| D10 | ✅ **Pular o backup quando o banco não mudou**, com as duas condições obrigatórias. Ver seção 13. |

## 13. D10 — pular o backup quando nada mudou (proposta)

**O marcador é o LSN do WAL** (`pg_current_wal_lsn()`), guardado ao lado do
último dump e comparado antes de decidir. Uma consulta barata, ~10 linhas no
script do servidor.

Descartados, e por quê:

- **Comparar o dump com o anterior**: `pg_dump --format=custom` grava data e hora
  dentro do arquivo, então dados idênticos produzem arquivos diferentes. E já
  teria pago o custo de gerar o dump.
- **Contadores de `pg_stat_database`**: zeram quando o contêiner reinicia e
  contam transações de leitura — cada health check acusaria movimento.

**O LSN erra na direção certa.** Se não andou, é garantido que nada foi escrito:
pular é seguro. Se andou, pode ter sido manutenção interna do banco e o backup
sai à toa. Ou seja: **nunca deixa de fazer um backup necessário; no máximo faz um
desnecessário.** Ele também sobrevive a reinício e só anda para frente, ao
contrário dos contadores.

**O ganho não é disco** (186 GB livres no servidor). É que a retenção deixa de
ser medida em calendário e passa a ser medida em mudanças: 14 cópias viram **14
estados diferentes do banco**. Num projeto que muda duas vezes por semana, as
duas semanas pedidas viram meses de histórico real sem guardar um byte a mais. E
como o timer roda no máximo uma vez por dia, 14 cópias continuam sendo sempre
**pelo menos** 14 dias — nunca menos do que foi pedido.

### A regra de partida

**Só se pula quando existe um backup válido, o LSN guardado dele é legível, e o
LSN atual é exatamente igual.** Qualquer outra situação faz o backup.

Formulado assim, um único princípio cobre quatro armadilhas em vez de quatro
casos especiais:

| Situação | O que acontece |
|---|---|
| Não existe nenhum backup | **Faz.** É a primeira execução — e cobre o caso de o banco estar quieto desde sempre, que sem esta regra ficaria sem backup para sempre parecendo saudável |
| O marcador de LSN sumiu ou está ilegível | **Faz.** Não dá para provar que nada mudou |
| O LSN atual é *diferente* do guardado, em qualquer direção | **Faz.** LSN só anda para frente; se voltou, o banco não é mais a mesma linhagem — foi restaurado ou recriado |
| O último dump existe mas reprovou na verificação | **Faz.** Um dump que não passa não é backup |

**Duas condições, sem as quais não vale fazer:**

1. **Intervalo máximo de 7 dias.** Força um backup mesmo sem mudança. O risco
   real não é pular quando devia; é um erro na detecção fazer os backups pararem
   em silêncio. Com o teto, o pior caso é um backup de 7 dias, não a ausência
   descoberta meses depois.
2. **Separar "quieto" de "quebrado".** O servidor registra a verificação separada
   do backup, e o verbo `estado` responde `conferido hoje, sem alterações desde
   14/08`. Sem isso, "último backup há 6 dias" é ambíguo.

---

## 14. D9 — retenção editável na interface

Retenção de **14 por projeto**, alterável na tela de Retenção. Isto é uma
**exceção deliberada** ao princípio de que a interface web não escreve
configuração, e precisa ficar registrada como exceção no `AGENTS.md` para que uma
sessão futura não a "conserte" de volta.

**Por que a exceção é defensável.** A raiz de backup continua somente leitura na
interface, e por um motivo diferente: apontá-la para outro lugar órfã o catálogo
inteiro de uma vez. A retenção é de outra classe de risco — o estrago é limitado,
conhecido de antemão, e o código já tem dois pisos que nenhuma tela alcança:

- `aplicar_retencao` **nunca remove o último artefato válido** de um tipo, mesmo
  com retenção 0;
- artefatos **fixados** são imunes à retenção. É a saída para o que não pode
  sumir: fixe antes de mexer no número.

### Como a tela se comporta

**Aumentar não apaga nada** — salva direto, sem fricção. Exigir confirmação para
tornar as coisas mais seguras seria fricção no lugar errado.

**Diminuir mostra a consequência exata antes de aceitar**, com números reais, não
aviso genérico:

> Reduzir de 14 para 2 vai apagar **12 backups** do Controle Bancário na próxima
> execução bem-sucedida. O mais antigo que sobra passa a ser o de **18/08**.
> Backups fixados não são afetados (**0 fixados** neste projeto).
>
> Para confirmar, digite o nome do projeto: `controle_bancario`

A confirmação digitada é o mesmo recurso da regra 6 da restauração — o projeto já
decidiu que **a fricção é o mecanismo de segurança**, e não inventa um padrão
novo para isso.

### A rede de proteção que já existe

**Nada é apagado no instante da mudança.** A retenção só roda depois de um backup
novo verificado (regra 3: nunca apagar antes de ter o substituto). Entre baixar o
número e a próxima execução existe uma janela inteira para voltar atrás — e a
tela diz isso, porque é a diferença entre um susto e uma perda.

---

## 15. Fase 1 — concluída em 2026-08-20

**A produção tem backup diário verificado.** É a primeira vez.

### O que existe agora no servidor

| Caminho | O quê |
|---|---|
| `/home/ubuntu/backup-db.sh` | o script (cópia em `_manutencao/vps/backup-db.sh`) |
| `/etc/systemd/system/backup-db.service` | executa o script como `ubuntu`, `Type=oneshot` |
| `/etc/systemd/system/backup-db.timer` | `OnCalendar=*-*-* 03:00:00 America/Sao_Paulo`, `Persistent=true` |
| `/home/ubuntu/backups/<projeto>/` | os dumps e os `.sha256` |

O fuso vai **explícito** no `OnCalendar`, não convertido para UTC na mão: o
systemd 255 aceita, e assim a regra sobrevive a uma eventual mudança de fuso do
servidor. Confirmado com `systemd-analyze calendar`.

```
~/backup-db.sh --estado    estado dos quatro, sem alterar nada
~/backup-db.sh             o ciclo (é o que o timer chama)
~/backup-db.sh --forcar    ignora a checagem de alteração
```

### Os dumps são muito menores do que este plano estimava

A seção 2 dizia "poucos MB por dump". **Errado por uma ordem de grandeza:**

| Projeto | Dump |
|---|---|
| `controle_bancario` | 216 KB |
| `controle_renda_variavel` | 164 KB |
| `mega_sena` | 132 KB |
| `conforto_termico` | 44 KB |

Os volumes de 50–70 MB são quase todos índice e WAL. Seis dumps ocupam 720 KB no
total. Retenção é, na prática, de graça — o que reforça a escolha de 14 e torna a
limpeza do D8 uma medida de segurança, não de espaço.

### A detecção de alteração foi validada na prática

Rodando o ciclo três vezes seguidas, com segundos de intervalo:

- 1ª: os quatro fizeram backup, motivo `primeiro backup` — **a regra de partida
  funcionou**;
- 2ª: três pularam; o `conforto_termico` gravou de novo com motivo `banco
  alterado`;
- 3ª: os quatro pularam.

O `conforto_termico` não foi falso positivo: ele tem um **coletor gravando
leituras continuamente**, então o LSN dele anda de verdade a cada poucos
segundos. O comportamento esperado em regime é conforto gravando quase todo dia e
os outros três só quando houver lançamento.

### Verificação independente

Os seis dumps foram reconferidos **fora do script**: `sha256sum -c` contra o
sidecar, e `pg_restore --list` rodado por um contêiner **diferente** do que
produziu cada um. Os seis passaram — o que também prova que os dumps são
portáteis, e não dependem do contêiner de origem.

### Como desfazer, se precisar

```
sudo systemctl disable --now backup-db.timer
sudo rm /etc/systemd/system/backup-db.{service,timer}
sudo systemctl daemon-reload
```

Nada mais precisa ser tocado. O script e a pasta de dumps não são alcançados por
nenhum outro sistema do servidor.

### O que a Fase 1 ainda não dá

**Não há cópia fora do servidor.** Se o VPS for perdido, os dumps vão junto. É
exatamente o que a camada 2 resolve, e por isso ela continua valendo a pena.

---

## 16. Fase 2 — concluída em 2026-08-20

**Existe uma chave dedicada, travada por `command=`, capaz só dos quatro verbos.**

### O que existe agora

| Onde | O quê |
|---|---|
| `C:\Users\MSPA\Downloads\OracleKeys\backup-agent-key-20260820`(`.pub`) | par de chaves dedicado, fora do Git, ao lado da chave de administração |
| `/home/ubuntu/backup-agent.sh` | o agente (cópia em `_manutencao/vps/backup-agent.sh`) |
| `/home/ubuntu/.ssh/authorized_keys` | ganhou uma segunda linha, com `command="/home/ubuntu/backup-agent.sh"` e `no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding,no-user-rc` presos à chave nova |
| `/home/ubuntu/.ssh/authorized_keys.bak-20260820` | cópia da `authorized_keys` de antes, para desfazer |

O agente lê `$SSH_ORIGINAL_COMMAND` — nunca o argv que o cliente tentou passar
— porque é isso que o `command=` do `authorized_keys` garante: com essa chave,
só `backup-agent.sh` roda, sempre, e só ele decide o que o texto do comando
autoriza. `estado` delega em `~/backup-db.sh --estado` (mesma saída da Camada 1)
e acrescenta a saúde do timer.

### Validado na prática, com a chave nova

- `estado`: respondeu com os quatro projetos e `timer backup-db.timer: active (enabled)`.
- `listar`: respondeu nome, tamanho e SHA-256 dos sete dumps existentes no momento.
- **Nenhum comando**: recusado com `verbo desconhecido`, não abriu shell
  (`Pseudo-terminal will not be allocated` — a chave não pede TTY, e mesmo
  pedindo o `no-pty` recusaria).
- `rm -rf /` como comando SSH: ignorado pelo `command=` forçado, executou o
  agente, que recusou por verbo desconhecido — **a produção nunca viu esse
  comando**.
- `apagar` no dump mais recente do conforto térmico: recusado
  (`é o dump mais recente`) — o piso da seção 5.2 funciona.
- `apagar ../../etc/passwd`: recusado por não bater o formato de caminho —
  travessia de diretório não tem como.
- `enviar` num dump antigo do conforto térmico: baixado e conferido por
  SHA-256 aqui, bateu com o valor que o `listar` tinha informado.

**Nenhum dump foi apagado do servidor nesta fase.** A limpeza (seção 5.2) só
faz sentido depois que a Camada 2 souber buscar e verificar de verdade — Fase 4
em diante. Fase 2 só prova que a chave e o agente funcionam.

### Como desfazer, se precisar

```bash
cp ~/.ssh/authorized_keys.bak-20260820 ~/.ssh/authorized_keys
rm /home/ubuntu/backup-agent.sh
```

E apagar o par de chaves local em `Downloads\OracleKeys\`.

---

## 17. Fase 3 — concluída em 2026-08-20

**O código conhece os oito projetos, protege por par e tem onde guardar o alvo
SSH.** Nenhum backup real de VPS acontece ainda — isso é a Fase 4.

### O que mudou

- **`projetos.py`**: `Projeto` ganhou `ambiente` (`"local"` ou `"vps"`).
  `PROJETOS` passou de 4 para 8 entradas — as quatro novas com sufixo `_vps`,
  mesmo contêiner/usuário/banco dos originais (são os nomes reais do lado de
  lá), `pasta=""`, `tipos=("banco",)` só, `retencao=14` (D9). `.caminho` e
  `.e_repo_git` tratam `pasta` vazia sem erro. `CONTAINERS_PROTEGIDOS` virou
  `frozenset` de pares `(ambiente, contêiner)`.
- **`restaurar.py`**: a trava 1 compara `("local", container_destino)` — a
  restauração só fala com o Docker local, então o ambiente do destino é
  sempre conhecido. `comparar_com_origem` recusa qualquer projeto que não seja
  `ambiente="local"` (a origem "VPS" ainda não tem um caminho de leitura;
  usar o contêiner local do mesmo nome daria número errado, não erro).
- **`motor.py`**: `fazer_backup` recusa qualquer projeto que não seja
  `ambiente="local"`, **depois** de abrir a execução no catálogo — fechando-a
  como "falha" antes de propagar o erro, no mesmo padrão das outras travas
  pré-`try` da função.
- **`configuracao.py`**: `alvo_vps()` / `configurar_vps()` (D7) — host,
  usuário e caminho da chave em `configuracao.local.json`, com o mesmo padrão
  de escrita atômica da raiz de backup. Recusa chave que não existe no disco.
- **`cli.py`**: `configurar-vps <host> --usuario --chave`, única via de
  escrita. `backup --todos` passou a filtrar só `ambiente="local"` — mesmo
  comportamento de antes, explícito em vez de acidental (havia só projetos
  locais até agora).
- **`web.py` / `configuracoes.html`**: card "Produção (VPS)" **somente
  leitura** — a rota `/configuracoes` continua sem `POST`, e `web.py` nem
  importa `configurar_vps`.

### Um bug pego pelo próprio ensaio na tela

A primeira versão da trava do `motor.fazer_backup` recusava o projeto `_vps`
**antes** de abrir a execução no catálogo. Funcionava sozinha, mas quando
disparada pela tela (`disparar_backup` já cria a execução em "fila" antes de
chamar o motor), a exceção pulava o `fechar_execucao` — a execução ficava
**presa em "fila" para sempre**. Só apareceu ao clicar "Fazer backup agora"
em `/projeto/mega_sena_vps` de verdade; o teste automatizado original não
testava esse caminho (`execucao_id` vindo de fora). Corrigido movendo a trava
para depois de abrir a execução, com `fechar_execucao("falha", …)` explícito
— e a suíte ganhou `test_non_local_backup_is_refused_before_touching_docker`,
que mocka `banco.abrir_execucao`/`fechar_execucao` para provar o fechamento
sem tocar no catálogo real. A execução órfã (#57, criada durante o teste
manual antes do fix) foi fechada manualmente como "falha" com nota explicando
a causa.

### Validado

- `python -m unittest discover -s tests -v`: **25 testes, 1 skip** (symlink
  sem privilégio no Windows — pré-existente, sem relação com esta fase).
- `python cli.py verificar`: 0 ausentes, 0 corrompidos, antes e depois.
- **Backup local real** de `conforto_termico` (banco 6,8 MB + código 314,5 KB,
  ambos verificados) — prova que a trava não regrediu o caminho local.
- **Ensaio real no sandbox** (`compose.teste.yaml up` → `cli.py ensaio` →
  `down -v`): 18/18 tabelas, 358.490/358.490 linhas, CONFERE.
- **Tela**: `/configuracoes` mostra o card VPS read-only
  (`ubuntu@163.176.214.214`); `/projetos` lista os 8, os quatro `_vps` com
  "(sem pasta local — ambiente 'vps')" e retenção 14; clicar "Fazer backup
  agora" em um projeto `_vps` termina em "Falhou" com mensagem clara — não
  trava, não crasha, não produz artefato com rótulo errado.
- **`cli.py configurar-vps` rodado de verdade**: `configuracao.local.json`
  agora aponta para `ubuntu@163.176.214.214` com a chave dedicada da Fase 2
  (`Downloads\OracleKeys\backup-agent-key-20260820`) — o que a Fase 4 vai
  precisar para buscar de verdade.
- Criado `.claude/launch.json` na raiz de `VSCodeProjects` (fora do escopo do
  BackupRestore) para subir `web.py` sob o preview do Claude Code.

### O que ainda não existe

Nenhum artefato de projeto `_vps` no catálogo — a Fase 4 (busca, verificação
e catalogação via `backup-agent.sh`) é o que preenche isso.

---

## 18. Fase 4 — concluída em 2026-08-20

**O código sabe buscar, verificar e catalogar um dump do VPS.** Ainda não foi
rodado contra o servidor real — isso é a Fase 5, deliberadamente separada
porque é a primeira que apaga algo em produção (mesmo que só dumps já
verificados, e nunca o mais recente).

### `vps.py`, módulo novo

Implementa o ciclo da seção 5.1, ponta a ponta:

- `listar_remoto(alvo)` — roda o verbo `listar` por SSH e faz o parse de cada
  linha (`<slug>/<arquivo> <bytes> <sha256>`) num `DumpRemoto`. Linha fora do
  formato ou SSH falhando **recusa tudo** (não cataloga parcialmente às
  cegas); um dump listado com `sem-hash` (sidecar ausente no servidor) é
  reprovado individualmente sem tentar buscar nem apagar.
- `enviar_remoto` / `_apagar_remoto` — os outros dois verbos. `_apagar_remoto`
  distingue três desfechos: apagou, foi recusado por ser o mais recente
  (**esperado — D8, não é erro**) ou falhou por outro motivo (vira aviso no
  catálogo, nunca derruba o ciclo: a limpeza é sempre best-effort).
- `verificar_dump_no_sandbox` — relê com `pg_restore --list` no
  **`backuprestore-sandbox`**, não no contêiner do projeto: a origem é outra
  máquina, então comparar com o contêiner local seria exatamente o erro que a
  Fase 3 fechou (nome de contêiner colidindo).
- `_criado_em_do_carimbo` — o carimbo do servidor é UTC; converte para hora
  local no mesmo formato que `banco.agora()` usa, para a ordenação por
  `criado_em` continuar comparável entre artefatos locais e do VPS.
- `sincronizar_projeto(projeto)` — orquestra tudo, no mesmo padrão de
  `motor.fazer_backup`: abre a execução, recusa projeto que não seja
  `ambiente="vps"` (fechando a execução antes de propagar — a lição da Fase 3
  foi aplicada de propósito aqui desde o início), busca só o que ainda não
  existe localmente (checagem por existência do arquivo final — idempotente:
  rodar de novo não rebaixa nem duplica), tenta apagar do servidor **todo**
  dump processado, exista de antes ou buscado agora (o servidor decide se
  recusa, o cliente não precisa replicar a lógica de "qual é o mais recente").

### `banco.registrar_artefato` ganhou `criado_em` opcional

Antes, todo artefato nascia com `criado_em = agora()`. Para um artefato de
origem VPS isso apagaria a informação mais importante da seção 13/D10: um PC
que ficou dias fora buscando vários dumps de uma vez os catalogaria todos com
o mesmo carimbo de hoje, embaralhando a ordem real de captura que a retenção
depende. Mudança aditiva, com o padrão de sempre para artefato local
(`criado_em=None` → `agora()`, comportamento idêntico a antes).

### `Projeto.slug_servidor`

Propriedade nova: `mega_sena_vps` → `mega_sena` (o apelido que o servidor usa
— ele não sabe nada sobre o sufixo `_vps` do catálogo local). Levanta erro se
chamada num projeto que não é `ambiente="vps"`.

### `cli.py sincronizar-vps --todos|--projeto`

Mesmo padrão de `backup`: imprime buscados/já existiam/reprovados/apagados/
mantidos por projeto, soma falhas, devolve código de saída não-zero se algo
falhou.

### Validado — só com mocks, nenhum contato com o VPS real

`tests/test_vps.py`, 16 testes novos (41 no total, 1 skip pré-existente):
parse de listagem válida/inválida/erro de SSH, conversão de carimbo UTC→local,
classificação dos três desfechos de `apagar`, `verificar_dump_no_sandbox`
recusando sandbox ausente e montando o comando `docker exec` certo, o ciclo
completo de busca+cataloga com o carimbo do servidor no artefato gravado,
reprovação por SHA-256 incompatível e por falha no sandbox (nenhuma promove
nem cataloga), a trava de ambiente fechando a execução como as demais, VPS
não configurado, dump já existente pulando a busca mas tentando apagar, e
dump `sem-hash` reprovado sem tentar buscar ou apagar.

Um detalhe de isolamento de teste vale registrar: `raiz_backup()` lê primeiro
o `configuracao.local.json` **real** deste PC — só a variável de ambiente
`BACKUPRESTORE_RAIZ_BACKUP` **não basta** para redirecionar os testes a um
diretório temporário, porque a chave do arquivo tem prioridade. É preciso
também trocar `configuracao.ARQUIVO_CONFIGURACAO` por um caminho temporário
(o padrão que `test_web_does_not_expose_root_change_post` já usava). Os
primeiros testes escritos erraram nisso e vazaram para a raiz real antes de
serem corrigidos — nenhum dado real chegou a ser tocado, o erro apareceu como
`ConfiguracaoInvalida` (a raiz real não cabia dentro da raiz permitida de
teste), não como escrita silenciosa.

### O que ainda não existe

Nenhum dump do VPS foi buscado de verdade — a Fase 5 é o primeiro ciclo real,
e é a primeira fase que efetivamente apaga algo em produção.

---

## 19. Fase 5 — concluída em 2026-08-20

**Primeiro ciclo real contra o servidor. Funcionou de primeira, sem ajuste no
código.** A produção do VPS agora tem cópia fora do servidor, verificada.

### O ciclo

Estado do servidor antes (`ssh ... listar`): 7 dumps — 4 do
`conforto_termico` (acumulados enquanto a Camada 2 não existia) e 1 de cada
um dos outros três.

`python cli.py sincronizar-vps --todos`, com o sandbox de pé:

| Projeto | buscados | já existiam | reprovados | apagados | mantidos |
|---|---|---|---|---|---|
| Conforto Térmico | 4 | 0 | 0 | 3 | 1 |
| Mega-Sena | 1 | 0 | 0 | 0 | 1 |
| Controle Bancário | 1 | 0 | 0 | 0 | 1 |
| Controle Renda Variável | 1 | 0 | 0 | 0 | 1 |

**7 buscados, 0 reprovados.** O servidor ficou com exatamente um dump por
projeto — os três excedentes do conforto térmico foram apagados, os quatro
mais recentes (um por projeto) mantidos porque o agente recusa apagar o mais
novo (D8). `python cli.py verificar`: 76 conferidos (69 de antes + 7), 0
ausentes, 0 corrompidos.

**`criado_em` gravado com o carimbo do servidor, não a hora do download** —
confirmado nos quatro registros: os carimbos UTC do servidor (06:00, 04:03,
04:04) viraram 03:00/01:03/01:04 no catálogo, batendo com UTC-3 de São Paulo.
É exatamente o que a seção 13 (D10) precisa para a retenção continuar
correta.

**Idempotência confirmada**: rodando `sincronizar-vps --todos` de novo
imediatamente depois, os quatro projetos deram 0 buscados / 1 já existia /
0 apagados / 1 mantido — nada foi buscado de novo, nada foi duplicado no
catálogo, e a tentativa de apagar o único dump que sobrou foi recusada pelo
servidor como esperado.

Sandbox subido com `docker compose -f compose.teste.yaml up -d`, aguardado o
health check, usado para a releitura de cada dump, e derrubado com `down -v`
ao final — nada ficou de pé além do necessário.

### O que isto já entrega

A produção do VPS agora tem cópia fora do servidor, num provedor diferente
(Dropbox, consciente — seção 10), verificada por SHA-256 e por
`pg_restore --list`. Se o VPS for perdido agora, os quatro bancos são
recuperáveis a partir deste catálogo — ainda que só até o estado do dump mais
recente de cada um, capturado nesta sessão.

### O que ainda falta

- **Nenhum ensaio de restauração de um dump VPS foi feito** — os artefatos
  estão catalogados e passaram por `pg_restore --list`, mas nunca foram
  restaurados de fato num banco e comparados linha a linha com a origem.
  Isso é a Fase 6.
- O ciclo ainda é manual (`cli.py sincronizar-vps`) — agendamento é Fase 7.

---

## 20. Fase 6 — concluída em 2026-08-20

**Um dump de origem VPS foi restaurado de verdade no sandbox, e as contagens
batem com a produção.** É a prova ponta a ponta: o que a Camada 2 buscou é
um backup que restaura.

### Por que `cli.py ensaio` precisou de um ajuste pequeno

`comparar_com_origem` (usada pelo `ensaio` para comparar com a origem)
recusa qualquer projeto que não seja `ambiente="local"` — trava da Fase 3,
porque o nome do contêiner do projeto `_vps` colide de propósito com o do
projeto local, e ler a "origem" por lá compararia com o banco errado. Não é
um bug a corrigir; é a mesma proteção funcionando como desenhada.

**Decisão desta fase: não dar ao agente do VPS um verbo de consulta SQL só
para isto.** O `backup-agent.sh` (D1) tem de propósito só quatro verbos —
`listar`, `enviar`, `apagar`, `estado` — e cada verbo a mais é superfície de
ataque a mais numa chave que já pode ler dados de produção. Comparar com a
origem em produção não é uma operação que precise ser automática nem
recorrente; é conferência pontual, e o operador já tem a chave de
administração para isso quando precisar.

`cli.py comando_ensaio` ganhou um branch: para `ambiente != "local"`, depois
de restaurar no sandbox com sucesso, mostra `resumo_banco` do **destino**
(tabelas e linhas restauradas) e para aí — sem tentar `comparar_com_origem`.
Testado com mock (`tests/test_safety.py::EnsaioVpsTests`, 42 testes no
total): a comparação nunca é chamada para um projeto `vps`.

### O ensaio real

`python cli.py ensaio --projeto mega_sena_vps` — artefato #94
(`mega_sena_banco_20260820_040329.dump`, capturado 04:03 UTC = 01:03 São
Paulo): `pg_restore` completo, 5 tabelas, 3.053 linhas no sandbox.

Comparação manual, **fora do código do app** (chave de administração, não a
chave restrita da Camada 2 — a separação de privilégio do D1 é justamente
para isto: consulta pontual não precisa de canal automático):

| Tabela | Produção agora | Dump restaurado (04:03 UTC) |
|---|---|---|
| `alembic_version` | 1 | 1 |
| `config` | 0 | 0 |
| `draws` | 3.046 | 3.046 |
| `generated_bets` | 10 | 5 |
| `users` | 2 | 1 |

`draws` (só muda com sorteio) e as tabelas de schema batem exatamente.
`generated_bets` e `users` cresceram desde a captura — é o app em uso normal
entre 04:03 e agora, não uma falha do artefato. É a mesma leitura que
`comparar_com_origem` já documenta para o caso local: "divergência
contemporânea é diagnóstico, não prova de falha do artefato que acabou de
restaurar."

### Validado

- `python -m unittest discover -s tests -v`: 42 testes, 1 skip (pré-existente).
- Sandbox subido, usado, derrubado com `down -v` — nada ficou de pé.

### O que ainda falta

Agendamento (Fase 7) — o ciclo `sincronizar-vps` continua manual. Sem isso, a
Camada 2 só busca quando alguém lembrar de rodar, o mesmo problema que a
seção 1 apontou para o backup local antes deste plano existir.

---

## 21. Fase 7 — concluída em 2026-08-20

**A Camada 2 roda sozinha, todo dia, sem ninguém lembrar. E a tela mostra os
oito projetos separados por onde os dados moram.**

### Agendamento — o achado que valia a pena registrar

A tarefa `BackupRestore` (backup local) já existia nesta máquina quando esta
sessão chegou à Fase 7 — criada em algum momento entre a Fase 1 (quando o
levantamento constatou sua ausência) e agora, provavelmente noutra sessão de
manutenção. Rodou com sucesso às 07:06 de hoje. Não precisou de trabalho
nesta fase.

Criada a segunda:

```powershell
schtasks /create /tn "BackupRestoreVPS" /tr '"C:\Users\MSPA\AppData\Local\Python\bin\python.exe" "...\BackupRestore\cli.py" sincronizar-vps --todos' /sc daily /st 03:30
```

**03:30, meia hora depois do timer do servidor (03:00 America/Sao_Paulo) e do
backup local** — folga generosa para um ciclo que leva segundos.

**Achado real, não cosmético — a primeira execução disparada pelo Agendador
falhou** com `Permission denied (publickey)`, mesmo a chave e o comando
estando corretos (rodava perfeitamente no meu terminal). Causa: a chave
dedicada (`backup-agent-key-20260820`), gerada por `ssh-keygen` num terminal
Git Bash, herdou ACL aberta da pasta —
`APSM\CodexSandboxUsers:(RX)`, `NT AUTHORITY\SYSTEM:(F)`,
`BUILTIN\Administrators:(F)`, `APSM\MSPA:(F)`, tudo herdado. O cliente OpenSSH
**real do Windows** (o que o Agendador de Tarefas invoca — não o do Git Bash)
recusa silenciosamente uma chave privada legível por mais de um principal. A
chave de administração já funcionava porque já tinha ACL restrita
(`APSM\MSPA:(R)`, sem herança) — não porque fosse mais nova. Corrigido com:

```powershell
icacls "<chave>" /inheritance:r /grant:r "APSM\MSPA:R"
```

Depois da correção, `schtasks /run /tn "BackupRestoreVPS"` completou com
`Last Result: 0` e as quatro sincronizações apareceram no catálogo como
sucesso. Documentado no `README.md` para a próxima chave dedicada que
alguém gerar num terminal Git Bash.

**O sandbox agora precisa ficar de pé entre execuções** (não mais criado e
destruído a cada ciclo) — é o que permite `sincronizar-vps` reler dumps sem
intervenção às 3h30 da manhã. Subido uma vez com `docker compose -f
compose.teste.yaml up -d` e deixado — `verificar_dump_no_sandbox` já sabia
ligar o contêiner parado, só precisava que ele existisse.

### Tela agrupada

`painel.html`, `projetos.html` e `retencao.html` passaram a separar os cards
e a tabela em duas seções — **"Neste computador"** e **"Produção (VPS)"** —
via `selectattr('ambiente', ...)`, sem mudar nada no backend (`web.py`
continua passando a mesma lista de 8 `PROJETOS`; o agrupamento é só de
apresentação).

**Um bug cosmético real corrigido de passagem**: a lógica de "Íntegro" no
painel checava `r.banco and r.codigo` incondicionalmente — um projeto `_vps`
(que nunca tem artefato de código, por D4/D5) ficaria **"Incompleto" para
sempre**, mesmo com o backup de banco perfeito. Corrigido para considerar
`p.tipos`: completo passou a significar "tem o que esse projeto realmente
produz", não "tem banco e código incondicionalmente". Mesma correção
aplicada em `retencao.html` (parou de mostrar uma linha "Código: 0/14" sem
sentido para projetos que nunca têm esse tipo).

Validado no navegador (`get_page_text` nas três páginas): os quatro projetos
`_vps` aparecem como "Íntegro", "Código: não se aplica", retenção 14 — e os
quatro locais continuam exatamente como antes.

### Validado

- `python -m unittest discover -s tests -v`: 42 testes, 1 skip (pré-existente).
- `python cli.py verificar`: 76 conferidos, 0 ausentes, 0 corrompidos —
  inalterado pelas mudanças de template/CSS.
- As duas tarefas agendadas existem, e a nova rodou com sucesso disparada
  pelo próprio Agendador (não só pelo terminal).

---

## 22. Fase 8 — concluída em 2026-08-20

**Documentação atualizada nos quatro documentos, com a recuperação de um dump
VPS descrita ponta a ponta.** Última fase do plano.

- **`README.md`**: abertura menciona a Camada 2; `Uso` ganhou
  `sincronizar-vps`/`configurar-vps`; `Agendamento` documenta as duas tarefas
  e os dois achados reais (sandbox precisa ficar de pé, ACL da chave); `O que
  é gravado` explica que os `_vps` só têm `banco/`; a regra 6 das "sete
  regras" foi corrigida para "par (ambiente, contêiner)"; `Arquivos` ganhou
  `vps.py` e "8 projetos" no lugar de "4".
- **`RESTAURAR.md`**: nova seção "Reconstrução completa a partir de um dump
  `_vps`" (o código vem do GitHub, não de um ZIP — não existe um aqui); a
  seção de ensaio explica por que a comparação com a origem não é automática
  para projetos VPS (D1); "O que o backup não cobre" ganhou os limites
  específicos da Camada 2 (segredos do VPS, ponto no tempo, monitoramento).
- **`KIT_RECUPERACAO.md`**: nova seção "VPS (produção)" com a tabela de
  segredos por projeto que a Fase 0 do plano levantou (D5) — diferente do
  inventário dos locais, os dois lados não são o mesmo hoje. Registrada como
  **pendência real, não fingida**: a config do nginx (D5) ainda não foi
  copiada para `_manutencao/vps/nginx/` — conferido nesta fase que a pasta
  não existe, e o texto diz isso explicitamente em vez de descrever um
  trabalho que não foi feito.
- **`AGENTS.md`**: `vps.py` entrou na lista de módulos que preservam os
  invariantes de segurança, e o "papel e fontes de verdade" passou a
  descrever as duas responsabilidades (backup local + busca do VPS).

### Validado

- `python -m unittest discover -s tests -v`: 42 testes, 1 skip. Nenhuma
  mudança de código nesta fase — só documentação.

### O que fica pendente, fora das oito fases

- Extração de segredos do VPS para o cofre (sempre manual, por decisão de
  escopo — D5 mais ampla).

### Sessão de 2026-08-20 (continuação) — cópia do nginx feita

Reconsiderada a decisão D5 antes de executar: automatizar essa cópia pelo
BackupRestore exigiria ou dar à chave restrita um verbo novo fora do diretório
de dumps (mais superfície numa chave que hoje só toca dumps se vazar), ou
trazer a chave de administração para dentro do código do app (hoje ela só é
usada manualmente — um BackupRestore comprometido não deve virar acesso amplo
ao VPS). As duas pioram uma fronteira de segurança existente; a decisão
manual se sustenta por motivo próprio, não só por ter sido acordada no meio
do plano. Puxados `/etc/nginx/sites-available/{conforto-termico,
controle-bancario,controle-renda-variavel,megasena}` do VPS com a chave de
administração (`ssh-key-2026-08-17.key`) para `_manutencao/vps/nginx/`, com
README explicando a origem e o comando para atualizar. Sem segredo dentro
(domínio, porta, caminho de certificado) — confirmado por leitura antes de
copiar.

---

## Registro de sessões

- **2026-08-19** — Levantamento (Fase 0) e primeira versão do plano, com o PC
  disparando `pg_dump` remoto. Quatro decisões validadas (D2, D4, D5, D6).
- **2026-08-20** — Reescrita em duas camadas. Motivo: a primeira versão amarrava
  o backup da produção a este computador estar ligado — e ficou constatado que
  nem o backup local roda sozinho (não existe tarefa agendada; último artefato de
  16/08). Acrescentada a limpeza do servidor a pedido do mantenedor (D8), com as
  três condições da seção 5.2. Retenção fechada em 14, por projeto e **editável
  na interface** com consequência numérica e confirmação digitada (D9, seção 14)
  — exceção deliberada ao "a web não escreve configuração", a registrar no
  `AGENTS.md`. Aprovado o pulo de backup sem alteração no banco (D10, seção 13).
  Acrescentada a regra de partida do D10 por observação do mantenedor: sem
  backup válido, sempre faz — senão um banco quieto ficaria sem backup para
  sempre, parecendo saudável. Conforto Térmico foi pausado e religado no VPS a
  pedido, para observar o comportamento — `/login` de volta em 200.
  **Fase 1 executada e verificada** (seção 15). A produção passou a ter backup
  diário. Nada no código do BackupRestore foi alterado ainda.
- **2026-08-20 (continuação)** — **Fase 2 executada e verificada** (seção 16):
  chave dedicada + `backup-agent.sh` no ar, com os quatro verbos testados
  contra o servidor real, incluindo tentativa de shell e travessia de
  caminho, ambas recusadas. Nenhum dump foi apagado.
- **2026-08-20 (continuação)** — **Fase 3 executada e verificada** (seção 17):
  `ambiente` em `Projeto`, oito projetos no catálogo, trava por par
  `(ambiente, contêiner)`, `configurar-vps` em `cli.py`/`configuracao.py`,
  card read-only na tela. 25 testes (1 skip), backup local real e ensaio no
  sandbox confirmando que o caminho local não regrediu. Um bug real foi pego
  testando na tela (não só nos testes automatizados): a trava de
  `motor.fazer_backup` deixava a execução presa em "fila" quando disparada
  pela web, corrigido e coberto por teste novo. `configuracao.local.json`
  deste PC já aponta para o VPS com a chave da Fase 2.
- **2026-08-20 (continuação)** — **Fase 4 executada e verificada** (seção 18):
  módulo `vps.py` novo com o ciclo completo (listar/enviar/apagar por SSH,
  releitura no sandbox, carimbo do servidor preservado via `criado_em`
  opcional em `banco.registrar_artefato`), `cli.py sincronizar-vps`. 16
  testes novos (41 no total), todos com mock — nenhum contato real com o
  servidor ainda. Achado de processo: `raiz_backup()` prioriza o
  `configuracao.local.json` real sobre a env var de teste; os testes
  precisam trocar `ARQUIVO_CONFIGURACAO` também, não só o env var
  (documentado na seção 18).
- **2026-08-20 (continuação)** — **Fase 5 executada e verificada** (seção 19):
  primeiro ciclo real contra o servidor, funcionou de primeira. 7 dumps
  buscados (0 reprovados), servidor ficou com um por projeto, catálogo local
  com 76 artefatos íntegros, `criado_em` gravado com o carimbo do servidor
  (confirmado batendo com UTC-3). Idempotência confirmada rodando o ciclo de
  novo em seguida (0 buscados, tentativa de apagar o único dump restante
  recusada pelo servidor). **A produção do VPS já tem cópia fora do
  servidor, verificada.**
- **2026-08-20 (continuação)** — **Fase 6 executada e verificada** (seção 20):
  `cli.py ensaio --projeto mega_sena_vps` restaurou de verdade o artefato #94
  no sandbox — 5 tabelas, 3.053 linhas. Comparação manual com a produção
  (chave de administração, fora do código do app, de propósito — D1) mostrou
  `draws` batendo exato (3.046=3.046) e `users`/`generated_bets` maiores na
  produção (cresceram desde a captura de 04:03 UTC) — divergência esperada,
  não falha. Decisão: não dar ao agente do VPS um verbo de consulta SQL só
  para automatizar essa comparação — mais superfície numa chave que já lê
  dados de produção, por um ganho que não se paga (conferência pontual, não
  recorrente). `cli.py comando_ensaio` ganhou um branch pequeno para
  `ambiente != "local"` que mostra o resumo do destino restaurado sem tentar
  `comparar_com_origem` (que continua recusando, por desenho da Fase 3). 42
  testes.
- **2026-08-20 (continuação)** — **Fase 7 executada e verificada** (seção 21):
  tarefa `BackupRestoreVPS` criada (`sincronizar-vps --todos`, 03:30, meia
  hora depois do timer do servidor). Achado real: a primeira execução via
  Agendador falhou com `Permission denied (publickey)` — a chave dedicada
  tinha ACL aberta (herdada de um terminal Git Bash), e o OpenSSH real do
  Windows recusa chave privada legível por mais de um principal; corrigido
  com `icacls /inheritance:r`, documentado no README para a próxima chave.
  Sandbox precisou passar a ficar de pé entre ciclos (antes era
  criado/destruído a cada uso manual). Tela agrupada em "Neste computador" /
  "Produção (VPS)" em painel/projetos/retenção — e um bug cosmético real
  corrigido de passagem: projeto `_vps` aparecia "Incompleto" para sempre
  porque a checagem de integridade exigia banco E código incondicionalmente.
  42 testes, catálogo inalterado (76/0/0).
- **2026-08-20 (continuação)** — **Fase 8 executada e verificada** (seção 22),
  última do plano. Documentação atualizada nos quatro documentos: README
  (Camada 2 na abertura, comandos, agendamento, "sete regras" corrigida para
  par), RESTAURAR.md (reconstrução a partir de dump VPS, ensaio sem
  comparação automática), KIT_RECUPERACAO.md (tabela de segredos do VPS por
  projeto — D5), AGENTS.md (`vps.py` nos invariantes). Pendência real
  registrada em vez de fingida: a cópia do nginx (D5) nunca foi feita, e o
  texto agora diz isso. **O plano de backup do VPS está concluído — as oito
  fases feitas e validadas.** Pendências fora do escopo das fases: cópia do
  nginx, extração de segredos do VPS para o cofre (ambas sempre manuais, por
  decisão de escopo).
