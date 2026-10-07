function B4_Stage3_TrainPCK(cfg)
% =========================================================================
% B4_Stage3_TrainPCK - Treinamento PC-Kriging Normalizado
%
% FUNÇÃO:
%   Treina metamodelo PC-Kriging usando 18 RVs obrigatorios + Xi selecionados
%   Entrada: dados normalizados (Z-score) para estabilidade numerica
%   Saida: modelo com estatisticas de normalizacao para denormalizacao posterior
%
% CORREÇÕES IMPLEMENTADAS (v7):
%   CORREÇÃO #1: Validacao rigorosa de LOO e R2_CV (rejeita NaN)
%   CORREÇÃO #2: Normalizacao de entradas ANTES de PCE (estabilidade)
%   CORREÇÃO #3: Armazenamento de estatisticas de normalizacao no contrato
%   CORREÇÃO #5: Estimacao de Pf com populacao LHS FIXA se AL_USE_Pf_STABILITY=true
%   CORREÇÃO #7: Sincronizacao de 18 RVs obrigatorios ao final
%
% USO:
%   B4_Stage3_TrainPCK(cfg);  % cfg = B4_DefaultConfig()
%
% =========================================================================

fprintf('\n[Etapa3] ====== PC-Kriging Normalizado - Versao v7 ======\n');
fprintf('[Etapa3] Treinamento com 18 RVs obrigatorios + Xi selecionados...\n');

%% =========================================================================
% VALIDACOES INICIAIS
%% =========================================================================

% Verificar UQLab
assert(~isempty(which('uqlab')), ...
    'Stage3: UQLab nao encontrado. Instale ou adicione ao path.');

% Inicializar UQLab (silencioso)
uqlab('-nosplash');

% Validar modo de marginais
assert(strcmpi(cfg.stage3_marginal_mode, 'estimated'), ...
    ['Stage3: use stage3_marginal_mode=''estimated'' para este arquivo. ', ...
     'O modo standard nao pode ser aplicado aos RVs fisicos.']);

% Validar parametro de numero de variaveis
validateattributes(cfg.stage3_nvars_train, {'numeric'}, ...
    {'scalar','integer','>=',18});

%% =========================================================================
% CARREGAR DADOS DE STAGE 2
%% =========================================================================

fprintf('[Etapa3] Carregando dados de Stage 2...\n');

S = load(fullfile(cfg.out_dir, 'stage2_selection.mat'));

X_sel = double(S.X_sel);
vars_sel = string(S.vars_sel(:))';
y = double(S.y(:));
Xi = S.Xi;
RV = S.RV;
sampleID = double(S.sampleID(:));
rvNames = string(S.rvNames(:))';
Stage0Contract = S.Stage0Contract;

%% =========================================================================
% VALIDACAO: 18 RVs OBRIGATORIOS PRESENTES
%% =========================================================================

[found, rvLoc] = ismember(rvNames, vars_sel);
assert(all(found) && numel(rvLoc) == 18, ...
    'Stage3: algum RV obrigatorio foi removido em Stage 2.');

fprintf('[Etapa3] 18 RVs obrigatorios confirmados em vars_sel.\n');

%% =========================================================================
% SELECIONAR VARIAVEIS PARA TREINAMENTO
%% =========================================================================

% Encontrar indices de Xi (variaveis que começam com "xi_")
xiLoc = find(startsWith(vars_sel, "xi_"));

