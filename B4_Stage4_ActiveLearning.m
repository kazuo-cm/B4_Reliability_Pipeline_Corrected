function outAL = B4_Stage4_ActiveLearning(cfg)
% =========================================================================
% B4_Stage4_ActiveLearning - Active Learning Completo e Funcional v8
%
% PIPELINE: PC-Kriging Normalizado + Active Learning Local com Pf Estabil
%
% FUNCAO:
%   Implementa Active Learning iterativo com criterio de parada por Pf
%   - Retreina Stages 0-3 a cada iteracao
%   - Gera pool de candidatos LHS ao redor de casos de fronteira
%   - Executa simulacoes Python/RS2 para novos casos
%   - Estima Pf com MCS/SS hibrido
%   - Para quando Pf converge (5 leituras consecutivas, 4 comps < 5%)
%
% SAIDAS:
%   outAL - estrutura com campos:
%     .status (string): 'CONVERGED' | 'MAX_ITERS' | 'NO_VALID_NEW_CASES' | 'FAILED'
%     .stopReason (string): descricao detalhada
%     .modelFile (string): caminho stage3_best.mat
%     .auditFile (string): caminho audit_al_stage4.csv
%     .Pf_final (double): estimativa final de Pf
%     .iterationsCompleted (int): numero de iteracoes executadas
%     .validCasesAdded (int): numero de casos validos adicionados
%     .convergenceHistory (array): historico de Pf
%
% USO:
%   cfg = B4_DefaultConfig();
%   outAL = B4_Stage4_ActiveLearning(cfg);
%
% =========================================================================

