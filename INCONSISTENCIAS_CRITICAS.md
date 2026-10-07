# 📋 Inconsistências Críticas Encontradas - B4 Pipeline v6

**Data**: 2026-10-07  
**Versão Analisada**: B4_NormalizedPCK_LocalAL_Pf_MCS_SS_Robust_v6  
**Status**: ⚠️ **6 críticas** | ✅ **Soluções documentadas**

---

## 🔴 CRÍTICA #1: Faixa de Pf invertida (sinais de sigma)

### Arquivo: `B4_Stage3_TrainPCK.m` (linhas 559-568)

**Problema:**
```matlab
% CÓDIGO ATUAL (INCORRETO):
Pf_low = mean(g_pop + kfactor .* Ypop_std_est <= 0);  % Otimista
Pf_high = mean(g_pop - kfactor .* Ypop_std_est <= 0); % Pessimista
```

**Análise:**
- Estado limite: `g = recalque_lim - y` → Falha quando `g ≤ 0` (y ≥ limite)
- Adicionando `+k*σ` **aumenta o numerador** → condição ≤ 0 **mais fácil** → **mais falhas** (pessimista)
- Subtraindo `-k*σ` **reduz o numerador** → condição ≤ 0 **mais difícil** → **menos falhas** (otimista)
- **Comentários estão invertidos!**

**Solução Corrigida:**
```matlab
% CORRETO:
Pf_low = mean(g_pop - kfactor .* Ypop_std_est <= 0);   % Otimista (menos falhas)
Pf_high = mean(g_pop + kfactor .* Ypop_std_est <= 0);  % Pessimista (mais falhas)

% Comentário correto:
fprintf('[Stage3] Pf faixa [otimista, pessimista]: [%.6f, %.6f]\n', ...
    Pf_low, Pf_high);
```

**Impacto:** ⚠️ **CRÍTICO**
- Historicamente inverteu interpretação de margem de segurança
- Afeta decisões de parada no Stage 4 (convergência questionável)
- Recomendação: reiniciar Stage 4 após correção

---

## 🔴 CRÍTICA #2: Função geração de população Pf não existe

### Arquivo: `B4_Stage4_ActiveLearning.m` (linha 1288)

**Problema:**
```matlab
% CÓDIGO ATUAL:
[Pf_current, nfail_mcs, method_used, status_txt] = ...
    local_estimate_pf_hybrid_mcs_ss(M, cfg);
```

**Análise:**
- Função `local_estimate_pf_hybrid_mcs_ss()` é **chamada** (linha 1288)
- Implementação está **incompleta** (linhas 1571-1632)
- Sub-função `local_generate_probabilistic_population()` **sem variância heteroscedástica**
- SS fallback usa marginais **uniformes** (não gaussianas como Xi real)

**Solução Necessária:**
✅ Arquivo corrigido: `B4_Stage4_ActiveLearning_FIXED.m`

**Impacto:** ⚠️ **CRÍTICO**
- Estimativa de Pf pode estar **subestimada** (100+ casos simulados, sem capturar incerteza)
- Parada por convergência baseada em estimativa incorreta

---

## 🔴 CRÍTICA #3: Material vazio tolerado mas não documentado

### Arquivo: `B4_Suport_build_spatial_fields_from_xi.m` (linhas 89-108)

**Problema:**
```matlab
% CÓDIGO ATUAL:
if isEmptyField
    if ~allowMissing
        error('B4:MaterialEmpty', ...);
    end
    
    materialFields{matID} = local_empty_field(requiredColumns);
    materialStatus(matID) = "EMPTY_SKIPPED";
    fprintf('[Spatial] Material %d vazio; ignorado por configuracao.\n', matID);
    continue;
end
```

**Análise:**
- Se `cfg.spatial_allow_missing_materials = true` → material vazio é **silenciosamente ignorado**
- Python/RS2 recebe campo com **4 materiais** em vez de **5**
- Simulação pode ser **inválida** se depender de material vazio
- **Log aviso não propagado para auditoria do Stage 4**

**Solução Necessária:**
✅ Arquivo corrigido: `B4_Suport_build_spatial_fields_from_xi_FIXED.m`

**Impacto:** ⚠️ **CRÍTICO**
- Casos com material vazio passam como "válidos" mas podem ser **fisicamente inválidos**
- Auditoria do AL não distingue "válido com material reduzido" de "válido completo"

---

## 🔴 CRÍTICA #4: Xi completo vs. Xi selecionado confundido

### Arquivo: `B4_Stage4_ActiveLearning.m` (linhas 785-806)

**Problema:**
```matlab
% CÓDIGO ATUAL:
nXi = size(D.Xi, 2);  % Xi COMPLETO (21465 colunas)

% Mas depois:
xiNew = xNew(1:nXi);  % Trata como se fossem 21465 primeiras colunas
rvNew = xNew(nXi+1:end);  % RVs nas posições 21465:21483

% Mas xiNew deveria ser APENAS os Xi selecionados (72) do modelo!
```

**Análise:**
- `D.Xi` = Xi completo (21465) de Stage 0
- `M.vars_train` = apenas Xi selecionados (72) + 18 RVs (90 total)
- `local_candidates()` gera candidatos com 21483 dimensões (correto)
- Mas depois `xiNew` é extraído como primeiras 21465 linhas (INCORRETO)
- Campo espacial recebe **Xi completo** (correto para Python/RS2)
- **Mas há risco de confusão se `nXi` for usado fora de contexto**

**Solução Necessária:**
```matlab
% CORRETO:
nXi_total = size(D.Xi, 2);  % 21465 (para clareza)
nXi_train = nnz(startsWith(M.vars_train, "xi_"));  % 72 (do modelo)

xiNew = xNew(1:nXi_total);  % Xi COMPLETO para campo espacial
rvNew = xNew(nXi_total+1:end);  % 18 RVs
```

