# B4_Reliability_Pipeline_Corrected
Pipeline B4 corrigido: 10 fragilidades críticas resolvidas (6 fases). Integridade de dados, normalização numérica, validação CV, campo espacial.

## Auditoria de diferenças de Pf no B5 (integração pendente)

Este clone não contém `B5_Official_Run`, `B5_Validate_LHS_Model`,
`B5_UQLab_Reliability_Skeleton`, `B5_Run_Reliability_Analysis` ou
`B5_Compare_Pf_FORM_MCS`. O PR #1 propõe versões `_CORRECTED`; elas não
foram copiadas, substituídas nem integradas aqui. O PR #2 acrescenta somente
`B5_Audit_Relative_Pf.m` e testes autocontidos. B4 permanece inalterado.

**A diferença é diagnóstica, não prova de erro, acurácia ou convergência.**
RS2 treinamento/AL é uma frequência empírica de um conjunto adaptativo,
não necessariamente representativo da distribuição global. Compará-lo
com base, avaliação externa ou truncada não valida Pf global; a truncada
muda a distribuição. Nenhum Pf esperado é imposto a FORM/MCS/SS.

### Contrato e chamada

O módulo recebe uma `table report` com `Metodo`, `Pf`, `Status`, já
calculados, e uma `table rowInfo` alinhada (uma linha para cada método).
Não depende de UQLab e não calcula nem altera as estimativas Pf:

```matlab
% Exemplo mínimo: substituir pelos resultados reais desta execução.
report = table(["RS2 treinamento/AL"; "FORM base"], [0.085784; 0.0475], ...
    ["OK"; "OK"], 'VariableNames', {'Metodo','Pf','Status'});
rowInfo = table(["reference"; "estimate"], ["training_al"; "base"], ...
    [NaN; NaN], [true; true], [1200; NaN], ...
    'VariableNames', {'Role','Scope','ReferenceRow','AnalysisSucceeded','SampleCount'});
% runDir deve ser a pasta isolada real da execução, nunca compartilhada.
out = B5_Audit_Relative_Pf(report, rowInfo, 'RunDir', runDir, ...
    'ReferencePf', NaN, 'Verbose', true);
report = out.report;
```

- `Role`: `reference` para RS2 empírico, `estimate` para os demais.
- `Scope`: `training_al`, `external`, `base`, `truncated` ou `unknown`.
  Identificar explicitamente **uma** referência RS2 `training_al` desta
  execução; não inferir por nome nem usar Pf armazenado de outra execução.
- `ReferenceRow`: índice de RS2 nos **mesmos casos** para cada comparação
  local surrogate/RS2; `NaN` nos demais. O chamador deve confirmar igualdade
  dos IDs dos casos, não apenas do tamanho/scope. O módulo valida papel/scope,
  mas não dispõe de IDs para comprovar pareamento.
- `AnalysisSucceeded`: logical obrigatório, obtido do resultado efetivo
  da análise (false em exceções/falhas, mesmo com Pf residual finito).
  `Status` é preservado e registrado, sem presumir um vocabulário de sucesso.
- `SampleCount` e `Reason`: opcionais; registrar somente contagens reais e
  mensagens reais de falha. Contagem ausente fica `NaN`.
- `ModelFile`: opção para o caminho real do modelo; ausente fica vazio.
  `ReferenceMethod` identifica a referência explícita (padrão `ReferencePf`).

Referências locais `same_cases` são preservadas. Nos demais métodos,
`ReferencePf` explícito tem precedência; somente `NaN` ativa o fallback
automático. Uma referência automática não finita, zero, inválida ou falha
fica registrada, mas **não permite diferença relativa**. Referência explícita
inválida também não é substituída silenciosamente. Zero nunca vira `eps`.
RS2 não recebe erro zero arbitrário. Pf método zero é válido quando a
referência é positiva. Pf fora de [0,1], não finito ou análise falha não é
calculado; a razão permanece na auditoria. Não se promete eliminar todos
os NaN. A fórmula única é `100*abs(PfEstimate-ReferencePf)/ReferencePf`.

### Integração necessária quando os módulos B5 estiverem disponíveis

