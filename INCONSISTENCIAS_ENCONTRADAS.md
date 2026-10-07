# Análise de Inconsistências no Pipeline B4

## Resumo Executivo

Foram identificadas **8 inconsistências críticas** que podem causar:
- Falhas silenciosas na convergência de Pf
- Materialização de materiais vazios rejeitados
- Resultados não reproduzíveis
- Corrupção de dados em snapshots

---

## 1. ⚠️ CRÍTICA: Sinal Invertido na Faixa de Pf (B4_Stage3_TrainPCK.m)

### Localização
Linhas 399-403 (Stage 3):
```matlab
Pf_low = mean(g_pop + kfactor .* Ypop_std_est <= 0);
Pf_high = mean(g_pop - kfactor .* Ypop_std_est <= 0);
```

### Problema
Os comentários dizem:
```
% - Pf_low  = mean(g + k*sigma <= 0) = pessimista (mais falha)
% - Pf_high = mean(g - k*sigma <= 0) = otimista (menos falha)
```

Mas **a lógica está invertida**:
- `g + k*sigma <= 0`: Faz **menos** amostras falhar (estimativa **otimista**)
- `g - k*sigma <= 0`: Faz **mais** amostras falhar (estimativa **pessimista**)

### Impacto
- ✗ Pf_low retorna otimista (deveria ser pessimista)
- ✗ Pf_high retorna pessimista (deveria ser otimista)
- ✗ Critério de parada Stage 4 usa faixa invertida
- ✗ Histórico de Pf pode aparecer "divergente" quando na verdade está correto

### Correção
```matlab
% CORRETO:
Pf_low = mean(g_pop - kfactor .* Ypop_std_est <= 0);  % pessimista
Pf_high = mean(g_pop + kfactor .* Ypop_std_est <= 0); % otimista
```

---

## 2. ⚠️ CRÍTICA: Materiais Vazios Não Bloqueados (B4_Suport_build_spatial_fields_from_xi.m)

### Localização
Linhas 160-185:
```matlab
if isEmptyField
    if ~allowMissing
        error(...)
    end
    materialFields{matID} = local_empty_field(requiredColumns);
    continue;
end
```

### Problema
1. **Material vazio é aceito**, mesmo com `spatial_allow_missing_materials=false`
2. **Retorna tabela vazia** → `local_empty_field()` cria 5 colunas com 0 linhas
3. **Ao concatenar com vertcat(materialFields{:})**, materiais vazios contribuem 0 pontos
4. **Faixa de Pf fica pequena** porque menos pontos = menos representatividade

### Impacto na Convergência
```
Iteração 1: Campo com 5 materiais       → Pf_estimate = 0.150, Pf_width = 0.30
Iteração 2: Material 3 começa ficar vazio → Pf_estimate = 0.160, Pf_width = 0.20
Iteração 3: Material 3 completamente vazio → Pf_estimate = 0.165, Pf_width = 0.15
                                           ↑ Faixa diminui = aparenta convergência falsa
```

### Correção
Necessário:
1. **Rastrear qual material ficou vazio**:
   ```matlab
   if ~any(materialPointCount > 0)
       error('Nenhum material com pontos validos. Materiais vazios: %s', ...)
   end
   ```

2. **Registrar no audit**: Coluna `EmptyMaterialsDetected`
3. **Validar material 3**: Se config de redução estiver ativa, pré-validar

---

## 3. ⚠️ MÉDIA: Faixa de Pf Nunca Converge (B4_Stage4_ActiveLearning.m, linha 658)

### Localização
```matlab
Pf_width_rel = (Pf_high - Pf_low) / max(Pf_estimate, cfg.AL_Pf_floor);
```

### Problema
1. **AL_Pf_floor é piso de normalização, não limite de convergência**
   - Default: 0.001 (0.1%)
   - Se Pf_estimate < 0.1%, denominador = 0.001 (fixo)
   - Pf_width_rel pode ser MUITO grande mesmo com faixa pequena

