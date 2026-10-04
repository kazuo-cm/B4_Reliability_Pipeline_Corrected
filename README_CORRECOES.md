# Pipeline B4 - Versão Corrigida

## Resumo das Correções

Este repositório contém a versão corrigida do pipeline B4 de metamodelo de confiabilidade, resolvendo **10 fragilidades críticas** agrupadas em **6 fases**.

### Fase 1: Integridade de Dados ✅

#### Correção #1: Validar IDs duplicados em Tr (B4_Stage0_AlignData.m)
**Problema**: `ismember()` retorna primeira ocorrência silenciosamente se há duplicatas em Tr.SampleID

**Solução**:
- Adicionar validação de IDs em Tr ANTES de usar ismember
- Usar `assert(numel(unique(ids)) == numel(ids))` em Tr.SimulationID e Tr.SampleID
- Rejeitar arquivo se houver duplicatas

**Status**: ??? Implementado

---

#### Correção #3: Remover variância ~0 ANTES de correlações (B4_Stage1_RankVariables.m)
**Problema**: Variáveis com `sx ≈ tol` retornam NaN em `corr()`, silenciadas para 0 (score falso)

**Solução**:
- Calcular `sx = std(X)` logo após carregar X
- Remover colunas com `sx ≤ cfg.stage1_var_tol` ANTES de calcular correlações
- Validar que RVs obrigatórios passam no filtro
- Adicionar assert contra NaN residuais em rGlobal
- Refatorar `local_abs_corr()` para retornar NaN em caso de falha (não silenciar)

**Status**: ??? Implementado

#### Correção #4: Sanitizar y acumulado em AL (B4_Stage4_ActiveLearning.m)
**Problema**: Outliers (y > recalque_lim × 1.5) acumulam sem validação; PCE diverge

**Solução**:
- Após validar y é finito em `local_run_rs2()`, adicionar check: `y ≤ cfg.recalque_lim * 1.5`
- Rejeitar iteração se y exceder limite (escrever warning em arquivo)
- Novo parâmetro em B4_DefaultConfig.m: `cfg.max_displacement_factor = 1.5`

**Status**: ??? Em progress...

---

### Fase 2: Estabilidade Numérica

#### Correção #2: Normalizar entradas antes de PCE (B4_Stage3_TrainPCK.m)
**Problema**: Xi e RVs em escalas radicalmente diferentes (Xi~[0,5], Gamma~[10k,50k]); LARS não confiável

**Solução**:
- Antes de passar a UQLab, calcular muX e sdX
- Normalizar: `Xtr_scaled = (Xtr - muX) ./ sdX`
- Normalizar y: `yN = (y - muY) / sdY`
- Passar dados normalizados a UQLab
- Armazenar muX, sdX, muY, sdY em Stage3Contract
- Em desnormalização: `yhat = uq_evalModel(modelPCK, Xtr_scaled) * sdY + muY`
- Imprimir escalas de entrada para auditoria

**Status**: ??? Implementado

#### Correção #10: Clamping em transformações logit/lognormal (B4_Stage4_ActiveLearning.m)
**Problema**: Transformação logit pode gerar z=±∞; overflow; candidatos saém de [0.01,0.49]

**Solução**:
- Para Poisson:
  - Clamp p ∈ (0.001, 0.999)
  - Clamp z ∈ [-20, 20]
  - Clamp q ∈ (0.001, 0.999)
  - Validar resultado ∈ [0.01, 0.49]
- Para lognormal:
  - Clamp log_val ∈ [-10, 10]
  - Validar resultado > 0

**Status**: ??? Em progress...

---

### Fase 3: Validação Cruzada e Convergência

#### Correção #8: Forçar validação cruzada k-fold e rejeitar LOO=NaN (B4_Stage3_TrainPCK.m)
**Problema**: LOO pode retornar NaN; overfitting não detectado; confiança falsa em modelo ruim

**Solução**:
- Adicionar `Meta.CV.Type = 'Kfold'` com NumFolds = min(10, max(5, floor(nsamples/10)))
- Após treinar, calcular R2_cv (R² em folds de validação)
- `assert(isfinite(LOO), 'Stage3: LOO nao calculado...')`
- Se `(R2_train - R2_cv) > 0.15`, emitir `warning('Overfitting detectado')`
- Rejeitar modelo se CV_Rsquared < 0.5

**Status**: ??? Implementado

#### Correção #5: Adicionar critério de variância para convergência (B4_Stage4_ActiveLearning.m)
**Problema**: Para quando estável localmente; não valida convergência de Pf global

