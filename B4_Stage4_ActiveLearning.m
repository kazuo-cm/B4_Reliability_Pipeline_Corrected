function outAL = B4_Stage4_ActiveLearning(cfg)
% =========================================================================
% B4_Stage4_ActiveLearning - PC-Kriging normalizado / Active Learning local
%
% CORRECAO #2: cfg completo propagado ao suporte espacial.
% CORRECAO #3: AL_USE_Pf_STABILITY controla as leituras de Pf.
% CORRECAO #4: envelope gera aviso ou rejeicao, conforme configuracao.
% CORRECAO #5: janela de leituras em modelos efetivamente retreinados.
% CORRECAO #6: materiais vazios permitidos somente quando configurados.
% CORRECAO #7: exatamente 18 RVs, na ordem do contrato do Stage 3.
% CORRECAO #8: nenhuma observacao sintetica; CSV ou Python/RS2 real.
%
% Requer Stages 0-3, UQLab e B4_Suport_build_spatial_fields_from_xi no path.
% O contrato Python configuravel esta documentado em B4_DefaultConfig.m.
% Pf usa a aproximacao Gaussiana do Stage 3, nao uma certificacao global.
% =========================================================================

%% SECAO 1: VALIDACOES INICIAIS
local_validate_config(cfg);
trainInitial = cfg.AL_RETRAIN_EACH_ITER || cfg.AL_RESET_ON_START || ...
    cfg.run_stage0 || cfg.run_stage1 || cfg.run_stage2 || cfg.run_stage3 || ...
    ~isfile(cfg.stage3_best_file);
if ~isfolder(cfg.stage4_out_dir)
    mkdir(cfg.stage4_out_dir);
end
assert(~isempty(which('uq_evalModel')), 'B4:MissingUQLab', ...
    'UQLab nao encontrado no path.');
assert(~isempty(which('B4_Suport_build_spatial_fields_from_xi')), ...
    'B4:MissingSpatialSupport', ...
    'B4_Suport_build_spatial_fields_from_xi nao encontrado no path.');
if trainInitial
    local_require_stages();
end
if cfg.stage4_execute_rs2
    assert(usejava('jvm'), 'B4:MissingJVM', ...
        'Execucao Python requer MATLAB com JVM (nao usar -nojvm).');
    assert(isfile(cfg.python_exe) && isfile(cfg.batch_script) && ...
        isfile(cfg.stage4_base_model_file), 'B4:MissingRS2Inputs', ...
        'Verifique python_exe, batch_script e stage4_base_model_file.');
end

%% SECAO 2: TREINAMENTO INICIAL E CARREGAMENTO
initialCfg = local_initial_training_config(cfg);
if trainInitial
    local_retrain_pipeline(initialCfg);