2. **Exemplo com Pf raro**:
   ```
   Pf_low = 0.001, Pf_high = 0.003
   Pf_width_rel = (0.003 - 0.001) / max(0.002, 0.001) = 0.002 / 0.002 = 1.0 (100%)
   
   Vs esperado com critério sensato:
   Pf_width_rel = (0.003 - 0.001) / 0.002 = 1.0 (ainda 100%, mas "correto")
   ```

3. **Critério de parada**: Rel_change < 5% pode NUNCA ser atingido se faixa é larga

### Impacto
- ✗ Parada por convergência Pf pode não funcionar para casos raros
- ✗ Stage 4 executa todas as 20 iterações mesmo com Pf estável

### Correção
```matlab
% Usar faixa RELATIVA da estimativa, não piso absoluto
if Pf_estimate > 0
    Pf_width_rel = (Pf_high - Pf_low) / Pf_estimate;  % faixa / estimativa
else
    Pf_width_rel = (Pf_high - Pf_low) / cfg.AL_Pf_floor;  % fallback
end
```

---

## 4. ⚠️ MÉDIA: Semente RNG Não Controlada em Snapshots (B4_Stage4_ActiveLearning.m)

### Localização
```matlab
% Linha 183: RNG é setado ANTES de cada iteração
rng(double(cfg.seed), 'twister');

% Mas dentro do loop (linha 600+):
[Pf_current, nfail_mcs, method_used, status_txt] = ...
    local_estimate_pf_hybrid_mcs_ss(M, cfg);
```

Problema:
- **MCS gera 50k amostras com RNG determinístico**
- **Seed é SEMPRE cfg.seed (ex: 100)**
- **Iteração 1 e Iteração 10 usam MESMA RNG** (se RNG não foi quebrada)

### Impacto
- ✗ Reprodução de erro impossível entre execuções
- ✗ Se Pf_history fica pequena, pode parecer convergência quando é repetição

### Correção
```matlab
% Incrementar seed por iteração
current_seed = cfg.seed + iter;
rng(double(current_seed), 'twister');
```

---

## 5. ⚠️ MÉDIA: Histórico de Pf Não Limpado Entre Execuções

### Localização
Linha 183 (B4_Stage4_ActiveLearning.m):
```matlab
Pf_history = [];  % inicializado
method_history = {};

for iter = 1:cfg.AL_MAX_ITERS
    % ... código ...
    Pf_history = [Pf_history, Pf_current];
```

Problema:
- Se Stage 4 é chamado DUAS VEZES na mesma sessão MATLAB
- `Pf_history` não é reinicializado
- Histórico da Execução 1 "contamina" decisões da Execução 2

### Impacto
- ✗ Se executar pipeline 2x na mesma sessão: Pf_history misturado
- ✗ Critério de parada pode parar cedo na Execução 2

### Correção
```matlab
% Adicionar ao início de B4_Stage4_ActiveLearning:
Pf_history = [];
method_history = {};
```

---

## 6. ⚠️ MÉDIA: Limiar de Comparação Sem Validação (B4_Stage4_ActiveLearning.m, linha 648)

### Localização
```matlab
rel_change = abs(window_pf(i) - window_pf(i-1)) / ...
    max(window_pf(i-1), cfg.AL_Pf_floor);
```

Problema:
- `window_pf(i-1)` pode ser < `cfg.AL_Pf_floor` (ex: 0.0001 vs 0.001)
- **Denominador é sempre `cfg.AL_Pf_floor`** neste caso
- Rel_change fica grande mesmo com mudanças pequenas

### Exemplo
```
window_pf(1) = 0.0005, window_pf(2) = 0.0006
rel_change = |0.0006 - 0.0005| / max(0.0005, 0.001)
          = 0.0001 / 0.001 = 0.1 (10%)
          
Esperado: (0.0006 - 0.0005) / 0.0005 = 0.2 (20%)
Mas isso inverteria o problema...
```

### Correção
```matlab
% Usar média das duas leituras como denominador (mais robusto)
denominator = (window_pf(i) + window_pf(i-1)) / 2;
rel_change = abs(window_pf(i) - window_pf(i-1)) / ...
    max(denominator, cfg.AL_Pf_floor);
```

---

## 7. ⚠️ BAIXA: Variável `nfail` Não Inicializada Sempre (B4_Stage4_ActiveLearning.m, linha 621)