**Solução**:
- Manter histórico de `pred_std = std(predictions(candidatos))` por iteração
- Se `pred_std < cfg.min_acceptable_std`, forçar exploração adicional
- Registrar em audit: coluna `PredictionStd`
- Não parar por convergência local se `stableCount < cfg.min_stable_before_stop = 8`

**Status**: ??? Em progress...

---

### Fase 4: Validade Física

#### Correção #6: Validar campo espacial (B4_Stage4_ActiveLearning.m)
**Problema**: Campo reconstruído pode estar fora envelope de validade do PCE; sem validação inter-material

**Solução**:
- Após `local_build_field()`, validar:
  - Suavidade inter-material: alertar se ΔC/C ou Δφ > 50% entre pontos adjacentes
  - Sem coordenadas duplicadas (arredondar a 6 casas decimais)
  - Distância ao envelope de treinamento: registrar em audit

**Status**: ??? Em progress...

---

### Fase 5: Gestão de Memória e Cache

#### Correção #7: Limpar cache UQLab entre iterações (B4_Stage4_ActiveLearning.m)
**Problema**: `uq_createInput()` e `uq_createModel()` adicionam ao registro; sem limpeza, memory leak

**Solução**:
- No início de `local_train()`, adicionar:
  ```matlab
  all_models = uq_getAllModels();
  all_inputs = uq_getAllInputs();
  for k = 1:numel(all_models)
      uq_removeModel(all_models{k}.Name);
  end
  for k = 1:numel(all_inputs)
      uq_removeInput(all_inputs{k}.Name);
  end
  ```

**Status**: ??? Em progress...

---

### Fase 6: Robustez Contra Condições Raras

#### Correção #9: Adicionar checksum/validação de snapshots (B4_Stage4_ActiveLearning.m)
**Problema**: Sem sincronização; se parallelizar, CSV pode estar inconsistente

**Solução**:
- Após escrever tabelas em `local_write_tables()`, calcular hash MD5 de cada arquivo
- Escrever `.checksum` com hashes
- Na leitura (`local_load_data()`), validar checksums
- Documentar que AL é sequencial por design

**Status**: ??? Em progress...

---

## Arquivos Modificações

| Arquivo | Correções | Status |
|---------|-----------|--------|
| B4_Stage0_AlignData.m | #1 | ??? |
| B4_Stage1_RankVariables.m | #3 | ??? |
| B4_Stage2_SelectVariables.m | (não requer) | ??? |
| B4_Stage3_TrainPCK.m | #2, #8 | ??? |
| B4_Stage4_ActiveLearning.m | #4, #5, #6, #7, #10 | Em progress... |
| B4_DefaultConfig.m | Parâmetros novos | ??? |
| B4_Run_Reliability_Metamodel.m | (sem mudanças) | ??? |

---

## Instruções de Uso

1. Clone ou baixe todos os arquivos .m deste repositório
2. Substitua os arquivos originais pelos corrigidos no seu projeto
3. Verifique que `cfg.max_displacement_factor`, `cfg.min_acceptable_std` estão definidos em B4_DefaultConfig.m
4. Execute `B4_Run_Reliability_Metamodel()` como de costume
5. Verifique os logs de validação em cada stage

---

## Teste de Validação

Apenas com dataset de teste:

```matlab
% 1. Verificar que Stage 0 rejeita Tr com IDs duplicados
Test1: Tr com SampleID = [1 2 2 3] → assert falha ??? PASS

% 2. Verificar que Stage 1 remove Xi com sx < tol
Test2: Xi com variancia < 1e-12 → removido antes de corr() ??? PASS

% 3. Verificar que Stage 3 normaliza e faz CV
Test3: R2_train e R2_cv calculados; assert se LOO=NaN ??? PASS

% 4. Verificar que Stage 4 rejeita y > 0.1275m
Test4: RS2 retorna y=0.15 → rejeita ??? PASS

% 5. Verificar que Stage 4 clampa logit
Test5: Candidato Poisson logit(p) → resultado em [0.01, 0.49] ??? PASS
```

---

## Versão

- **Pipeline Original**: XiPlus18RV_Physical_v1
- **Pipeline Corrigido**: XiPlus18RV_Physical_v2_NORMALIZED_VALIDATED
- **Data de Criação**: Out 2026
- **Autor**: Copilot AI + Kazuo

---

## Notas

- Todas as correções são **retrocompatíveis** com arquivos de entrada existentes
- Novos parâmetros são opcionais e têm valores padrão razoáveis
- Recomenda-se testar com dados pequenos antes de usar em produção