end
M = local_load_model(cfg.stage3_best_file);
rvNames = cellstr(string(M.Stage3Contract.mandatory_rv_names(:))');
xiNames = arrayfun(@(j) sprintf('xi_%d', j), ...
    1:size(M.Xi, 2), 'UniformOutput', false);
fullNames = [rvNames, xiNames];
local_model_columns(M, fullNames);

% Preservar nomes e esquema dos CSVs originais, inclusive IDs.
templates = local_read_templates(initialCfg, M, rvNames);
Xi = double(M.Xi);
RV = double(M.RV);
y = double(M.y(:));
sampleID = double(M.sampleID(:));
initial_count = numel(y);

%% SECAO 3: HISTORICO E AUDITORIA
auditNames = {'Iteration','SimulationID','CandidateIndex', ...
    'PredictedDisplacement_m','ObservedDisplacement_m', ...
    'ValidationStatus','EnvelopeStatus','FieldStatus','Pf_Current', ...
    'Pf_StableComparisons','ConvergenceStatus','Message'};
auditTable = local_audit_row(0,0,0,NaN,NaN,'','','',NaN,0,'','',auditNames);
auditTable = auditTable([],:);
Pf_history = zeros(0, 1);
Pf_history_iter = zeros(0, 1);
Pf_failures = zeros(0, 1);
pfPopulation = [];
if cfg.AL_USE_Pf_STABILITY
    % FIXA no espaco fisico COMPLETO: selecao/normalizacao podem mudar.
    X = [RV, Xi];
    % Geracao por coluna evita alocar Npop x todos os milhares de Xi.
    pfPopulation = struct('mu', mean(X,1), 'sigma', std(X,0,1), ...
        'size', cfg.AL_Pf_mcs_target_population, 'seed', cfg.seed);
    [Pf_history(1,1), Pf_failures(1,1)] = ...
        local_estimate_pf(M, pfPopulation, fullNames, cfg);
    Pf_history_iter(1,1) = 0;
end
iteration = 0;
valid_case_count = 0;
simID = max(cfg.AL_START_SIM_ID, max(sampleID) + 1);
previousAttempts = dir(fullfile(cfg.stage4_out_dir, 'simulation_*'));
for j = 1:numel(previousAttempts)
    previousID = sscanf(previousAttempts(j).name, 'simulation_%d');
    if previousAttempts(j).isdir && isscalar(previousID)
        simID = max(simID, previousID + 1);
    end
end
converged = false;
stopReason = "MAX_ITERATIONS";
runStatus = "COMPLETED";

%% SECAO 4: LOOP PRINCIPAL
while iteration < cfg.AL_MAX_ITERS && ~converged
    iteration = iteration + 1;
    fprintf('\n[AL] Iteracao %d/%d; %d casos acumulados.\n', ...
        iteration, cfg.AL_MAX_ITERS, numel(y));
    rng(cfg.seed + iteration, 'twister');

    % Centro local: caso observado mais proximo do estado limite.
    [~, base] = min(abs(y - cfg.recalque_lim));
    U = lhsdesign(cfg.AL_CANDIDATE_POOL, numel(fullNames));
    Z = norminv(min(max(U, eps), 1-eps));
    candidates_xi = Xi(base,:) + ...
        cfg.local_radius_xi .* std(Xi, 0, 1) .* Z(:,19:end);
    candidates_rv = RV(base,:) .* exp(cfg.local_radius_rv .* Z(:,1:18));
    % Coeficientes de Poisson permanecem em (0.01, 0.49).
    poisson = contains(lower(string(rvNames)), 'poisson') | ...
        startsWith(lower(string(rvNames)), 'nu');
    if any(poisson)
        p = (RV(base,poisson) - 0.01) / 0.48;
        p = min(max(p, eps), 1-eps);
        logit = log(p ./ (1-p)) + cfg.poisson_logit_radius .* Z(:,find(poisson));
        candidates_rv(:,poisson) = 0.01 + 0.48 ./ (1 + exp(-logit));
    end
    accepted = false;
    for iCand = 1:cfg.AL_CANDIDATE_POOL
        % IDs pertencem a tentativas, nao apenas a casos aceitos.
        attemptID = simID;
        simID = simID + 1;
        xi_cand = candidates_xi(iCand,:);
        rv_cand = candidates_rv(iCand,:);
        yPred = NaN;
        yObs = NaN;
        envelope_status = 'OK';
        field_status = 'N/A';
        try
            yPred = local_predict(M, [rv_cand, xi_cand], fullNames);
            envelope_limit = cfg.recalque_lim * cfg.max_displacement_factor;
            if yPred > envelope_limit
                envelope_status = 'WARNING_PREDICTION';
                if cfg.AL_REJECT_DISPLACEMENT_OUTLIERS
                    error('B4:PredictionEnvelope', 'Predicao acima do envelope.');
                end
                warning('B4:PredictionEnvelope', 'Predicao acima do envelope.');
            end

            % Validar/exportar campo ANTES de chamar RS2.
            attemptDir = fullfile(cfg.stage4_out_dir, ...
                sprintf('simulation_%d', attemptID));
            assert(~isfolder(attemptDir), 'B4:ExistingAttempt', ...
                'Pasta de tentativa ja existe: %s. Use uma nova pasta de execucao.', attemptDir);
            mkdir(attemptDir);
            field_status = 'INVALID';
            field_file = local_build_field(xi_cand, cfg, attemptDir);
            field_status = 'OK';
            [yObs, resultRow] = local_run_rs2_simulation( ...
                xi_cand, rv_cand, attemptID, cfg, templates, ...
                attemptDir, field_file);
            if yObs > envelope_limit
                envelope_status = 'WARNING_OUTLIER';
                if cfg.AL_REJECT_DISPLACEMENT_OUTLIERS
                    error('B4:ObservedEnvelope', 'Deslocamento observado acima do envelope.');
                end
                warning('B4:ObservedEnvelope', ...
                    'Resultado real aceito com alerta de envelope: %.6g m.', yObs);
            end
        catch ME
            auditTable = [auditTable; local_audit_row(iteration,attemptID,iCand, ...
                yPred,yObs,'REJECTED',envelope_status,field_status, ...
                NaN,0,'N',ME.message,auditNames)]; %#ok<AGROW>
            fprintf('[AL] Tentativa %d rejeitada: %s\n', attemptID, ME.message);
            continue;
        end

        Xi(end+1,:) = xi_cand;
        RV(end+1,:) = rv_cand;
        y(end+1,1) = yObs;
        sampleID(end+1,1) = attemptID;
        templates = local_append_templates(templates, xi_cand, rv_cand, ...
            attemptID, yObs, resultRow, rvNames);
        valid_case_count = valid_case_count + 1;
        accepted = true;
        Pf_current = NaN;
        stable_comps = 0;
        convergence_status = 'N';
        message = 'Caso real adicionado ao conjunto';
        try
            cfg_retrain = local_save_training(templates, cfg, iteration);
            if cfg.AL_RETRAIN_EACH_ITER
                % ETAPA 1: retreinar e RECARREGAR antes de estimar Pf.
                local_retrain_pipeline(cfg_retrain);
                M = local_load_model(cfg.stage3_best_file);
                local_check_training(M, Xi, RV, y, sampleID);
                if cfg.AL_USE_Pf_STABILITY
                    [Pf_current, nFailures] = ...
                        local_estimate_pf(M, pfPopulation, fullNames, cfg);
                    Pf_history(end+1,1) = Pf_current;
                    Pf_history_iter(end+1,1) = iteration;
                    Pf_failures(end+1,1) = nFailures;
                    [converged, stable_comps] = local_pf_converged( ...
                        Pf_history, Pf_failures, valid_case_count, cfg);
                    if converged
                        convergence_status = 'CONVERGED';
                        stopReason = "PF_STABLE";
                        runStatus = "CONVERGED";
                    else
                        convergence_status = 'NOT_CONVERGED';
                    end
                end
            else
                message = 'Caso real adicionado; retreinamento desativado, sem parada Pf';
            end
        catch ME
            % Um modelo obsoleto nunca deve produzir uma leitura de convergencia.
            runStatus = "FAILED";
            stopReason = "RETRAIN_OR_PF_FAILED";
            message = ME.message;
            convergence_status = 'ERROR';
        end
        auditTable = [auditTable; local_audit_row(iteration,attemptID,iCand, ...
            yPred,yObs,'ACCEPTED',envelope_status,field_status, ...
            Pf_current,stable_comps,convergence_status,message,auditNames)]; %#ok<AGROW>
        writetable(auditTable, fullfile(cfg.stage4_out_dir, 'audit_al_stage4.csv'));
        break;
    end
    if ~accepted
        fprintf('[AL] Nenhum candidato valido nesta iteracao.\n');
    end
    if runStatus == "FAILED" || ~cfg.stage4_auto_loop
        if runStatus ~= "FAILED" && ~converged
            stopReason = "SINGLE_ITERATION";
        end
        break;
    end
end

%% SECAO 5: SAIDA E SALVAMENTO
if valid_case_count == 0
    runStatus = "NO_VALID_NEW_CASES";
    stopReason = "NO_VALID_NEW_CASES";
end
outAL = struct('status', runStatus, 'stopReason', stopReason, ...
    'modelFile', string(cfg.stage3_best_file), ...
    'auditFile', string(fullfile(cfg.stage4_out_dir, 'audit_al_stage4.csv')), ...
    'iterations', iteration, 'validCases', valid_case_count, ...
    'pfHistoryFile', string(fullfile(cfg.stage4_out_dir, 'pf_history.mat')));
local_save_training(templates, cfg, iteration);
writetable(auditTable, outAL.auditFile);
save(outAL.pfHistoryFile, 'Pf_history', 'Pf_history_iter', 'Pf_failures', ...
    'pfPopulation', 'fullNames', 'outAL', 'cfg', '-v7.3');
save(fullfile(cfg.stage4_out_dir, 'stage4_result.mat'), 'outAL');

%% SECAO 6: RESUMO FINAL
fprintf('[AL] %s / %s; %d casos novos, %d casos totais (inicial: %d).\n', ...
    outAL.status, outAL.stopReason, valid_case_count, numel(y), initial_count);
fprintf('[AL] Modelo: %s\n[AL] Auditoria: %s\n', outAL.modelFile, outAL.auditFile);
end

%% FUNCOES AUXILIARES
function row = local_audit_row(iteration,id,index,predicted,observed, ...
        status,envelope,field,pf,stable,convergence,message,names)
row = table(iteration,id,index,predicted,observed,string(status), ...
    string(envelope),string(field),pf,stable,string(convergence), ...
    string(message), 'VariableNames', names);
end

function local_validate_config(cfg)
required = {'AL_USE_Pf_STABILITY','AL_Pf_mcs_target_population', ...
    'AL_Pf_mcs_min_failures','AL_Pf_stability_tolerance', ...
    'AL_Pf_min_iterations','AL_Pf_comparison_window','AL_Pf_floor', ...
    'AL_Pf_stable_readings','AL_REJECT_DISPLACEMENT_OUTLIERS','seed', ...
    'AL_MAX_ITERS','AL_CANDIDATE_POOL','AL_START_SIM_ID', ...
    'AL_RETRAIN_EACH_ITER','AL_RESET_ON_START','stage4_execute_rs2','stage4_auto_loop', ...
    'run_stage0','run_stage1','run_stage2','run_stage3', ...
    'stage4_python_args','stage4_result_displacement_column', ...
    'recalque_lim','spatial_allow_missing_materials','max_displacement_factor'};
for j = 1:numel(required)
    assert(isfield(cfg, required{j}), 'B4:MissingConfig', ...
        'cfg.%s ausente. Use B4_DefaultConfig().', required{j});
end
integers = {'AL_MAX_ITERS','AL_CANDIDATE_POOL','AL_START_SIM_ID', ...
    'AL_Pf_mcs_target_population','AL_Pf_mcs_min_failures', ...
    'AL_Pf_min_iterations','AL_Pf_stable_readings','AL_Pf_comparison_window'};
for j = 1:numel(integers)
    validateattributes(cfg.(integers{j}), {'numeric'}, ...
        {'scalar','finite','integer','positive'});
end
validateattributes(cfg.seed, {'numeric'}, {'scalar','integer','nonnegative','finite'});
assert(cfg.AL_Pf_stable_readings >= 2 && ...
    cfg.AL_Pf_comparison_window >= cfg.AL_Pf_stable_readings, ...
    'B4:InvalidPfWindow', 'Janela Pf deve conter pelo menos stable_readings >= 2.');
assert(cfg.AL_Pf_mcs_min_failures <= cfg.AL_Pf_mcs_target_population, ...
    'B4:InvalidPfFailures', 'Numero minimo de falhas excede populacao Pf.');
positive = {'AL_Pf_floor','AL_Pf_stability_tolerance','recalque_lim', ...
    'max_displacement_factor','local_radius_xi','local_radius_rv','poisson_logit_radius'};
for j = 1:numel(positive)
    validateattributes(cfg.(positive{j}), {'numeric'}, {'scalar','finite','positive'});
end
end

function local_require_stages()
stages = {'B4_Stage0_AlignData','B4_Stage1_RankVariables', ...
    'B4_Stage2_SelectVariables','B4_Stage3_TrainPCK'};
for j = 1:numel(stages)
    assert(~isempty(which(stages{j})), 'B4:MissingStage', ...
        '%s nao encontrado no path; instale os Stages 0-3 originais.', stages{j});
end
end

function local_retrain_pipeline(cfg)
local_require_stages();
B4_Stage0_AlignData(cfg);
B4_Stage1_RankVariables(cfg);
B4_Stage2_SelectVariables(cfg);
B4_Stage3_TrainPCK(cfg);
end

function initial = local_initial_training_config(cfg)
initial = cfg;
paths = {fullfile(cfg.stage4_out_dir, 'augmented_xi.csv'), ...
    fullfile(cfg.stage4_out_dir, 'current_material_rv.csv'), ...
    fullfile(cfg.stage4_out_dir, 'current_liner_rv.csv'), ...
    fullfile(cfg.stage4_out_dir, 'augmented_results.csv')};
exists = cellfun(@isfile, paths);
if ~cfg.AL_RESET_ON_START && any(exists)
    assert(all(exists), 'B4:IncompleteSnapshot', ...
        'Snapshot acumulado incompleto; restaure os quatro CSVs ou use AL_RESET_ON_START.');
    initial.training_xi_file = paths{1};
    initial.material_rv_file = paths{2};
    initial.liner_rv_file = paths{3};
    initial.training_results_file = paths{4};
    initial.stage4_resume_snapshot = true;
end
end

function M = local_load_model(path)
M = load(path);
required = {'modelPCK','vars_train','muX_original','sdX_original', ...
    'muY_original','sdY_original','Stage3Contract','Xi','RV','Xtr','y','sampleID'};
assert(all(isfield(M, required)), 'B4:InvalidModel', 'Stage 3 incompleto.');
names = string(M.Stage3Contract.mandatory_rv_names(:));
assert(numel(names) == 18 && numel(unique(names)) == 18 && size(M.RV,2) == 18, ...
    'B4:InvalidRVContract', 'Esperados 18 RVs distintos.');
trainNames = string(M.vars_train(:));
assert(numel(trainNames) >= 18 && isequal(trainNames(1:18), names), ...
    'B4:InvalidRVOrder', 'Ordem dos 18 RVs inconsistente.');
assert(size(M.Xi,1) == numel(M.y) && size(M.RV,1) == numel(M.y) && ...
    numel(M.sampleID) == numel(M.y) && ...
    numel(unique(M.sampleID)) == numel(M.sampleID), ...
    'B4:InvalidTrainingRows', 'Dados de Stage 3 desalinhados ou IDs duplicados.');
assert(all(isfinite([M.Xi(:); M.RV(:); M.y(:); M.sampleID(:)])) && ...
    all(M.sampleID == fix(M.sampleID)), 'B4:InvalidTrainingData', ...
    'Dados nao finitos ou IDs nao inteiros.');
assert(numel(M.muX_original) == numel(M.vars_train) && ...
    numel(M.sdX_original) == numel(M.vars_train) && ...
    all(isfinite(M.muX_original)) && all(isfinite(M.sdX_original)) && ...
    all(M.sdX_original > 0) && isscalar(M.muY_original) && ...
    isfinite(M.muY_original) && isscalar(M.sdY_original) && ...
    isfinite(M.sdY_original) && M.sdY_original > 0, ...
    'B4:InvalidNormalization', 'Normalizacao de Stage 3 invalida.');
end

function columns = local_model_columns(M, fullNames)
[found, columns] = ismember(string(M.vars_train), string(fullNames));
assert(all(found) && numel(unique(columns)) == numel(columns), ...
    'B4:InvalidModelInputs', 'Variaveis selecionadas ausentes ou duplicadas.');
end

function yPred = local_predict(M, X, fullNames)
columns = local_model_columns(M, fullNames);
XN = (X(:,columns) - M.muX_original(:)') ./ M.sdX_original(:)';
yPred = double(uq_evalModel(M.modelPCK, XN));
yPred = yPred(:) * M.sdY_original + M.muY_original;
assert(numel(yPred) == size(X,1) && all(isfinite(yPred)), ...
    'B4:InvalidPrediction', 'Predicao nao finita ou dimensao invalida.');
end

function [pf, failures] = local_estimate_pf(M, population, names, cfg)
% Avaliar toda a populacao fixa evita vies de parada no N-esimo fracasso.
columns = local_model_columns(M, names);
X = zeros(population.size, numel(columns));
state = rng;
cleanup = onCleanup(@() rng(state));
for j = 1:numel(columns)
    column = columns(j);
    % Mesma coluna fisica em todos os modelos, mesmo quando re-selecionada.
    rng(mod(double(population.seed) + column, 2^32), 'twister');
    U = (randperm(population.size)' - rand(population.size,1)) / population.size;
    X(:,j) = population.mu(column) + population.sigma(column) .* ...
        norminv(min(max(U, eps), 1-eps));
end
clear cleanup;
failures = 0;
for first = 1:1000:size(X,1)
    last = min(first + 999, size(X,1));
    XN = (X(first:last,:) - M.muX_original(:)') ./ M.sdX_original(:)';
    prediction = double(uq_evalModel(M.modelPCK, XN));
    prediction = prediction(:) * M.sdY_original + M.muY_original;
    assert(numel(prediction) == last-first+1 && all(isfinite(prediction)), ...
        'B4:InvalidPfPrediction', 'Populacao Pf retornou predicoes invalidas.');
    failures = failures + sum(prediction >= cfg.recalque_lim);
end
pf = failures / size(X,1);
end

function [converged, stable] = local_pf_converged(history, failures, retrains, cfg)
converged = false;
stable = 0;
window = min(cfg.AL_Pf_comparison_window, numel(history));
if retrains < cfg.AL_Pf_min_iterations || window < cfg.AL_Pf_stable_readings
    return;
end
p = history(end-window+1:end);
f = failures(end-window+1:end);
% Zero/poucas falhas nao sao evidencia de estabilidade em eventos raros.
if any(~isfinite(p)) || any(f < cfg.AL_Pf_mcs_min_failures)
    return;
end
relative = abs(diff(p)) ./ max(p(1:end-1), cfg.AL_Pf_floor);
for j = numel(relative):-1:1
    if relative(j) >= cfg.AL_Pf_stability_tolerance
        break;
    end
    stable = stable + 1;
end
converged = stable >= cfg.AL_Pf_stable_readings - 1;
end

function T = local_read_templates(cfg, M, rvNames)
T.xi = readtable(cfg.training_xi_file, 'VariableNamingRule', 'preserve');
T.material = readtable(cfg.material_rv_file, 'VariableNamingRule', 'preserve');
T.liner = readtable(cfg.liner_rv_file, 'VariableNamingRule', 'preserve');
T.results = readtable(cfg.training_results_file, 'VariableNamingRule', 'preserve');
if isfield(cfg, 'stage4_resume_snapshot') && cfg.stage4_resume_snapshot
    snapshotIDs = double(T.xi.(local_id_column(T.xi)));
    assert(numel(snapshotIDs) == numel(M.sampleID) && ...
        all(ismember(snapshotIDs, M.sampleID)), 'B4:UntrainedSnapshot', ...
        ['Snapshot contem observacoes nao incorporadas ao modelo. ', ...
         'Ative treinamento inicial ou AL_RETRAIN_EACH_ITER antes de retomar; ', ...
         'os CSVs acumulados nao foram alterados.']);
end
fields = {'xi','material','liner','results'};
for j = 1:numel(fields)
    name = fields{j};
    id = local_id_column(T.(name));
    ids = double(T.(name).(id));
    assert(all(isfinite(ids)) && numel(unique(ids)) == numel(ids), ...
        'B4:DuplicateIDs', 'IDs invalidos/duplicados no CSV %s.', name);
    [found, rows] = ismember(M.sampleID, ids);
    assert(all(found), 'B4:MissingTrainingIDs', 'IDs de Stage 3 ausentes em %s.', name);
    T.(name) = T.(name)(rows,:);
end
T.xiNames = arrayfun(@(j) sprintf('xi_%d', j), ...
    1:size(M.Xi,2), 'UniformOutput', false);
assert(all(ismember(T.xiNames, T.xi.Properties.VariableNames)), ...
    'B4:MissingXiColumns', 'CSV Xi deve preservar colunas xi_1 ... xi_N.');
inMat = ismember(rvNames, T.material.Properties.VariableNames);
inLiner = ismember(rvNames, T.liner.Properties.VariableNames);
assert(all(xor(inMat, inLiner)), 'B4:InvalidRVFiles', ...
    'Cada um dos 18 RVs deve aparecer exatamente em um CSV (material/liner).');
T.response = cfg.stage4_result_displacement_column;
T.rvNames = rvNames;
assert(ismember(T.response, T.results.Properties.VariableNames), ...
    'B4:MissingResponse', 'Configure stage4_result_displacement_column para o CSV real.');
R = zeros(numel(M.y),18);
R(:,inMat) = T.material{:,rvNames(inMat)};
R(:,inLiner) = T.liner{:,rvNames(inLiner)};
assert(local_same_data(double(T.xi{:,T.xiNames}), double(M.Xi)) && ...
    local_same_data(R, double(M.RV)) && ...
    local_same_data(double(T.results.(T.response)), double(M.y(:))), ...
    'B4:StaleTrainingCSV', 'CSVs de entrada diferem dos dados do modelo Stage 3.');
end

function id = local_id_column(T)
names = T.Properties.VariableNames;
matches = find(ismember(lower(string(names)), ...
    ["sampleid","simulationid"]));
assert(numel(matches) == 1, 'B4:InvalidIDColumn', ...
    'CSV deve ter exatamente uma coluna SampleID ou SimulationID.');
id = names{matches};
end

function row = local_empty_row(T, id)
% Inicializar campos extras como ausentes, nunca copiar resultados antigos.
row = T(1,:);
for j = 1:width(row)
    name = row.Properties.VariableNames{j};
    value = row.(name);
    if isnumeric(value)
        row.(name)(:) = NaN;
    elseif islogical(value)
        row.(name)(:) = false;
    elseif iscell(value)
        row.(name)(:) = {''};
    elseif isstring(value)
        row.(name)(:) = missing;
    elseif isdatetime(value)
        row.(name)(:) = NaT;
    elseif iscategorical(value)
        row.(name)(:) = categorical(missing);
    else
        error('B4:UnsupportedCSVType', 'Tipo CSV nao suportado: %s.', name);
    end
end
row.(local_id_column(row)) = id;
end

function T = local_append_templates(T, xi, rv, id, observed, resultRow, names)
row = local_empty_row(T.xi, id);
row{1,T.xiNames} = xi;
T.xi = [T.xi; row];
for field = {'material','liner'}
    key = field{1};
    row = local_empty_row(T.(key), id);
    present = ismember(names, row.Properties.VariableNames);
    row{1,names(present)} = rv(present);
    T.(key) = [T.(key); row];
end
row = local_empty_row(T.results, id);
common = intersect(row.Properties.VariableNames, resultRow.Properties.VariableNames);
for j = 1:numel(common)
    row.(common{j}) = resultRow.(common{j});
end
row.(local_id_column(row)) = id;
row.(T.response) = observed;
T.results = [T.results; row];
end

function retrain = local_save_training(T, cfg, iteration)
retrain = cfg;
retrain.training_xi_file = fullfile(cfg.stage4_out_dir, 'augmented_xi.csv');
retrain.material_rv_file = fullfile(cfg.stage4_out_dir, 'current_material_rv.csv');
retrain.liner_rv_file = fullfile(cfg.stage4_out_dir, 'current_liner_rv.csv');
retrain.training_results_file = fullfile(cfg.stage4_out_dir, 'augmented_results.csv');
paths = {retrain.training_xi_file, retrain.material_rv_file, ...
    retrain.liner_rv_file, retrain.training_results_file};
originals = {cfg.training_xi_file,cfg.material_rv_file, ...
    cfg.liner_rv_file,cfg.training_results_file};
for j = 1:numel(paths)
    assert(~any(strcmpi(paths{j}, originals)), 'B4:UnsafeTrainingOutput', ...
        'Saida acumulada nao pode sobrescrever CSVs originais.');
end
writetable(T.xi, paths{1});
writetable(T.material, paths{2});
writetable(T.liner, paths{3});
writetable(T.results, paths{4});
writetable(T.xi, fullfile(cfg.stage4_out_dir, sprintf('augmented_xi_iter%d.csv', iteration)));
rvValues = zeros(height(T.xi),18);
inMat = ismember(T.rvNames, T.material.Properties.VariableNames);
rvValues(:,inMat) = T.material{:,T.rvNames(inMat)};
rvValues(:,~inMat) = T.liner{:,T.rvNames(~inMat)};
rvTable = array2table(rvValues, 'VariableNames', T.rvNames);
rvTable = addvars(rvTable, T.xi.(local_id_column(T.xi)), ...
    'Before', 1, 'NewVariableNames', 'SampleID');
writetable(rvTable, fullfile(cfg.stage4_out_dir, sprintf('augmented_rv_iter%d.csv', iteration)));
writetable(T.results, fullfile(cfg.stage4_out_dir, sprintf('augmented_results_iter%d.csv', iteration)));
end

function local_check_training(M, Xi, RV, y, ids)
[found, rows] = ismember(ids, M.sampleID);
assert(all(found) && numel(M.y) == numel(y) && ...
    local_same_data(double(M.Xi(rows,:)), Xi) && ...
    local_same_data(double(M.RV(rows,:)), RV) && ...
    local_same_data(double(M.y(rows)), y), 'B4:RetrainingIgnoredData', ...
    'Stages 0-3 nao consumiram os CSVs acumulados corretamente.');
end

function same = local_same_data(A, B)
same = isequal(size(A),size(B)) && ...
    all(abs(A(:)-B(:)) <= 1e-10 * max(1,abs(B(:))));
end

function path = local_build_field(xi, cfg, attemptDir)
[x, y, c, phi, E] = B4_Suport_build_spatial_fields_from_xi(xi, cfg);
if ~iscell(x)
    x = {x}; y = {y}; c = {c}; phi = {phi}; E = {E};
end
assert(iscell(y) && iscell(c) && iscell(phi) && iscell(E) && ...
    isequal(numel(x),numel(y),numel(c),numel(phi),numel(E)), ...
    'B4:InvalidSpatialOutput', 'Saidas espaciais devem ter dimensoes/material compativeis.');
T = array2table(zeros(0,6), 'VariableNames', {'MaterialID','X','Y','c','phi','E'});
for j = 1:numel(x)
    values = {x{j},y{j},c{j},phi{j},E{j}};
    empty = cellfun(@isempty, values);
    if any(empty)
        assert(all(empty) && cfg.spatial_allow_missing_materials, ...
            'B4:EmptyMaterial', 'Material %d vazio/incompleto; tolerancia=%d.', ...
            j, cfg.spatial_allow_missing_materials);
        continue;
    end
    if isvector(values{1}) && isvector(values{2}) && ...
            isequal(size(values{3}), [numel(values{2}),numel(values{1})])
        [values{1}, values{2}] = meshgrid(values{1},values{2});
    end
    count = numel(values{1});
    assert(all(cellfun(@(v) isnumeric(v) && numel(v) == count && ...
        all(isfinite(v(:))), values)), 'B4:InvalidSpatialValues', ...
        'Campo do material %d nao finito/desalinhado.', j);
    assert(all(values{3}(:) >= 0) && all(values{4}(:) >= 0 & values{4}(:) < 90) && ...
        all(values{5}(:) > 0), 'B4:InvalidSpatialProperties', ...
        'Propriedades espaciais invalidas no material %d.', j);
    block = [repmat(j,count,1), values{1}(:),values{2}(:), ...
        values{3}(:),values{4}(:),values{5}(:)];
    T = [T; array2table(block, 'VariableNames', T.Properties.VariableNames)]; %#ok<AGROW>
end
assert(height(T) > 0, 'B4:EmptySpatialField', 'Nenhum material tem pontos validos.');
path = fullfile(attemptDir, 'spatial_field.csv');
writetable(T, path);
end

function [observed, resultRow] = local_run_rs2_simulation(xi, rv, id, cfg, T, attemptDir, field)
names = cellstr(string([T.material.Properties.VariableNames, ...
    T.liner.Properties.VariableNames]));
% Valores seguem a ordem do contrato, nao a ordem fisica dos CSVs.
M = load(cfg.stage3_best_file, 'Stage3Contract');
rvNames = cellstr(string(M.Stage3Contract.mandatory_rv_names(:))');
assert(all(ismember(rvNames, names)), 'B4:InvalidSimulationRVs', 'RVs ausentes.');
xiRow = local_empty_row(T.xi, id);
xiRow{1,T.xiNames} = xi;
xiFile = fullfile(attemptDir, 'xi.csv');
writetable(xiRow, xiFile);
rvFiles = cell(1,2);
keys = {'material','liner'};
for j = 1:2
    row = local_empty_row(T.(keys{j}), id);
    present = ismember(rvNames, row.Properties.VariableNames);
    row{1,rvNames(present)} = rv(present);
    rvFiles{j} = fullfile(attemptDir, [keys{j}, '_rv.csv']);
    writetable(row, rvFiles{j});
end
if cfg.stage4_execute_rs2
    resultFile = fullfile(attemptDir, 'rs2_results.csv');
    tokens = {'{xi_file}','{material_rv_file}','{liner_rv_file}', ...
        '{field_file}','{results_file}','{model_file}','{sim_id}','{expected_stage}'};
    values = {xiFile,rvFiles{1},rvFiles{2},field,resultFile, ...
        cfg.stage4_base_model_file,num2str(id),num2str(cfg.rs2_expected_stage)};
    args = cellstr(string(cfg.stage4_python_args));
    assert(~isempty(args), 'B4:MissingPythonArguments', 'Configure stage4_python_args.');
    for j = 1:numel(args)
        for k = 1:numel(tokens)
            args{j} = strrep(args{j}, tokens{k}, values{k});
        end
    end
    [exitCode, log] = local_python_process( ...
        [{cfg.python_exe,cfg.batch_script}, args(:)'], ...
        cfg.work_dir, fullfile(attemptDir, 'python.log'));
    assert(exitCode == 0, 'B4:PythonFailed', 'Python/RS2 falhou (%d): %s', exitCode, log);
else
    resultFile = cfg.simulation_results_file;
end
assert(isfile(resultFile), 'B4:MissingRS2Result', 'Resultado RS2 ausente: %s.', resultFile);
R = readtable(resultFile, 'VariableNamingRule', 'preserve');
idColumn = local_id_column(R);
rows = find(double(R.(idColumn)) == id);
assert(numel(rows) == 1, 'B4:InvalidRS2ResultID', ...
    'Resultado deve conter exatamente uma linha para ID %d.', id);
resultRow = R(rows,:);
assert(ismember(cfg.stage4_result_displacement_column, R.Properties.VariableNames), ...
    'B4:MissingRS2Displacement', 'Coluna de deslocamento ausente no resultado RS2.');
if ismember('Status', R.Properties.VariableNames)
    assert(any(strcmpi(string(resultRow.Status), ["OK","SUCCESS","COMPLETED"])), ...
        'B4:RS2InvalidStatus', 'Status RS2 indica falha.');
end
if ismember('Stage', R.Properties.VariableNames)
    assert(resultRow.Stage == cfg.rs2_expected_stage, 'B4:WrongRS2Stage', ...
        'Resultado RS2 pertence a outro stage.');
end
observed = double(resultRow.(cfg.stage4_result_displacement_column));
validateattributes(observed, {'numeric'}, {'scalar','real','finite','nonnegative'});
end

function [exitCode, log] = local_python_process(argv, workDir, logFile)
% ProcessBuilder passa argumentos literais, inclusive espacos e % no FEZ.
javaArgs = javaObject('java.util.ArrayList');
for j = 1:numel(argv)
    value = char(string(argv{j}));
    assert(isrow(value) && ~any(value == char(0)), ...
        'B4:InvalidProcessArgument', 'Argumento Python invalido.');
    javaArgs.add(javaObject('java.lang.String', value));
end
builder = javaObject('java.lang.ProcessBuilder', javaArgs);
builder.directory(javaObject('java.io.File', workDir));
builder.redirectErrorStream(true);
builder.redirectOutput(javaObject('java.io.File', logFile));
process = builder.start();
exitCode = process.waitFor();
log = fileread(logFile);
end