### Localização
```matlab
nfail = 0;  % inicializado
method_used = '';

if cfg.AL_USE_Pf_STABILITY
    [Pf_current, nfail_mcs, method_used, status_txt] = ...
        local_estimate_pf_hybrid_mcs_ss(M, cfg);
    nfail = nfail_mcs;  % ✗ Só atribuído se AL_USE_Pf_STABILITY = true
```

Problema:
- Se `cfg.AL_USE_Pf_STABILITY = false`
- `nfail` permanece 0
- Audit registra "0 falhas MCS" mas MCS não foi executado

### Impacto
- ✗ Auditoria enganosa (aparenta MCS executado)
- ✗ Difícil diagnosticar que Pf não foi estimado

### Correção
```matlab
nfail = NaN;  % indicar "não calculado"

if cfg.AL_USE_Pf_STABILITY
    [Pf_current, nfail_mcs, method_used, status_txt] = ...
        local_estimate_pf_hybrid_mcs_ss(M, cfg);
    nfail = nfail_mcs;
else
    nfail = NaN;  % explícito
end
```

---

## 8. ⚠️ BAIXA: Arquivo Incompleto Python (run_al_batch.py)

### Localização
Fim do arquivo (linha ~300):
```python
def apply_liner_random_values(model, liner_row):
    liners = model.getAllLinerProperties()
    ...
    for liner_number in range(1, 3):
        ...
        tensile_strength = liner  # ✗ INCOMPLETO
```

### Problema
- Função cortada no final
- Falta parâmetro `liner_row[f"ft_Liner{liner_number}"]`
- Importação de funções não completada

### Impacto
- ✗ Python não consegue executar
- ✗ Stage 4 falha em todas as tentativas

### Correção
Completar arquivo:
```python
def apply_liner_random_values(model, liner_row):
    liners = model.getAllLinerProperties()
    if len(liners) < 2:
        raise RuntimeError(...)
    
    for liner_number in range(1, 3):
        thickness = liner_row[f"Thickness_Liner{liner_number}"]
        youngs_modulus = liner_row[f"E_Liner{liner_number}"]
        compressive_strength = liner_row[f"fc_Liner{liner_number}"]
        tensile_strength = liner_row[f"ft_Liner{liner_number}"]
        
        liner_prop = liners[liner_number - 1]
        apply_liner_rc_properties(
            liner_prop, thickness, youngs_modulus,
            compressive_strength, tensile_strength
        )
```

---

## Resumo de Prioridades

| ID | Severidade | Arquivo | Linhas | Impacto |
|:--:|:----------:|---------|--------|---------|
| 1  | 🔴 CRÍTICA | B4_Stage3_TrainPCK.m | 399-403 | Faixa Pf invertida |
| 2  | 🔴 CRÍTICA | B4_Suport_build_spatial_fields_from_xi.m | 160-185 | Materiais vazios aceitos |
| 3  | 🟠 MÉDIA | B4_Stage4_ActiveLearning.m | 658 | Pf nunca converge |
| 4  | 🟠 MÉDIA | B4_Stage4_ActiveLearning.m | 183 | RNG não diversificada |
| 5  | 🟠 MÉDIA | B4_Stage4_ActiveLearning.m | 183 | Histórico não limpado |
| 6  | 🟠 MÉDIA | B4_Stage4_ActiveLearning.m | 648 | Limiar mal calculado |
| 7  | 🟡 BAIXA | B4_Stage4_ActiveLearning.m | 621 | nfail não inicializado |
| 8  | 🔴 CRÍTICA | run_al_batch.py | ~300 | Arquivo incompleto |

---

## Recomendações

✅ **Imediato** (hoje):
1. Corrigir sinais Pf_low/Pf_high (#1)
2. Completar run_al_batch.py (#8)
3. Validar materiais vazios (#2)

✅ **Curto prazo** (esta semana):
4. Diversificar RNG por iteração (#4)
5. Corrigir faixa relativa Pf (#3)

✅ **Médio prazo** (próxima iteração):
6. Revisão e teste de convergência Pf
7. Documentação de contrato de dados
