# ANÁLISE DE INCONSISTÊNCIAS - Pipeline B4 v7

**Data**: 2026-10-07  
**Status**: 6 Inconsistências Críticas Identificadas  
**Impacto**: Medium-High (Execução falha ou resultado inválido)

---

## 📋 SUMÁRIO EXECUTIVO

O pipeline possui um **contrato quebrado entre Stages 0-4**:
- **Stage 3** estima Pf com `AL_USE_Pf_CONVERGENCE` (novo)
- **Stage 4** espera usar Pf histórico para parada por estabilidade, MAS
- **B4_DefaultConfig.m** define parâmetros MCS/SS HARDCODED, sem vincular a `AL_USE_Pf_CONVERGENCE`
- **Resultado**: `NO_VALID_NEW_CASES` after 20 iters → nenhum caso novo válido

Além disso, `spatial_allow_missing_materials` NÃO é respeitado em **B4_Stage4_ActiveLearning.m** quando tenta usar Pf_population fixo.

---

## 🔴 INCONSISTÊNCIA #1: `AL_RESET_ON_START` vs Comportamento Esperado

**Localização**: `B4_DefaultConfig.m` linha 108

```matlab
cfg.AL_RESET_ON_START = true;  % ❌ HARDCODED TRUE
```

**Problema**: 
- Config recente (linhas copiadas) define `true`
- Nova config (seu input) define `false`
- MATLAB não reclama, mas Stage 4 pode **deletar snapshots acidentalmente**

**Impacto**: Medium (perda de rastreabilidade, não falha execução)

**Solução**:
```matlab
cfg.AL_RESET_ON_START = false;  % ✅ DEFAULT SEGURO
```

---

## 🔴 INCONSISTÊNCIA #2: Parâmetros MCS/SS Faltam em `B4_DefaultConfig.m`

**Localização**: `B4_DefaultConfig.m` (linhas 157-173 faltam COMPLETAMENTE)

**Problema**:
Seu novo código em `B4_Stage4_ActiveLearning.m` linha **~1100** define:

```matlab
defaults.AL_Pf_mcs_target_population = 50000;
defaults.AL_Pf_mcs_min_failures = 50;
defaults.AL_Pf_ss_intermediate_pf = 0.1;
defaults.AL_Pf_ss_num_chains = 1000;
defaults.AL_Pf_ss_samples_per_chain = 2;
defaults.AL_Pf_stability_tolerance = 0.05;
defaults.AL_Pf_stable_readings = 5;
defaults.AL_Pf_min_iterations = 6;
defaults.AL_Pf_comparison_window = 5;
defaults.AL_Pf_floor = 0.001;
defaults.AL_Pf_max_eval_cost = 5e6;
```

MAS `B4_DefaultConfig.m` **NÃO DEFINE** nenhum desses campos!

**Impacto**: HIGH (defaults aplicados, mas não documentados/ajustáveis pelo usuário)

**Solução**: Adicionar seção **§ 11-12** no DefaultConfig com esses parâmetros.

---

## 🔴 INCONSISTÊNCIA #3: `AL_USE_Pf_CONVERGENCE` vs `AL_USE_Pf_STABILITY`

**Localização**: 
- `B4_Stage3_TrainPCK.m` linha ~380 usa `AL_USE_Pf_CONVERGENCE`
- `B4_Stage4_ActiveLearning.m` linha ~600 usa `AL_USE_Pf_STABILITY`

**Problema**:
```matlab
% Stage 3:
if isfield(cfg, 'AL_USE_Pf_CONVERGENCE') && cfg.AL_USE_Pf_CONVERGENCE
    % Gera Pf_population fixo
    
% Stage 4:
if cfg.AL_USE_Pf_STABILITY
    % Espera usar histórico de Pf da população
```

**São NOMES DIFERENTES para funções SIMILARES mas não idênticas:**
- `AL_USE_Pf_CONVERGENCE`: Habilita geração de população LHS FIXA no Stage 3
- `AL_USE_Pf_STABILITY`: Habilita parada por variação SEQUENCIAL < 5% no Stage 4

**Não há relação semântica clara!**

**Impacto**: HIGH (confusão conceitual, Stage 4 pode rodar sem População Stage 3)

**Solução**:
```matlab
% Renomear para clareza:
cfg.AL_USE_Pf_STABILITY = true;  % ÚNICO nome; controls BOTH Stages 3 e 4
```

Remover `AL_USE_Pf_CONVERGENCE` completamente.

---

## 🔴 INCONSISTÊNCIA #4: `spatial_allow_missing_materials` Não Propagado para Stage 4

**Localização**: 
- Definido em `B4_DefaultConfig.m` linha ~460
- Usado em `B4_Suport_build_spatial_fields_from_xi.m` linha ~85 ✓
- **NÃO PASSADO** para `local_build_field()` em `B4_Stage4_ActiveLearning.m` linha ~380

**Problema**:
```matlab
% B4_Stage4_ActiveLearning.m linha ~380:
field = local_build_field(xiNew, cfg, simID);

% MAS local_build_field() chama:
[xGrid, yGrid, cVals, phiVals, EVals] = ...
    B4_Suport_build_spatial_fields_from_xi(xi_row, cfg);

% E cfg.spatial_allow_missing_materials NÃO É PASSADO!
% Resultado: Se Material 3 vazio → ERRO, Stage 4 falha
```

