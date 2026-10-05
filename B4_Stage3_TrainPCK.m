function B4_Stage3_TrainPCK(cfg)
% PCK em entradas fisicas: 18 RVs obrigatorios + Xi selecionados.
% CORREÇÃO #2: Normalização de entradas antes de PCE
% CORREÇÃO #8: Validação cruzada k-fold obrigatória + rejeita LOO=NaN
%
% Versão Normalizada: Entradas standardizadas antes de PCE para estabilidade numérica.

fprintf('\n[Etapa3] Treinamento PCK Xi + 18 RVs (NORMALIZADO)...\n');

assert(~isempty(which('uqlab')), 'Stage3: UQLab nao encontrado.');
uqlab('-nosplash');

assert(strcmpi(cfg.stage3_marginal_mode, 'estimated'), ...
    ['Stage3: use stage3_marginal_mode=''estimated'' para este arquivo. ', ...
     'O modo standard nao pode ser aplicado aos RVs fisicos.']);

validateattributes(cfg.stage3_nvars_train, {'numeric'}, ...
    {'scalar','integer','>=',18});

S = load(fullfile(cfg.out_dir, 'stage2_selection.mat'));

X_sel = double(S.X_sel);
vars_sel = string(S.vars_sel(:))';
y = double(S.y(:));
Xi = S.Xi;
RV = S.RV;
sampleID = double(S.sampleID(:));
rvNames = string(S.rvNames(:))';
Stage0Contract = S.Stage0Contract;

[found, rvLoc] = ismember(rvNames, vars_sel);
assert(all(found) && numel(rvLoc) == 18, ...
    'Stage3: algum RV obrigatorio foi removido.');

xiLoc = find(startsWith(vars_sel, "xi_"));