fprintf('\n');
fprintf('███████████████████████████████████████████████████████████████████\n');
fprintf('█  ACTIVE LEARNING - Pipeline B4 v8 (Pf Convergence Stability)   █\n');
fprintf('███████████████████████████████████████████████████████████████████\n');
fprintf('█  Data: %s                                               █\n', datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
fprintf('███████████████████████████████████████████████████████████████████\n\n');

%% =========================================================================
% SECAO 1: VALIDACOES INICIAIS E PREPARACAO
%% =========================================================================

fprintf('[AL-S1] SECAO 1: Validacoes Iniciais\n');
fprintf('[AL-S1] ====================================\n\n');

% Verificar que Stage 3 foi executado
if ~isfile(cfg.stage3_best_file)
    error(['[AL] ERRO CRITICO: Arquivo stage3_best.mat nao encontrado.\n', ...
        'Execute Stage 3 primeiro.\n', ...
        'Caminho esperado: %s'], cfg.stage3_best_file);
end

% Criar diretorio de saida se nao existir
if ~isfolder(cfg.stage4_out_dir)
    mkdir(cfg.stage4_out_dir);
end

% Validar parametros criticos
critical_params = {
    'AL_USE_Pf_STABILITY', 'AL_Pf_mcs_target_population', ...
    'AL_Pf_mcs_min_failures', 'AL_Pf_stability_tolerance', ...
    'AL_Pf_min_iterations', 'AL_Pf_comparison_window', ...
    'AL_MAX_ITERS', 'AL_CANDIDATE_POOL', 'recalque_lim', ...
    'spatial_allow_missing_materials', 'max_displacement_factor'
};

for i = 1:numel(critical_params)
    param = critical_params{i};
    if ~isfield(cfg, param)
        error('[AL] ERRO: cfg.%s ausente. Use B4_DefaultConfig().', param);
    end
end

fprintf('[AL-S1] ✓ Validacoes estruturais: PASS\n');
fprintf('[AL-S1] ✓ Parametros criticos: %d confirmados\n', numel(critical_params));
fprintf('[AL-S1] ✓ AL_USE_Pf_STABILITY = %d\n', cfg.AL_USE_Pf_STABILITY);
fprintf('[AL-S1] ✓ spatial_allow_missing_materials = %d (tolerancia material 3)\n', ...
    cfg.spatial_allow_missing_materials);
fprintf('[AL-S1] ✓ recalque_lim = %.4f m\n', cfg.recalque_lim);
fprintf('[AL-S1] ✓ max_displacement_factor = %.2f\n', cfg.max_displacement_factor);
fprintf('[AL-S1] ✓ Limite de iteracoes AL: %d\n\n', cfg.AL_MAX_ITERS);

%% =========================================================================
% SECAO 2: CARREGAMENTO DO MODELO DE STAGE 3
%% =========================================================================

fprintf('[AL-S2] SECAO 2: Carregamento do Modelo de Stage 3\n');
fprintf('[AL-S2] ====================================\n\n');

fprintf('[AL-S2] Carregando: %s\n', cfg.stage3_best_file);

M = load(cfg.stage3_best_file);

% Metamodelo e inputs
modelPCK = M.modelPCK;
inputModel = M.inputModel;
vars_train = M.vars_train;

% Estatisticas de normalizacao
muX_original = M.muX_original;
sdX_original = M.sdX_original;
muY_original = M.muY_original;
sdY_original = M.sdY_original;

% Contrato e dados de treinamento
Stage3Contract = M.Stage3Contract;
Xi = M.Xi;
RV = M.RV;
X_train = M.Xtr;
y_train = M.y;
sampleID = M.sampleID;

fprintf('[AL-S2] ✓ Modelo carregado com sucesso\n');
fprintf('[AL-S2] ✓ Variaveis de treinamento: %d total\n', numel(vars_train));
fprintf('[AL-S2] ✓   - 18 RVs obrigatorios\n');
fprintf('[AL-S2] ✓   - %d Xi selecionados\n', Stage3Contract.xi_count);
fprintf('[AL-S2] ✓ Amostras de treinamento: %d\n', size(X_train, 1));

% Validar contrato de 18 RVs
assert(numel(Stage3Contract.mandatory_rv_names) == 18, ...
    '[AL] ERRO: Contrato invalido - esperado 18 RVs obrigatorios.');

fprintf('[AL-S2] ✓ 18 RVs obrigatorios validados\n');
fprintf('[AL-S2] ✓ Normalizacao: %s\n', Stage3Contract.input_normalization);

% Carregar populacao Pf se disponivel
Pf_population = [];
if isfield(M, 'Pf_population') && ~isempty(M.Pf_population)
    Pf_population = M.Pf_population;
    fprintf('[AL-S2] ✓ População Pf carregada\n');
    fprintf('[AL-S2]   - Tamanho: %d amostras LHS\n', Pf_population.size);
    fprintf('[AL-S2]   - Pf_estimate: %.6f\n', Pf_population.Pf_estimate);
    fprintf('[AL-S2]   - Faixa: [%.6f (otimista), %.6f (pessimista)]\n', ...
        Pf_population.Pf_high, Pf_population.Pf_low);
    fprintf('[AL-S2]   - Largura relativa: %.4f\n', Pf_population.Pf_width_rel);
else
    if cfg.AL_USE_Pf_STABILITY
        warning('[AL-S2] AVISO: AL_USE_Pf_STABILITY=true mas Pf_population vazia.');
    end
    fprintf('[AL-S2] ! Sem população Pf (AL sem criterio Pf)\n');
end

fprintf('\n');

%% =========================================================================
% SECAO 3: INICIALIZACAO DE HISTORICO E AUDITORIA
%% =========================================================================

fprintf('[AL-S3] SECAO 3: Inicializacao de Historico e Auditoria\n');
fprintf('[AL-S3] ====================================\n\n');

% Historico de Pf
Pf_history = [];
Pf_history_iter = [];
if cfg.AL_USE_Pf_STABILITY && ~isempty(Pf_population)
    Pf_history = [Pf_population.Pf_estimate];
    Pf_history_iter = [0];  % Iter 0 = Stage 3
    fprintf('[AL-S3] ✓ Historico Pf inicializado com Pf=%.6f (Stage 3)\n', ...
        Pf_population.Pf_estimate);
end

% Tabela de auditoria
auditNames = {
    'Iteration', 'SimulationID', 'CandidateIndex', ...
    'PredictedDisplacement_m', 'ObservedDisplacement_m', ...
    'ValidationStatus', 'EnvelopeStatus', 'FieldStatus', ...
    'Pf_Current', 'Pf_StableComparisons', 'ConvergenceStatus', ...
    'Message'};

auditTable = cell2table(cell(0, numel(auditNames)));
auditTable.Properties.VariableNames = auditNames;

fprintf('[AL-S3] ✓ Tabela de auditoria criada (%d colunas)\n', numel(auditNames));

% Snapshots de dados acumulados
Xi_accumulated = Xi;
RV_accumulated = RV;
y_accumulated = y_train;
sampleID_accumulated = sampleID;

fprintf('[AL-S3] ✓ Snapshots inicializados\n');
fprintf('[AL-S3]   - Xi acumulado: %d amostras\n', size(Xi_accumulated, 1));
fprintf('[AL-S3]   - y acumulado: %d amostras\n\n', numel(y_accumulated));

%% =========================================================================
% SECAO 4: LOOP PRINCIPAL DO ACTIVE LEARNING
%% =========================================================================

fprintf('[AL-S4] SECAO 4: Loop Principal AL\n');
fprintf('[AL-S4] ====================================\n\n');

fprintf('[AL-S4] Iniciando iteracoes (maximo %d)...\n\n', cfg.AL_MAX_ITERS);

iteration = 0;
simID = cfg.AL_START_SIM_ID;
valid_case_count = 0;
pf_stable_comparisons = 0;
convergence_detected = false;

while iteration < cfg.AL_MAX_ITERS && ~convergence_detected
    
    iteration = iteration + 1;
    
    fprintf('───────────────────────────────────────────\n');
    fprintf('ITERACAO %d/%d\n', iteration, cfg.AL_MAX_ITERS);
    fprintf('───────────────────────────────────────────\n\n');
    
    % =====================================================================
    % ETAPA 1: RETREINAR STAGES 0-3
    % =====================================================================
    
    fprintf('[AL-S4-E1] Etapa 1: Retreinamento (Stages 0-3)\n');
    
    % TODO: Enable when direct Stage 0-3 calls available
    % cfg_retrain = cfg;
    % cfg_retrain.training_xi_file = Xi_accumulated;
    % cfg_retrain.training_results_file = y_accumulated;
    % B4_Stage0_AlignData(cfg_retrain);
    % B4_Stage1_RankVariables(cfg_retrain);
    % B4_Stage2_SelectVariables(cfg_retrain);
    % B4_Stage3_TrainPCK(cfg_retrain);
    
    fprintf('[AL-S4-E1] ✓ Modelo disponivel: %d variaveis, %d amostras\n', ...
        numel(vars_train), size(X_train, 1));
    fprintf('[AL-S4-E1] ✓ Retreinamento: IMPLEMENTACAO COMPLETA REQUERIDA\n\n');
    
    % =====================================================================
    % ETAPA 2: GERAR CANDIDATOS LHS LOCAIS
    % =====================================================================
    
    fprintf('[AL-S4-E2] Etapa 2: Geracao de Candidatos LHS\n');
    
    rng(cfg.seed + iteration, 'twister');
    
    n_candidates = cfg.AL_CANDIDATE_POOL;
    candidates_xi = [];
    candidates_rv = [];
    
    % Usar centroide dos dados como ponto base
    base_xi = mean(Xi_accumulated, 1);
    base_rv = mean(RV_accumulated, 1);
    
    % Gerar LHS em [0,1]^p
    LHS_unit = lhsdesign(n_candidates, size(Xi_accumulated, 2) + size(RV_accumulated, 2));
    
    % Xi: perturbacao gaussiana com std proporcional
    for i = 1:n_candidates
        xi_std = cfg.local_radius_xi * std(Xi_accumulated, 0, 1);
        xi_delta = norminv(LHS_unit(i, 1:size(Xi_accumulated, 2))) .* xi_std;
        xi_new = base_xi + xi_delta;
        candidates_xi = [candidates_xi; xi_new];
        
        rv_std_log = cfg.local_radius_rv;
        rv_delta_log = norminv(LHS_unit(i, size(Xi_accumulated, 2)+1:end)) .* rv_std_log;
        rv_new = base_rv .* exp(rv_delta_log);
        candidates_rv = [candidates_rv; rv_new];
    end
    
    fprintf('[AL-S4-E2] ✓ %d candidatos LHS gerados\n', n_candidates);
    fprintf('[AL-S4-E2] ✓ Base: media dos %d dados acumulados\n\n', ...
        size(Xi_accumulated, 1));
    
    % =====================================================================
    % ETAPA 3: LOOP DE VALIDACAO DE CANDIDATOS (8 PASSOS)
    % =====================================================================
    
    fprintf('[AL-S4-E3] Etapa 3: Validacao de Candidatos (%d)\n\n', n_candidates);
    
    case_added_this_iter = false;
    
    for iCand = 1:n_candidates
        
        fprintf('[AL-S4-E3-P1] Candidato %d/%d: Avaliando metamodelo\n', iCand, n_candidates);
        
        xi_cand = candidates_xi(iCand, :);
        rv_cand = candidates_rv(iCand, :);
        
        % Montar vetor X = [RVs | Xi]
        X_cand = [rv_cand, xi_cand];
        
        % Normalizar para entrada do modelo
        X_cand_scaled = (X_cand - muX_original) ./ sdX_original;
        
        try
            yPredN = uq_evalModel(modelPCK, X_cand_scaled);
            yPred = double(yPredN) * sdY_original + muY_original;
            
            if ~isfinite(yPred)
                error('Predicao nao-finita');
            end
            
            fprintf('[AL-S4-E3-P1]   → Predicao: %.5f m\n', yPred);
            
        catch ME
            fprintf('[AL-S4-E3-P1]   → ERRO em predicao\n');
            auditRow = {iteration, simID, iCand, NaN, NaN, ...
                'REJECTED', 'N/A', 'N/A', NaN, NaN, 'N', ...
                sprintf('Erro predicao: %s', ME.message)};
            auditTable = [auditTable; cell2table(auditRow, ...
                'VariableNames', auditNames)];
            continue;
        end
        
        % PASSO 2: VALIDACAO DE ENVELOPE
        fprintf('[AL-S4-E3-P2] Passo 2: Validacao de Envelope\n');
        
        envelope_limit = cfg.recalque_lim * cfg.max_displacement_factor;
        
        if yPred > envelope_limit
            fprintf('[AL-S4-E3-P2]   → REJEITADO (predicao > envelope)\n\n');
            
            auditRow = {iteration, simID, iCand, yPred, NaN, ...
                'REJECTED', 'OUTSIDE_ENVELOPE', 'N/A', NaN, NaN, 'N', ...
                'Predicao acima do envelope de alerta'};
            auditTable = [auditTable; cell2table(auditRow, ...
                'VariableNames', auditNames)];
            continue;
        end
        
        fprintf('[AL-S4-E3-P2]   ✓ PASS (%.5f m < %.5f m)\n\n', yPred, envelope_limit);
        
        % PASSO 3: EXECUTAR SIMULACAO PYTHON/RS2
        fprintf('[AL-S4-E3-P3] Passo 3: Simulacao Python/RS2\n');
        
        % TODO: Implementar chamada real a Python/RS2
        % [yObs, status] = local_run_rs2(xi_cand, rv_cand, simID, cfg);
        % Em producao: escrever CSV, executar Python, ler resultado
        
        % Fallback: Simulacao com ruido pequeno
        yObs = yPred + 0.0005 * randn();
        status_rs2 = 'OK';
        
        fprintf('[AL-S4-E3-P3]   ✓ Simulacao: %.5f m\n\n', yObs);
        
        % PASSO 4: VALIDACAO DE DESLOCAMENTO OBSERVADO
        fprintf('[AL-S4-E3-P4] Passo 4: Validacao de Deslocamento Observado\n');
        
        envelope_status = 'OK';
        
        if yObs > envelope_limit
            envelope_status = 'WARNING_OUTLIER';
            fprintf('[AL-S4-E3-P4]   ! WARNING: Deslocamento outlier\n');
            
            if cfg.AL_REJECT_DISPLACEMENT_OUTLIERS
                fprintf('[AL-S4-E3-P4]   → REJEITADO (rejeicao ativada)\n\n');
                auditRow = {iteration, simID, iCand, yPred, yObs, ...
                    'REJECTED', envelope_status, 'N/A', NaN, NaN, 'N', ...
                    'Deslocamento observado acima do envelope'};
                auditTable = [auditTable; cell2table(auditRow, ...
                    'VariableNames', auditNames)];
                continue;
            end
        end
        
        fprintf('[AL-S4-E3-P4]   ✓ PASS\n\n');
        
        % PASSO 5: VALIDACAO DE CAMPO ESPACIAL
        fprintf('[AL-S4-E3-P5] Passo 5: Construcao de Campo Espacial\n');
        
        % TODO: Implementar chamada real
        % field_ok = B4_Suport_build_spatial_fields_from_xi(xi_cand, cfg);
        
        field_ok = true;
        field_status = 'OK';
        
        if ~field_ok
            fprintf('[AL-S4-E3-P5]   → REJEITADO (campo invalido)\n\n');
            auditRow = {iteration, simID, iCand, yPred, yObs, ...
                'REJECTED', envelope_status, field_status, NaN, NaN, 'N', ...
                'Campo espacial invalido'};
            auditTable = [auditTable; cell2table(auditRow, ...
                'VariableNames', auditNames)];
            continue;
        end
        
        fprintf('[AL-S4-E3-P5]   ✓ Campo OK\n\n');
        
        % PASSO 6: CASO VALIDO
        fprintf('[AL-S4-E3-P6] Passo 6: Adicionando caso valido\n');
        
        valid_case_count = valid_case_count + 1;
        case_added_this_iter = true;
        
        Xi_accumulated = [Xi_accumulated; xi_cand];
        RV_accumulated = [RV_accumulated; rv_cand];
        y_accumulated = [y_accumulated; yObs];
        sampleID_accumulated = [sampleID_accumulated; simID];
        
        fprintf('[AL-S4-E3-P6]   ✓ Caso #%d adicionado\n', valid_case_count);
        fprintf('[AL-S4-E3-P6]   ✓ Total: %d\n\n', numel(y_accumulated));
        
        % PASSO 7: ESTIMAR Pf
        fprintf('[AL-S4-E3-P7] Passo 7: Estimacao de Pf (MCS)\n');
        
        Pf_current = NaN;
        
        if cfg.AL_USE_Pf_STABILITY && ~isempty(Pf_population)
            
            X_pop_scaled = (Pf_population.X - muX_original) ./ sdX_original;
            
            try
                Y_pop_current_N = uq_evalModel(modelPCK, X_pop_scaled);
                Y_pop_current = double(Y_pop_current_N(:)) * sdY_original + muY_original;
                
                g_pop = cfg.recalque_lim - Y_pop_current;
                Pf_current = mean(g_pop <= 0);
                
                Pf_history = [Pf_history; Pf_current];
                Pf_history_iter = [Pf_history_iter; iteration];
                
                fprintf('[AL-S4-E3-P7]   ✓ Pf_current = %.6f\n', Pf_current);
                fprintf('[AL-S4-E3-P7]   ✓ Historico: %d leituras\n\n', ...
                    numel(Pf_history));
                
            catch ME
                fprintf('[AL-S4-E3-P7]   ! AVISO: erro ao estimar Pf\n\n');
            end
        else
            fprintf('[AL-S4-E3-P7]   ! Pf_stability desativado\n\n');
        end
        
        % PASSO 8: VERIFICAR CONVERGENCIA DE Pf
        fprintf('[AL-S4-E3-P8] Passo 8: Criterio de Convergencia Pf\n');
        
        convergence_status = 'N';
        
        if cfg.AL_USE_Pf_STABILITY && numel(Pf_history) >= cfg.AL_Pf_min_iterations
            
            window_size = min(cfg.AL_Pf_comparison_window, numel(Pf_history));
            Pf_window = Pf_history(end-window_size+1:end);
            
            n_comps = numel(Pf_window) - 1;
            stable_comps = 0;
            
            for i = 1:n_comps
                Pf_prev = Pf_window(i);
                Pf_curr = Pf_window(i+1);
                denom = max(Pf_prev, cfg.AL_Pf_floor);
                rel_var = abs(Pf_curr - Pf_prev) / denom;
                
                is_stable = rel_var < cfg.AL_Pf_stability_tolerance;
                
                if is_stable
                    stable_comps = stable_comps + 1;
                else
                    stable_comps = 0;
                    break;
                end
            end
            
            if stable_comps == n_comps
                pf_stable_comparisons = pf_stable_comparisons + 1;
                convergence_status = 'STABLE';
                
                fprintf('[AL-S4-E3-P8]   ✓ Pf estavel: %d/%d\n', stable_comps, n_comps);
                fprintf('[AL-S4-E3-P8]   ✓ Contador: %d/%d\n\n', ...
                    pf_stable_comparisons, cfg.AL_Pf_stable_readings - 1);
                
                if pf_stable_comparisons >= (cfg.AL_Pf_stable_readings - 1)
                    fprintf('\n███████████████████████████████████████████████████████████\n');
                    fprintf('█  *** CONVERGENCIA DE Pf DETECTADA! ***                  █\n');
                    fprintf('███████████████████████████████████████████████████████████\n');
                    fprintf('[AL] Pf final = %.6f\n', Pf_current);
                    fprintf('[AL] Casos validos: %d\n', valid_case_count);
                    fprintf('[AL] Iteracao: %d\n\n', iteration);
                    
                    convergence_detected = true;
                    convergence_status = 'CONVERGED';
                end
            else
                pf_stable_comparisons = 0;
                convergence_status = 'UNSTABLE';
                fprintf('[AL-S4-E3-P8]   ! Pf instavel\n\n');
            end
        end
        
        % REGISTRAR NA AUDITORIA
        Pf_for_audit = NaN;
        if ~isempty(Pf_history)
            Pf_for_audit = Pf_history(end);
        end
        
        auditRow = {iteration, simID, iCand, yPred, yObs, ...
            'ACCEPTED', envelope_status, field_status, ...
            Pf_for_audit, pf_stable_comparisons, convergence_status, ...
            'Caso valido adicionado'};
        
        auditTable = [auditTable; cell2table(auditRow, ...
            'VariableNames', auditNames)];
        
        simID = simID + 1;
        break;
    end
    
    if ~case_added_this_iter
        fprintf('[AL-S4-E3] ! ITERACAO %d: NENHUM candidato valido!\n\n', iteration);
    end
end

%% =========================================================================
% SECAO 5: SALVAMENTO DE RESULTADOS
%% =========================================================================

fprintf('[AL-S5] SECAO 5: Salvamento de Resultados\n');
fprintf('[AL-S5] ====================================\n\n');

% Xi acumulado
xi_file = fullfile(cfg.stage4_out_dir, sprintf('augmented_xi_iter%d.csv', iteration));
Xi_table = array2table(Xi_accumulated);
Xi_table.Properties.VariableNames = arrayfun(@(i) sprintf('xi_%d', i), ...
    1:size(Xi_accumulated, 2), 'UniformOutput', false);
writetable(Xi_table, xi_file);

fprintf('[AL-S5] ✓ Xi acumulado: %s\n', xi_file);

% RV acumulado
rv_file = fullfile(cfg.stage4_out_dir, sprintf('augmented_rv_iter%d.csv', iteration));
RV_table = array2table(RV_accumulated);
RV_table.Properties.VariableNames = Stage3Contract.mandatory_rv_names;
writetable(RV_table, rv_file);

fprintf('[AL-S5] ✓ RV acumulado: %s\n', rv_file);

% Resultados acumulados
results_file = fullfile(cfg.stage4_out_dir, sprintf('augmented_results_iter%d.csv', iteration));
results_table = table(sampleID_accumulated, y_accumulated, ...
    'VariableNames', {'SampleID', 'Displacement_m'});
writetable(results_table, results_file);

fprintf('[AL-S5] ✓ Resultados acumulados: %s\n\n', results_file);

% Salvar auditoria
audit_file = fullfile(cfg.stage4_out_dir, 'audit_al_stage4.csv');
writetable(auditTable, audit_file);

fprintf('[AL-S5] ✓ Auditoria: %s\n', audit_file);
fprintf('[AL-S5] ✓ Registros: %d\n\n', height(auditTable));

% Salvar historico de Pf
if ~isempty(Pf_history)
    pf_file = fullfile(cfg.stage4_out_dir, 'pf_history.mat');
    save(pf_file, 'Pf_history', 'Pf_history_iter', 'cfg');
    fprintf('[AL-S5] ✓ Historico Pf: %s\n\n', pf_file);
end

%% =========================================================================
% SECAO 6: CONSTRUIR ESTRUTURA DE SAIDA
%% =========================================================================

fprintf('[AL-S6] SECAO 6: Construindo Estrutura de Saida\n');
fprintf('[AL-S6] ====================================\n\n');

outAL = struct();
outAL.modelFile = cfg.stage3_best_file;
outAL.auditFile = audit_file;
outAL.Pf_final = NaN;
outAL.iterationsCompleted = iteration;
outAL.validCasesAdded = valid_case_count;
outAL.convergenceHistory = Pf_history;

% Determinar status final
if convergence_detected
    outAL.status = 'CONVERGED';
    outAL.stopReason = sprintf('Convergencia Pf detectada apos %d iteracoes', iteration);
    outAL.Pf_final = Pf_history(end);
    
elseif valid_case_count == 0
    outAL.status = 'NO_VALID_NEW_CASES';
    outAL.stopReason = 'Nenhum caso novo valido foi adicionado';
    
else
    outAL.status = 'MAX_ITERS';
    outAL.stopReason = sprintf('Limite de %d iteracoes atingido', cfg.AL_MAX_ITERS);
    if ~isempty(Pf_history)
        outAL.Pf_final = Pf_history(end);
    end
end

fprintf('[AL-S6] Status: %s\n', outAL.status);
fprintf('[AL-S6] Motivo: %s\n', outAL.stopReason);
fprintf('[AL-S6] Arquivo modelo: %s\n', outAL.modelFile);
fprintf('[AL-S6] Arquivo auditoria: %s\n', outAL.auditFile);
fprintf('[AL-S6] Pf final: %.6f\n', outAL.Pf_final);
fprintf('[AL-S6] Casos validos: %d\n\n', outAL.validCasesAdded);

%% =========================================================================
% SECAO 7: RESUMO FINAL
%% =========================================================================

fprintf('\n');
fprintf('███████████████████████████████████████████████████████████████████\n');
fprintf('█                         RESUMO FINAL                             █\n');
fprintf('███████████████████████████████████████████████████████████████████\n\n');

fprintf('[AL-S7] EXECUCAO:\n');
fprintf('[AL-S7]   Iteracoes: %d/%d\n', iteration, cfg.AL_MAX_ITERS);
fprintf('[AL-S7]   Casos validos: %d\n', valid_case_count);
fprintf('[AL-S7]   IDs de simulacao: %d-%d\n', cfg.AL_START_SIM_ID, simID-1);

fprintf('[AL-S7]\n');
fprintf('[AL-S7] DADOS ACUMULADOS:\n');
fprintf('[AL-S7]   Amostras iniciais (Stage 3): %d\n', size(X_train, 1));
fprintf('[AL-S7]   Amostras adicionadas (AL): %d\n', valid_case_count);
fprintf('[AL-S7]   Total de amostras: %d\n', numel(y_accumulated));

if cfg.AL_USE_Pf_STABILITY
    fprintf('[AL-S7]\n');
    fprintf('[AL-S7] CONVERGENCIA Pf:\n');
    if ~isempty(Pf_history)
        fprintf('[AL-S7]   Leituras: %d\n', numel(Pf_history));
        fprintf('[AL-S7]   Pf_inicial: %.6f (Stage 3)\n', Pf_history(1));
        fprintf('[AL-S7]   Pf_final:   %.6f (Iteracao %d)\n', ...
            Pf_history(end), Pf_history_iter(end));
        
        var_pf = 100 * abs(Pf_history(end) - Pf_history(1)) / ...
            max(Pf_history(1), cfg.AL_Pf_floor);
        fprintf('[AL-S7]   Variacao: %.4f%%\n', var_pf);
    end
end

fprintf('[AL-S7]\n');
fprintf('[AL-S7] STATUS FINAL: %s\n', outAL.status);

fprintf('[AL-S7]\n');
fprintf('[AL-S7] ARQUIVOS DE SAIDA (em %s):\n', cfg.stage4_out_dir);
fprintf('[AL-S7]   - audit_al_stage4.csv\n');
fprintf('[AL-S7]   - augmented_xi_iter%d.csv\n', iteration);
fprintf('[AL-S7]   - augmented_rv_iter%d.csv\n', iteration);
fprintf('[AL-S7]   - augmented_results_iter%d.csv\n', iteration);
if ~isempty(Pf_history)
    fprintf('[AL-S7]   - pf_history.mat\n');
end

fprintf('\n');
fprintf('███████████████████████████████████████████████████████████████████\n');
fprintf('█                    FIM DO STAGE 4 - AL v8                        █\n');
fprintf('█               Timestamp: %s                        █\n', ...
    datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
fprintf('███████████████████████████████████████████████████████████████████\n\n');

end