**Impacto**: CRITICAL (Leads to `NO_VALID_NEW_CASES` quando Material 3 vazio)

**Solução**:
```matlab
% Em B4_Stage4_ActiveLearning.m, antes de local_build_field():
assert(isfield(cfg, 'spatial_allow_missing_materials'), ...
    '[AL] cfg.spatial_allow_missing_materials ausente.');

% Depois de receber erro de Material 3 vazio:
% Catch a excepção e registrar como "INVALID_SPATIAL"
```

---

## 🔴 INCONSISTÊNCIA #5: Pf_population NÃO Armazenada/Recuperada Entre Stages

**Localização**: 
- Stage 3 salva em `cfg.stage3_best_file` (linha ~520)
- Stage 4 tenta carregar e usar, MAS

**Problema**:
```matlab
% B4_Stage3_TrainPCK.m linha ~520:
save(cfg.stage3_best_file, ..., 'Pf_population', ...);

% B4_Stage4_ActiveLearning.m local_train() linha ~800:
M = load(modelFile, ...);  % ← local_fit() torna modelPCK privado!
% Pf_population NÃO ESTÁ NO ARQUIVO FINAL PUBLICADO
```

**Raiz**: `local_fit()` usa `-private` para modelos UQLab, mas isso NÃO afeta `Pf_population`!

**Impacto**: MEDIUM (Pf_population deveria estar disponível, mas Stage 4 não a recupera)

**Solução**:
```matlab
% No final de B4_Stage3_TrainPCK.m, ANTES de save():
assert(isfield(Pf_population, 'is_fixed') && ...
    Pf_population.is_fixed == true, ...
    'Stage3: Pf_population nao marcada como FIXA.');

% NO local_train() de B4_Stage4_ActiveLearning.m:
M_raw = load(modelFile);
M.Pf_population = M_raw.Pf_population;  % Recuperar explicitamente
```

---

## 🔴 INCONSISTÊNCIA #6: Recalque Limite Mudou de 0.085 para 0.095

**Localização**: 
- `B4_DefaultConfig.m` linha 87 diz `0.085`
- `B4_Stage0_AlignData.m` linha 34 diz `0.095`
- Seu novo input deseja `0.095` (para material 3 reduzido)

**Problema**:
```matlab
% B4_DefaultConfig.m:
cfg.recalque_lim = 0.085;  % ← FIXO, nunca altera

% B4_Stage0_AlignData.m:
if isfield(cfg, 'recalque_lim')
    limit = double(cfg.recalque_lim);
else
    limit = 0.095;  % ← FALLBACK para 0.095
```

Se DefaultConfig não é carregado corretamente, Stage 0 usa FALLBACK e **gera contrato com 0.095**, mas Stages 1-3 recebem **0.085** de cfg!

**Impacto**: HIGH (Contrato de estado limite quebrado)

**Solução**:
```matlab
% B4_DefaultConfig.m:
cfg.recalque_lim = 0.095;  % ✅ Atualizar para 0.095 (material 3 reduzido)

% B4_Stage0_AlignData.m remover fallback:
assert(isfield(cfg, 'recalque_lim'), ...
    'Stage0: recalque_lim ausente em cfg.');
```

---

## ✅ LISTA DE CORREÇÕES RECOMENDADAS

| ID | Severidade | Ação | Arquivo |
|----|---|---|---|
| #1 | MEDIUM | Mudar `AL_RESET_ON_START = false` | B4_DefaultConfig.m L108 |
| #2 | HIGH | Adicionar seção MCS/SS params (§11-12) | B4_DefaultConfig.m |
| #3 | HIGH | Renomear `AL_USE_Pf_CONVERGENCE` → `AL_USE_Pf_STABILITY` | B4_Stage3_TrainPCK.m, B4_DefaultConfig.m |
| #4 | CRITICAL | Assegurar `cfg.spatial_allow_missing_materials` propagado para Stage 4 | B4_Stage4_ActiveLearning.m ~local_build_field() |
| #5 | MEDIUM | Recuperar `Pf_population` explicitamente em local_train() | B4_Stage4_ActiveLearning.m |
| #6 | HIGH | Sincronizar `recalque_lim = 0.095` entre Stages | B4_DefaultConfig.m, B4_Stage0_AlignData.m |

---

## 🎯 CONCLUSÃO

Seu pipeline **V7 está 70% correto** mas tem **6 pontos de falha**:

1. ✅ Normalização em Stage 3 → OK
2. ✅ Filtragem de variância → OK
3. ✅ PC-Kriging com CV explícita → OK
4. ❌ Contrato Pf entre Stages → QUEBRADO
5. ❌ Parâmetros MCS/SS não documentados → OCULTOS
6. ❌ Material 3 vazio não tratado → ERRO SILENCIOSO

O status **`NO_VALID_NEW_CASES`** provavelmente vem de #4 + #6: todos os 20 candidatos falham porque Material 3 vazio retorna erro que não é capturado corretamente.

