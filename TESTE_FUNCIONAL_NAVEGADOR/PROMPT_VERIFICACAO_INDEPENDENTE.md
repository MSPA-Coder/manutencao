# Prompt de verificação independente

Copie tudo abaixo da linha para uma nova IA. Ela não conhece a conversa
anterior e deve atuar como revisora independente, não como implementadora.

---

Você deve verificar, com evidências, se todo o trabalho definido nesta rodada
foi tratado e resolvido em quatro aplicações locais e no VPS. Não confie
cegamente nos relatórios: eles são o mapa inicial, não a prova final.

## Escopo e restrições

- Workspace: `C:\Users\MSPA\Dropbox\Programacao\VSCodeProjects`.
- Sistemas: ConfortoTermico (5001), MegaSena (5101), ControleBancario (5201)
  e ControleRendaVariavel (5301). Todos usam Docker Compose.
- O código de cada sistema foi integrado em `main`, publicado e implantado no
  VPS. Confirme o estado, não altere código, banco, Docker, VPS ou credenciais.
- Use as interfaces Docker documentadas por cada repositório. Não instale
  dependências no host, não leia segredos e não imprima tokens/senhas.
- Para navegar, o mantenedor faz o login. Você nunca digita senha, não cria ou
  reseta senha e não conclui uma troca de senha. A validação visual de senha
  temporária é a única exceção aceita desta revisão.
- Não execute ações destrutivas, importações, uploads, fechamento mensal,
  `VACUUM`, reset ou limpeza. Faça somente verificações de leitura e testes
  isolados/documentados pelos repositórios.

## Leitura obrigatória

Leia nesta ordem:

1. `_manutencao/TESTE_FUNCIONAL_NAVEGADOR/ANDAMENTO.md`
2. `_manutencao/TESTE_FUNCIONAL_NAVEGADOR/STATUS_CB.md`
3. `_manutencao/TESTE_FUNCIONAL_NAVEGADOR/CONCLUSOES_TRANSVERSAIS.md`
4. Os quatro `AGENTS.md`, `README.md` e `compose.yaml` dos projetos.

`PROMPT_RETOMADA.md` é histórico e está obsoleto; não o use para concluir que
há trabalho pendente.

## Fatos que precisam ser verificados

1. As correções aprovadas das seis decisões de produto estão em `main`, têm
   testes e continuam presentes no código: falha fechada do CB, modo discreto,
   auditoria, ciclo de vida de cadastros e frescor/histórico.
2. Os quatro repositórios estão limpos e as validações de qualidade documentadas
   continuam reproduzíveis em Docker.
3. O VPS está no mesmo commit publicado de cada projeto e os serviços/health
   checks estão saudáveis. Não execute deploy.
4. Claudia no ControleBancario é `user`, ativa e tem somente o perfil Operador
   (12 permissões funcionais). Confirme que não possui permissões críticas; o
   acesso aos três titulares é configuração deliberada de titular e não deve
   ser confundido com a permissão funcional.
5. A matriz de autorização foi verificada no navegador para Claudia no CB e em
   testes de servidor nos demais sistemas. Diferencie evidência de navegador de
   evidência automatizada.
6. Os uploads foram exercitados: MegaSena aceitou XLSX idêntico como ignorado;
   CB ignorou CSV duplicado e aceitou/removiu comprovante de teste. Confirme que
   não há comprovante de teste nem conta/registro `ZZTESTE` residual.
   O único artefato conhecido fora dos repositórios é o fixture inofensivo
   `CodexTemp/mega-upload-duplicate.xlsx`; apenas registre sua presença, não o
   remova nesta revisão de leitura.
7. O `VACUUM ANALYZE` do CB foi executado com sucesso.
8. O ConfortoTermico local tem propositalmente zero gerações/medições de
   `dados_entrada` e histórico zerado, resultado de exclusões autorizadas sem
   backup. Zonas, equipamentos e usuários devem continuar existentes. Trate
   isso como estado conhecido, não como falha nova.

## Método de verificação

- Compare o estado local com `origin/main`, PRs/commits e o VPS por comandos
  somente leitura. Se houver diferença, identifique o commit e o impacto.
- Prefira testes focados para autenticação/autorização e comandos oficiais de
  health. Não reduza controles para fazê-los passar.
- Se o mantenedor disponibilizar sessão no navegador, confira apenas fluxos
  não destrutivos e registre identidade/papel, rota e resposta. Não trate item
  oculto na interface como prova: confira a recusa no servidor.
- Investigue qualquer contradição entre relatório, código, banco e serviço.
  Não aceite um diagnóstico sem ler a implementação correspondente.

## Entrega esperada

Forneça um relatório conciso em português com uma tabela contendo:

- item/decisão original;
- evidência verificada;
- estado: `confirmado`, `parcial`, `divergente` ou `não verificável`;
- ação necessária, se houver.

Conclua explicitamente se há algo pendente além da validação visual de senha
temporária. Se não houver, diga se a única pendência operacional é commitar os
três relatórios modificados em `_manutencao/TESTE_FUNCIONAL_NAVEGADOR/`.