% Limite total de treinamento: RVs + Xi.
nXiTrain = min(cfg.stage3_nvars_train - 18, numel(xiLoc));
trainLoc = [rvLoc(:)', xiLoc(1:nXiTrain)];

Xtr = X_sel(:, trainLoc);
vars_train = vars_sel(trainLoc);
n = size(Xtr, 2);

assert(size(Xtr,1) == numel(y) && numel(y) == numel(sampleID), ...
    'Stage3: tamanhos de entradas, respostas e IDs diferentes.');
assert(numel(unique(sampleID)) == numel(sampleID), ...
    'Stage3: IDs duplicados.');
assert(all(isfinite(Xtr(:))) && all(isfinite(y)), ...
    'Stage3: dados nao finitos.');

%% NOVO PASSO 0: Calcular estatísticas de normalização
fprintf('[Etapa3] Calculando estatisticas de normalizacao...\n');

muX_original = mean(Xtr, 1);
sdX_original = std(Xtr, 0, 1);

assert(all(isfinite(sdX_original)) && all(sdX_original > 0), ...
    'Stage3: entrada selecionada constante ou invalida.');

muY_original = mean(y);
sdY_original = std(y);

assert(isfinite(sdY_original) && sdY_original > 0, ...
    'Stage3: resposta constante ou invalida.');

fprintf('[Etapa3] Escalas de entrada (originais):\n');
for j = 1:n
    fprintf('  %s: μ=%.4e, σ=%.4e\n', ...
        vars_train(j), muX_original(j), sdX_original(j));
end
fprintf('[Etapa3] Escala de resposta: μ=%.4e, σ=%.4e\n', muY_original, sdY_original);

%% PASSO 1: Normalizar (standardizar) entradas e resposta
Xtr_scaled = (Xtr - muX_original) ./ sdX_original;
yN = (y - muY_original) / sdY_original;

assert(all(isfinite(Xtr_scaled(:))), ...
    'Stage3: normalizacao produziu NaN ou Inf em X.');
assert(all(isfinite(yN)), ...
    'Stage3: normalizacao produziu NaN ou Inf em y.');

fprintf('[Etapa3] Normalizacao concluida: dados em escala [~0, ~1]\n');

%% PASSO 2: Definir marginais Gaussianas em escala NORMALIZADA
InputOpts = struct();

for j = 1:n
    mu_norm = mean(Xtr_scaled(:, j));
    sd_norm = std(Xtr_scaled(:, j));
    
    InputOpts.Marginals(j).Type = 'Gaussian';
    InputOpts.Marginals(j).Moments = [mu_norm, sd_norm];
    InputOpts.Marginals(j).Name = char(vars_train(j));
end

inputModel = uq_createInput(InputOpts);

fprintf('[Etapa3] Input model criado com marginais Gaussianas (dados normalizados)\n');

%% PASSO 3: PCE com validação cruzada k-fold
Meta = struct();
Meta.Type = 'Metamodel';
Meta.MetaType = 'PCK';
Meta.Input = inputModel;
Meta.ExpDesign.X = Xtr_scaled;  % DADOS NORMALIZADOS
Meta.ExpDesign.Y = yN;           % RESPOSTA NORMALIZADA
Meta.PCE.Method = 'LARS';
Meta.PCE.Degree = 1:3;
Meta.PCE.TruncOptions.qNorm = 0.85:0.05:1.0;

% Configurar validação cruzada k-fold
nsamples = size(Xtr_scaled, 1);
nfolds = min(10, max(5, floor(nsamples / 10)));
Meta.CV.Type = 'Kfold';
Meta.CV.NumFolds = nfolds;

fprintf('[Etapa3] Treinando PCE com %d-fold CV...\n', nfolds);
fprintf('[Etapa3] Dados normalizados: 18 RVs + %d Xi = %d variaveis, %d amostras\n', ...
    nXiTrain, n, nsamples);

modelPCK = uq_createModel(Meta);

fprintf('[Etapa3] PCE treinado\n');

%% PASSO 4: Avaliar em dados NORMALIZADOS e DESNORMALIZAR para métricas
yhatN = uq_evalModel(modelPCK, Xtr_scaled);
yhat = double(yhatN(:)) * sdY_original + muY_original;  % Desnormalizar

assert(numel(yhat) == numel(y) && all(isfinite(yhat)), ...
    'Stage3: previsoes de treinamento invalidas.');

R2_train = 1 - sum((y - yhat).^2) / sum((y - mean(y)).^2);

%% PASSO 5: Extrair LOO e R² de validação cruzada
LOO = NaN;
R2_cv = NaN;

try
    if isstruct(modelPCK)
        if isfield(modelPCK, 'Error') && isfield(modelPCK.Error, 'LOO')
            LOO = double(modelPCK.Error.LOO);
        end
        if isfield(modelPCK, 'Error') && isfield(modelPCK.Error, 'CV_Rsquared')
            R2_cv = double(modelPCK.Error.CV_Rsquared);
        elseif isfield(modelPCK, 'MetaError') && isfield(modelPCK.MetaError, 'CV_Rsquared')
            R2_cv = double(modelPCK.MetaError.CV_Rsquared);
        end
    end
catch
    % Silencia erro de acesso se campo não existe
end

%% PASSO 6: VALIDAÇÃO CRÍTICA - Rejeitar se LOO ou CV_R² não disponível
fprintf('[Etapa3] Metricas de validacao:\n');
fprintf('  R2 treino: %.6f\n', R2_train);
fprintf('  R2 CV:     %.6f\n', R2_cv);
fprintf('  LOO:       %.6e\n', LOO);

assert(isfinite(LOO), ...
    'Stage3: LOO nao calculado ou nao-finito; impossivel validar modelo. Confira versao UQLab.');

assert(isfinite(R2_cv), ...
    'Stage3: R2_cv nao calculado ou nao-finito; CV falhou. Confira dados e parametros.');

%% PASSO 7: Alertar se overfitting detectado
delta_R2 = R2_train - R2_cv;
if delta_R2 > 0.15
    warning('B4:OverfittingDetected', ...
        '[Stage3] Overfitting detectado: ΔR² = %.4f (treino-CV). Modelo pode estar em regime nao-confiavel.', ...
        delta_R2);
end

if R2_cv < 0.50
    warning('B4:PoorGeneralization', ...
        '[Stage3] R2_cv = %.6f < 0.50; modelo generaliza pobremente. Revisar seleção de variaveis.', ...
        R2_cv);
end

Perf = table("PCK","OK",R2_train,R2_cv,LOO,n,size(Xtr,1),18,nXiTrain, ...
    'VariableNames', {'Method','Status','R2_Train','R2_CV','LOO', ...
    'NVars','NSamples','NRV','NXi'});

writetable(Perf, fullfile(cfg.out_dir, 'stage3_perf.csv'));

%% Contrato: Registrar normalização
Stage3Contract = struct();
Stage3Contract.version = 'XiPlus18RV_Selected_Physical_v2_NORMALIZED';
Stage3Contract.limit_state = 'g = lim - displacement';
Stage3Contract.lim_m = cfg.recalque_lim;
Stage3Contract.nvars_train = n;

Stage3Contract.xi_count = nXiTrain;
Stage3Contract.rv_count = 18;
Stage3Contract.full_xi_count = size(Xi, 2);
Stage3Contract.input_names = vars_train;
Stage3Contract.mandatory_rv_names = rvNames;

%% NOVO: Armazenar estatísticas de normalização
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

parentDir = fileparts(cfg.stage3_best_file);
if ~isempty(parentDir) && ~isfolder(parentDir)
    mkdir(parentDir);
end

%% Salvar com estatísticas de normalização
save(cfg.stage3_best_file, ...
    'modelPCK','inputModel','vars_train','Xtr','y', ...
    'muX_original','sdX_original','muY_original','sdY_original', ...
    'Xtr_scaled','yN', ...
    'sampleID','Xi','RV', ...
    'Perf','cfg','Stage0Contract','Stage3Contract','-v7.3');

fprintf('[Etapa3] R2 treino=%.6f | R2_CV=%.6f | LOO=%.6e | RV=18 | Xi=%d.\n', ...
    R2_train, R2_cv, LOO, nXiTrain);
fprintf('[Etapa3] Modelo normalizado salvo com contratos.\n');
end