% Limitar a stage3_nvars_train total (18 RVs + resto Xi)
nXiTrain = min(cfg.stage3_nvars_train - 18, numel(xiLoc));
trainLoc = [rvLoc(:)', xiLoc(1:nXiTrain)];

% Extrair dados de treinamento
Xtr = X_sel(:, trainLoc);
vars_train = vars_sel(trainLoc);
n = size(Xtr, 2);

fprintf('[Etapa3] Variaveis de treinamento: %d total (18 RVs + %d Xi).\n', n, nXiTrain);

%% =========================================================================
% VALIDACOES DE DADOS
%% =========================================================================

% Compatibilidade de tamanhos
assert(size(Xtr,1) == numel(y) && numel(y) == numel(sampleID), ...
    'Stage3: tamanhos de entradas, respostas e IDs diferentes.');

% IDs unicos
assert(numel(unique(sampleID)) == numel(sampleID), ...
    'Stage3: IDs duplicados detectados.');

% Dados finitos
assert(all(isfinite(Xtr(:))) && all(isfinite(y)), ...
    'Stage3: dados nao finitos detectados.');

fprintf('[Etapa3] Validacoes de dados: OK (%d amostras, %d variaveis).\n', ...
    size(Xtr,1), n);

%% =========================================================================
% PASSO 1: CALCULAR ESTATISTICAS DE NORMALIZACAO
%% =========================================================================

fprintf('[Etapa3] Passo 1: Calculando estatisticas de normalizacao...\n');

% Media e desvio padrao ORIGINAIS (antes de normalizar)
muX_original = mean(Xtr, 1);
sdX_original = std(Xtr, 0, 1);

% Validacoes
assert(all(isfinite(sdX_original)) && all(sdX_original > 0), ...
    'Stage3: entrada selecionada constante ou invalida (std=0).');

muY_original = mean(y);
sdY_original = std(y);

assert(isfinite(sdY_original) && sdY_original > 0, ...
    'Stage3: resposta constante ou invalida (std=0).');

% Log das escalas
fprintf('[Etapa3] Escalas de entrada ORIGINAIS:\n');
for j = 1:n
    fprintf('  %s: μ=%.4e, σ=%.4e\n', ...
        vars_train(j), muX_original(j), sdX_original(j));
end
fprintf('[Etapa3] Escala de resposta ORIGINAL: μ=%.4e, σ=%.4e\n', ...
    muY_original, sdY_original);

%% =========================================================================
% PASSO 2: NORMALIZAR (STANDARDIZAR) ENTRADAS E RESPOSTA
%% =========================================================================

fprintf('[Etapa3] Passo 2: Normalizando dados (Z-score)...\n');

% Z-score: (X - mu) / sigma
Xtr_scaled = (Xtr - muX_original) ./ sdX_original;
yN = (y - muY_original) / sdY_original;

% Validacoes apos normalizacao
assert(all(isfinite(Xtr_scaled(:))), ...
    'Stage3: normalizacao produziu NaN ou Inf em X.');
assert(all(isfinite(yN)), ...
    'Stage3: normalizacao produziu NaN ou Inf em y.');

fprintf('[Etapa3] Normalizacao concluida: dados em escala [~0, ~1].\n');

%% =========================================================================
% PASSO 3: DEFINIR MARGINAIS GAUSSIANAS EM ESCALA NORMALIZADA
%% =========================================================================

fprintf('[Etapa3] Passo 3: Criando Input Model com marginais Gaussianas...\n');

InputOpts = struct();

for j = 1:n
    % Calcular media e std dos dados JA NORMALIZADOS
    mu_norm = mean(Xtr_scaled(:, j));
    sd_norm = std(Xtr_scaled(:, j));
    
    % Definir marginal Gaussiana
    InputOpts.Marginals(j).Type = 'Gaussian';
    InputOpts.Marginals(j).Moments = [mu_norm, sd_norm];
    InputOpts.Marginals(j).Name = char(vars_train(j));
end

% Criar modelo de entrada UQLab
inputModel = uq_createInput(InputOpts);

fprintf('[Etapa3] Input model criado com %d marginais Gaussianas.\n', n);

%% =========================================================================
% PASSO 4: CONFIGURAR PC-KRIGING COM VALIDACAO CRUZADA K-FOLD
%% =========================================================================

fprintf('[Etapa3] Passo 4: Configurando PC-Kriging...\n');

Meta = struct();
Meta.Type = 'Metamodel';
Meta.MetaType = 'PCK';
Meta.Input = inputModel;

% DADOS NORMALIZADOS para treinamento
Meta.ExpDesign.X = Xtr_scaled;  % Entrada normalizada
Meta.ExpDesign.Y = yN;           % Resposta normalizada

% PCE: LARS com graus 1, 2, 3
Meta.PCE.Method = 'LARS';
Meta.PCE.Degree = cfg.stage3_pce_degree;  % [1 2 3]
Meta.PCE.TruncOptions.qNorm = cfg.stage3_pce_qnorm;  % [0.85:0.05:1.0]

% Validacao cruzada K-FOLD (obrigatoria)
nsamples = size(Xtr_scaled, 1);
nfolds = min(cfg.cv_fold_count_max, ...
    max(cfg.cv_fold_count_min, floor(nsamples / 10)));

Meta.CV.Type = 'Kfold';
Meta.CV.NumFolds = nfolds;

fprintf('[Etapa3] Configuracao: LARS, graus [1 2 3], qNorm [0.85:0.05:1.0]\n');
fprintf('[Etapa3] Validacao cruzada: %d-fold\n', nfolds);
fprintf('[Etapa3] Dados: %d amostras normalizadas, %d variaveis\n', ...
    nsamples, n);

%% =========================================================================
% PASSO 5: TREINAR MODELO PCE
%% =========================================================================

fprintf('[Etapa3] Passo 5: Treinando modelo PCE...\n');

modelPCK = uq_createModel(Meta);

fprintf('[Etapa3] Modelo PCE treinado com sucesso.\n');

%% =========================================================================
% PASSO 6: AVALIAR DESEMPENHO EM DADOS NORMALIZADOS
%% =========================================================================

fprintf('[Etapa3] Passo 6: Avaliando desempenho do modelo...\n');

% Predicoes EM ESCALA NORMALIZADA
yhatN = uq_evalModel(modelPCK, Xtr_scaled);

% Desnormalizar para calcular metricas EM ESCALA ORIGINAL
yhat = double(yhatN(:)) * sdY_original + muY_original;

assert(numel(yhat) == numel(y) && all(isfinite(yhat)), ...
    'Stage3: previsoes de treinamento invalidas.');

% R² em escala original
R2_train = 1 - sum((y - yhat).^2) / sum((y - mean(y)).^2);

fprintf('[Etapa3] R² de treinamento (escala original): %.6f\n', R2_train);

%% =========================================================================
% PASSO 7: EXTRAIR LOO E R² DE VALIDACAO CRUZADA (CRITICO)
%% =========================================================================

fprintf('[Etapa3] Passo 7: Extraindo metricas de validacao cruzada...\n');

LOO = NaN;
R2_cv = NaN;

try
    if isstruct(modelPCK)
        % Tentar extrair LOO
        if isfield(modelPCK, 'Error') && isfield(modelPCK.Error, 'LOO')
            LOO = double(modelPCK.Error.LOO);
        end
        
        % Tentar extrair R2_cv
        if isfield(modelPCK, 'Error') && isfield(modelPCK.Error, 'CV_Rsquared')
            R2_cv = double(modelPCK.Error.CV_Rsquared);
        elseif isfield(modelPCK, 'MetaError') && isfield(modelPCK.MetaError, 'CV_Rsquared')
            R2_cv = double(modelPCK.MetaError.CV_Rsquared);
        end
    end
catch ME
    fprintf('[Etapa3] Aviso: erro ao extrair metricas CV: %s\n', ME.message);
end

%% =========================================================================
% PASSO 8: VALIDACAO CRITICA - REJEITAR SE LOO OU CV_R² NAO DISPONIVEL
%% =========================================================================

fprintf('[Etapa3] Passo 8: Validacoes criticas de modelo...\n');
fprintf('[Etapa3] Metricas de validacao:\n');
fprintf('  R2 treino: %.6f\n', R2_train);
fprintf('  R2 CV:     %.6f\n', R2_cv);
fprintf('  LOO:       %.6e\n', LOO);

% CRITICO: LOO deve estar disponivel
assert(isfinite(LOO), ...
    ['Stage3: LOO nao calculado ou nao-finito; impossivel validar modelo. ', ...
     'Confira versao UQLab ou aumente nsamples.']);

% CRITICO: R2_cv deve estar disponivel
assert(isfinite(R2_cv), ...
    ['Stage3: R2_cv nao calculado ou nao-finito; CV falhou. ', ...
     'Confira dados e parametros.']);

fprintf('[Etapa3] Validacoes criticas: PASSED ✓\n');

%% =========================================================================
% PASSO 9: ALERTAS DE OVERFITTING E GENERALIZACAO
%% =========================================================================

fprintf('[Etapa3] Passo 9: Verificando qualidade de generalizacao...\n');

% Overfitting: gap entre treino e CV
delta_R2 = R2_train - R2_cv;

if delta_R2 > cfg.stage3_overfit_r2_gap
    warning('B4:OverfittingDetected', ...
        ['[Stage3] Overfitting detectado: ΔR² = %.4f (treino-CV > %.4f). ', ...
         'Modelo pode estar em regime nao-confiavel.'], ...
        delta_R2, cfg.stage3_overfit_r2_gap);
end

% Generalizacao pobre
if R2_cv < cfg.stage3_min_r2_cv
    warning('B4:PoorGeneralization', ...
        ['[Stage3] R2_cv = %.6f < %.6f; modelo generaliza pobremente. ', ...
         'Revisar selecao de variaveis ou aumentar nsamples.'], ...
        R2_cv, cfg.stage3_min_r2_cv);
end

%% =========================================================================
% PASSO 10: SALVAR METRICAS DE DESEMPENHO
%% =========================================================================

fprintf('[Etapa3] Passo 10: Salvando metricas de desempenho...\n');

Perf = table("PCK","OK",R2_train,R2_cv,LOO,n,size(Xtr,1),18,nXiTrain, ...
    'VariableNames', {'Method','Status','R2_Train','R2_CV','LOO', ...
    'NVars','NSamples','NRV','NXi'});

writetable(Perf, fullfile(cfg.out_dir, 'stage3_perf.csv'));

fprintf('[Etapa3] Metricas salvos em stage3_perf.csv\n');

%% =========================================================================
% PASSO 11: ESTIMACAO DE Pf COM POPULACAO LHS FIXA (NOVO - CORREÇÃO #5)
%% =========================================================================

if isfield(cfg, 'AL_USE_Pf_STABILITY') && cfg.AL_USE_Pf_STABILITY
    fprintf('[Etapa3] Passo 11: Estimando Pf inicial com populacao LHS FIXA...\n');
    
    % Gerar populacao LHS FIXA em espaco normalizado
    rng(double(cfg.seed), 'twister');
    
    nPop = cfg.AL_Pf_population_size;
    XpopN = lhsdesign(nPop, n);
    
    % Mapear para distribuicao Gaussiana normalizada
    % Q = muZ + sigZ * norminv(u)
    for j = 1:n
        mu_norm = mean(Xtr_scaled(:, j));
        sd_norm = std(Xtr_scaled(:, j));
        XpopN(:, j) = mu_norm + sd_norm * norminv(XpopN(:, j));
    end
    
    % Avaliar no modelo normalizado
    YpopN = uq_evalModel(modelPCK, XpopN);
    
    % Desnormalizar
    Ypop = double(YpopN(:)) * sdY_original + muY_original;
    
    % Calcular estado limite: g = recalque_lim - y
    g_pop = cfg.recalque_lim - Ypop;
    
    % Estimativas pontuais
    Pf_estimate = mean(g_pop <= 0);
    
    % Faixa de Pf com k*sigma (CORREÇÃO: sinais CORRETOS)
    % Pf_low = pessimista (mais falha)  = P(g - k*sigma <= 0)
    % Pf_high = otimista (menos falha)  = P(g + k*sigma <= 0)
    Ypop_std_est = std(Ypop);
    kfactor = cfg.AL_Pf_k_factor;
    
    Pf_low = mean(g_pop - kfactor .* Ypop_std_est <= 0);   % pessimista
    Pf_high = mean(g_pop + kfactor .* Ypop_std_est <= 0);  % otimista
    
    % Validacao: faixa de Pf monotonico (pessimista >= otimista)
    assert((Pf_low >= Pf_high || Pf_low == Pf_high), ...
        ['Stage3: faixa de Pf nao-monotonica: low=%.6f, est=%.6f, high=%.6f', ...
         ' (esperado: high <= est <= low)'], ...
        Pf_high, Pf_estimate, Pf_low);
    
    % Armazenar para Stage 4
    Pf_population = struct();
    Pf_population.is_fixed = true;
    Pf_population.X = XpopN;
    Pf_population.Y_normalized = YpopN;
    Pf_population.Y = Ypop;
    Pf_population.g = g_pop;
    Pf_population.size = nPop;
    Pf_population.seed = cfg.seed;
    Pf_population.Pf_estimate = Pf_estimate;
    Pf_population.Pf_low = Pf_low;
    Pf_population.Pf_high = Pf_high;
    Pf_population.Pf_width_rel = (Pf_low - Pf_high) / max(Pf_estimate, cfg.AL_Pf_floor);
    Pf_population.k_factor = kfactor;
    Pf_population.description = ...
        sprintf('LHS %d amostras, k=%.1f, range [%.6f, %.6f], est %.6f', ...
        nPop, kfactor, Pf_high, Pf_low, Pf_estimate);
    
    fprintf('[Etapa3] Pf_estimate = %.6f\n', Pf_estimate);
    fprintf('[Etapa3] Pf_low (pessimista) = %.6f\n', Pf_low);
    fprintf('[Etapa3] Pf_high (otimista) = %.6f\n', Pf_high);
    fprintf('[Etapa3] Pf_width_rel = %.4f\n', Pf_population.Pf_width_rel);
    fprintf('[Etapa3] Populacao Pf marcada como FIXA para Stage 4.\n');
else
    fprintf('[Etapa3] Passo 11: Estimacao de Pf desativada (AL_USE_Pf_STABILITY=false).\n');
    Pf_population = [];
end

%% =========================================================================
% PASSO 12: CONTRATO DE STAGE 3
%% =========================================================================

fprintf('[Etapa3] Passo 12: Criando contrato de Stage 3...\n');

Stage3Contract = struct();
Stage3Contract.version = 'XiPlus18RV_Selected_Physical_Normalized_v7';
Stage3Contract.limit_state = 'g = recalque_lim - displacement';
Stage3Contract.lim_m = cfg.recalque_lim;
Stage3Contract.nvars_train = n;

Stage3Contract.xi_count = nXiTrain;
Stage3Contract.rv_count = 18;
Stage3Contract.full_xi_count = size(Xi, 2);
Stage3Contract.input_names = vars_train;
Stage3Contract.mandatory_rv_names = rvNames;

% NOVO: Armazenar estatisticas de normalizacao (CORREÇÃO #3)
Stage3Contract.input_normalization = 'standardization';
Stage3Contract.input_mu = muX_original;
Stage3Contract.input_sigma = sdX_original;
Stage3Contract.output_mu = muY_original;
Stage3Contract.output_sigma = sdY_original;

Stage3Contract.input_representation = 'physical';
Stage3Contract.model_input_representation = 'standardized';
Stage3Contract.external_input_transform = '(X - muX) ./ sdX';
Stage3Contract.cv_scope = 'conditional_on_selected_variables';
Stage3Contract.probabilistic_mode = ...
    'Gaussian_moments_estimated_training_approximation_NORMALIZED';
Stage3Contract.valid_for_global_pf_sampling = false;

% Garantir que arquivo de saida existe
parentDir = fileparts(cfg.stage3_best_file);
if ~isempty(parentDir) && ~isfolder(parentDir)
    mkdir(parentDir);
end

fprintf('[Etapa3] Contrato criado com normalizacao sincronizada.\n');

%% =========================================================================
% PASSO 13: SALVAR TUDO
%% =========================================================================

fprintf('[Etapa3] Passo 13: Salvando modelo e contratos...\n');

save(cfg.stage3_best_file, ...
    'modelPCK','inputModel','vars_train','Xtr','y', ...
    'muX_original','sdX_original','muY_original','sdY_original', ...
    'Xtr_scaled','yN', ...
    'sampleID','Xi','RV', ...
    'Pf_population', ...
    'Perf','cfg','Stage0Contract','Stage3Contract','-v7.3');

fprintf('[Etapa3] Arquivo stage3_best.mat salvo com sucesso.\n');

%% =========================================================================
% RESUMO FINAL
%% =========================================================================

fprintf('[Etapa3] ====== RESUMO FINAL ======\n');
fprintf('[Etapa3] R2 treino: %.6f\n', R2_train);
fprintf('[Etapa3] R2 CV:     %.6f\n', R2_cv);
fprintf('[Etapa3] LOO:       %.6e\n', LOO);
fprintf('[Etapa3] Variaveis: 18 RVs + %d Xi = %d total\n', nXiTrain, n);
fprintf('[Etapa3] Amostras:  %d\n', size(Xtr, 1));
fprintf('[Etapa3] Normalizacao: Ativada (Z-score, media μ, std σ)\n');
if ~isempty(Pf_population)
    fprintf('[Etapa3] Pf_population: OK (Pf=%.6f, width=%.4f)\n', ...
        Pf_population.Pf_estimate, Pf_population.Pf_width_rel);
end
fprintf('[Etapa3] Status: ✓ SUCESSO\n');
fprintf('[Etapa3] =========================\n\n');

end