**Impacto:** ⚠️ **MÉDIO** (código atual funciona, mas é confuso)
- Documentação inadequada causa erros em manutenção futura
- Recomendação: renomear variáveis para clareza

---

## 🔴 CRÍTICA #5: Auditoria Stage 4 não registra método de Pf

### Arquivo: `B4_Stage4_ActiveLearning.m` (linhas 1176-1186)

**Problema:**
```matlab
% CÓDIGO ATUAL:
audit = [audit; local_audit_row_Pf_stability( ...
    iter, simID, baseID, predicted, observed, ...
    Pf_current, "OK", message, iterationStop, attemptDir, ...
    nfail, nValid)]; %#ok<AGROW>
```

**Análise:**
- Audit registra: `Pf_estimate`, `NFailures_MCS`
- **NÃO registra**: método (`'mcs'` vs. `'ss'`)
- Não há rastreabilidade de qual método foi usado em cada iteração
- Impossível auditar convergência se mistura estimativas MCS/SS

**Solução Necessária:**
✅ Arquivo corrigido: `B4_Stage4_ActiveLearning_FIXED.m`

**Impacto:** ⚠️ **MÉDIO** (auditoria incompleta)
- Recomendação: adicionar coluna `Pf_Method` (string)

---

## 🔴 CRÍTICA #6: Config não valida `AL_USE_Pf_CONVERGENCE` vs `AL_USE_Pf_STABILITY`

### Arquivo: `B4_DefaultConfig.m` (linhas 127-131)

**Problema:**
```matlab
% EXISTE EM STAGE 3:
cfg.AL_USE_Pf_CONVERGENCE = true;  % Estima Pf inicial

% EXISTE EM STAGE 4:
cfg.AL_USE_Pf_STABILITY = true;    % Usa histórico de Pf para parada

% FALTA: validação de coerência!
```

**Análise:**
- `AL_USE_Pf_CONVERGENCE` → Stage 3 gera `Pf_population` (estrutura para parada futura)
- `AL_USE_Pf_STABILITY` → Stage 4 tenta usar histórico de Pf para parada
- **Se ambas forem FALSE** → Stage 3 não cria população, Stage 4 para apenas por max_iters
- **Se estiverem inconsistentes** → avisos genéricos, sem erro claro

**Solução Necessária:**
✅ Arquivo corrigido: `B4_DefaultConfig_FIXED.m`

**Impacto:** ⚠️ **MÉDIO** (validação mais rigorosa)
- Recomendação: adicionar `local_validate_pf_flags()` em `B4_Run_Reliability_Metamodel.m`

---

## 📊 Tabela de Impacto

| # | Arquivo | Linha(s) | Severidade | Tipo | Sugestão |
|---|---------|----------|-----------|------|----------|
| 1 | B4_Stage3_TrainPCK.m | 559-568 | 🔴 CRÍTICO | Lógica | Inverter sinais de sigma |
| 2 | B4_Stage4_ActiveLearning.m | 1288-1632 | 🔴 CRÍTICO | Incompleto | Completar função MCS/SS |
| 3 | B4_Suport_build_spatial_fields_from_xi.m | 89-108 | 🔴 CRÍTICO | Não documentado | Alertar auditoria |
| 4 | B4_Stage4_ActiveLearning.m | 785-806 | 🟡 MÉDIO | Confuso | Renomear variáveis |
| 5 | B4_Stage4_ActiveLearning.m | 1176-1186 | 🟡 MÉDIO | Auditoria | Adicionar coluna método |
| 6 | B4_DefaultConfig.m | 127-131 | 🟡 MÉDIO | Validação | Validar coerência flags |

---

## ✅ Arquivos Corrigidos Disponíveis

1. **B4_Stage3_TrainPCK_FIXED.m** → Correção #1
2. **B4_Stage4_ActiveLearning_FIXED.m** → Correções #2, #4, #5
3. **B4_Suport_build_spatial_fields_from_xi_FIXED.m** → Correção #3
4. **B4_DefaultConfig_FIXED.m** → Correção #6

---

## 🔧 Instruções de Implementação

### Passo 1: Backup
```bash
cp B4_Stage3_TrainPCK.m B4_Stage3_TrainPCK_BACKUP_2026-10-07.m
cp B4_Stage4_ActiveLearning.m B4_Stage4_ActiveLearning_BACKUP_2026-10-07.m
cp B4_Suport_build_spatial_fields_from_xi.m B4_Suport_build_spatial_fields_from_xi_BACKUP_2026-10-07.m
cp B4_DefaultConfig.m B4_DefaultConfig_BACKUP_2026-10-07.m
```

### Passo 2: Integração
```matlab
% Em B4_Run_Reliability_Metamodel.m (no try-catch), adicione:
fprintf('[B4] AVISO: Usando versão corrigida v6.1 com 6 correções críticas.\n');
fprintf('[B4] Consulte INCONSISTENCIAS_CRITICAS.md para detalhes.\n');
```

### Passo 3: Testes Recomendados
- [ ] Stage 3: Verificar que `Pf_low < Pf_estimate < Pf_high` (sempre)
- [ ] Stage 4: Confirmar que audit registra método de Pf (MCS vs SS)
- [ ] Stage 4: Testar com `spatial_allow_missing_materials = true` e verificar log
- [ ] Config: Validar ambas flags Pf ativadas ou desativadas juntas

---

## 📝 Notas Futuras

- **v6.2**: Validar heteroscedasticidade em Pf_population (Stage 3)
- **v6.3**: Implementar suavidade inter-material (Stage 4 validação)
- **v6.4**: Cache de populações LHS (otimização memória)

**Última atualização**: 2026-10-07 13:25 UTC