1. No **motor**, após obter resultados ou capturar falhas, montar `report`
   e metadados para todas as linhas, inclusive FORM/MCS/SS base e FORM/MCS
   truncada. Remover os cálculos duplicados de `ErroRelativoPf_pct` e chamar
   esta API onde o cálculo realmente ocorre, não só no Skeleton.
2. Skeleton e comparativo devem encaminhar `ReferencePf`, `Verbose`,
   `ModelFile`, `runDir` e os resultados do motor; o comparativo que calcula
   seus próprios resultados deve usar a mesma API. Repassar
   `out.relativeErrorAudit` e `out.relativeErrorAuditFile`.
3. Na consolidação oficial, incluir a avaliação externa
   `RF_5Mat_3Var_400Sim_metamodelo` como `external`, com Pf e contagem próprios.
   Se substituir a linha de treinamento, **recalcular** a auditoria do
   relatório consolidado; nunca reutilizar o erro de treinamento. Usar
   `ReferenceRow` externo somente se houver RS2 para os mesmos casos;
   senão registrar a comparação diagnóstica explícita/automática.
   Se remover a linha RS2 treinamento/AL do resumo, manter essa referência
   no relatório de cálculo auditado, antes de selecionar as linhas do resumo.
4. Mesclar estes campos no `out` existente, sem perder outros resultados,
   e incluí-los no MAT oficial. A API já grava a table e caminho num MAT
   próprio junto com `out.report`. Chamadas na mesma `runDir` substituem os
   dois arquivos com o relatório recebido; para motor/comparativo distintos,
   usar subpastas isoladas ou consolidar todas as linhas antes de gravar.
5. Preservar no preditor PCK entradas físicas na ordem `vars_train`,
   `(X-muX)./sdX`, `uq_evalModel`, depois saída `*sdY+muY`
   (escalas salvas em `B4_Stage3_TrainPCK.m`). Não adicionar
   `Gopts.Type='Model'`. Nenhuma distribuição ou convergência B4 é alterada.

### Artefatos e logs

Na pasta indicada: `pf_relative_error_audit.csv` e
`pf_relative_error_audit.mat`. CSV/table contêm `Timestamp`, `Method`,
`PfEstimate`, `ReferenceMethod`, `ReferencePf`, `ReferenceSource`
(`explicit`, `automatic`, `same_cases`, ou vazio sem comparação),
`AbsoluteDifference`, `RelativeDifferencePercent`, `Formula`,
`CalculationStatus`, `Reason`, `ComparisonScope`, `Interpretation`,
`ModelFile`, `runDir`, `SampleCount`, `ReferenceSampleCount`, `AnalysisStatus`.
O timestamp é horário local da gravação, sem alegar UTC. Linhas de referência
têm referência/diferença ausentes e motivo explícito.

Exemplo de conteúdo do log (valores exibidos arredondados, cálculo exato):

```text
[B5 Pf audit] WARNING: differences are diagnostic, not proof of global accuracy/convergence.
[B5 Pf audit] FORM base | Pf=0.0475 | ref=RS2 treinamento/AL (0.085784) | source=automatic | ref N=1200 | abs=0.038284 | relative=44.62836893% | calculated | Diagnostic difference only; not evidence of accuracy or convergence. Adaptive RS2 training/AL is not necessarily representative of global Pf.
```

`Verbose=false` suprime somente o console de auditoria, não CSV/MAT.
Referência zero, NaN e falhas produzem `not_calculated` com motivo, inclusive
para análises que lançaram exceção, desde que o motor inclua a linha falha.

### Testes sem UQLab

A partir da raiz do repositório no MATLAB:

```matlab
addpath(pwd);
results = runtests(fullfile(pwd, 'tests', 'test_B5_Audit_Relative_Pf.m'));
assert(all([results.Passed]));
```

Cobertura: referência explícita/fallback, zero, NaN, método e referência
falhos, ausência de referência, referência inválida sem fallback,
truncada diagnóstica, substituição por avaliação externa, pareamento,
verbosidade e consistência CSV/table/report/MAT. O fixture usa a expressão
exata para 0.085784 e 0.0475, não um percentual arredondado.
**Não executados neste ambiente:** testes MATLAB e execução B5/UQLab,
pois MATLAB/Octave e os módulos de execução B5 não estão disponíveis.
Não houve alteração em arquivos locais do computador do usuário.
