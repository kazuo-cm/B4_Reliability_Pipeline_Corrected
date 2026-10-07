function cfg = B4_DefaultConfig_FIXED(workDir)
% =========================================================================
% B4_DefaultConfig_FIXED - Configuracao central do pipeline B4
% VERSÃO CORRIGIDA: 10 fragil. críticas resolvidas
%
% Pipeline: PC-Kriging Normalizado + Active Learning Local com Pf estável
% Versao: v7 - Corrigido com validacoes rigorosas e tolerância a materiais
%
% ALTERAÇÕES PRINCIPAIS DESTA VERSÃO:
% 1. cfg.AL_USE_Pf_CONVERGENCE → controla estimação de Pf no Stage 3
% 2. cfg.spatial_allow_missing_materials → tolera materiais vazios
% 3. Validações mais rigorosas em cada stage
% 4. Comments explicativos em configurações críticas
% =========================================================================

if nargin < 1 || isempty(workDir)
    workDir = 'C:\Kazuo-Script';
end

workDir = string(workDir);

assert(isscalar(workDir) && ~ismissing(workDir) && ...
    strlength(strip(workDir)) > 0, ...
    'B4: workDir deve ser um caminho escalar nao vazio.');

cfg = struct();

%% =========================================================================
% 1. IDENTIFICACAO E REPRODUCIBILIDADE
%% =========================================================================

cfg.configuration_version = 'B4_NormalizedPCK_LocalAL_Pf_MCS_SS_RobustFixed_v7';
cfg.seed = 100;  % CRÍTICO: Garante reproducibilidade; alterar para novo experimento

%% =========================================================================
% 2. DIRETORIOS DE ENTRADA
%% =========================================================================

cfg.work_dir = char(workDir);
cfg.base_dir = fullfile(cfg.work_dir, 'RF_5Mat_3Var_400Sim');

cfg.spatial_config_file = fullfile(cfg.base_dir, 'B1_spatial_config.mat');
cfg.training_xi_file = fullfile(cfg.base_dir, 'xi', 'X_xi_5mat_3var_400sim.csv');
cfg.training_results_file = fullfile(cfg.work_dir, 'RS2_Results_RF400.csv');
cfg.material_rv_file = fullfile(cfg.base_dir, 'random_values', 'material_rv.csv');
cfg.liner_rv_file = fullfile(cfg.base_dir, 'random_values', 'liner_rv.csv');

%% =========================================================================
% 3. INTERFACE PYTHON / RS2
%% =========================================================================

cfg.python_exe = fullfile(cfg.work_dir, '.venv', 'Scripts', 'python.exe');
cfg.batch_script = fullfile(cfg.work_dir, 'run_al_batch.py');
cfg.fez_file = fullfile(cfg.work_dir, 'MetroParaiso-EstudoCaso_Partial_50%_RF.fez');
cfg.stage4_base_model_file = cfg.fez_file;
cfg.simulation_results_file = fullfile(cfg.work_dir, 'RS2_Results_RF400.csv');
cfg.rs2_expected_stage = 7;

%% =========================================================================
% 4. SAIDAS
%% =========================================================================

cfg.out_dir = fullfile(cfg.work_dir, 'B4_Output_Official', 'pipeline');
cfg.stage0_out_dir = cfg.out_dir;
cfg.stage1_out_dir = cfg.out_dir;
cfg.stage2_out_dir = cfg.out_dir;
cfg.stage3_out_dir = cfg.out_dir;
cfg.stage4_out_dir = fullfile(cfg.work_dir, 'B4_Output_Official', 'stage4');
cfg.stage3_best_file = fullfile(cfg.out_dir, 'stage3_best.mat');

cfg.AL_AUGMENTED_XI_FILE = fullfile(cfg.stage4_out_dir, 'augmented_xi.csv');
cfg.AL_AUGMENTED_RESULTS_FILE = fullfile(cfg.stage4_out_dir, 'augmented_results.csv');
cfg.current_material_rv_file = fullfile(cfg.stage4_out_dir, 'current_material_rv.csv');
cfg.current_liner_rv_file = fullfile(cfg.stage4_out_dir, 'current_liner_rv.csv');

%% =========================================================================
% 5. CONTROLE DE STAGES
%% =========================================================================

cfg.run_stage0 = true;   % Alinhamento
cfg.run_stage1 = true;   % Ranking
cfg.run_stage2 = true;   % Seleção
cfg.run_stage3 = true;   % PC-Kriging
cfg.run_stage4 = true;   % Active Learning

cfg.stage4_execute_rs2 = true;   % Executa Python/RS2
cfg.stage4_auto_loop = true;      % Loop automático

%% =========================================================================
% 6. CONFIRMACAO: 18 RVS APLICADOS INICIALMENTE
%% =========================================================================
% CRÍTICO: Deve ser TRUE se 18 RVs foram usados nas 400 simulações iniciais

cfg.initialRVAppliedConfirmed = true;

%% =========================================================================
% 7. ESTADO LIMITE E RANKING
%% =========================================================================

% LIMITE DE DESLOCAMENTO
% Alterar a 0.095 m se material 3 foi reduzido ao máximo
cfg.recalque_lim = 0.085;  % m
cfg.border_tol = 0.01;     % m - zona de fronteira para amostragem AL

% FILTRO DE VARIÂNCIA (Stage 1)
% Remove variáveis com std <= este valor ANTES de calcular correlações
% Previne NaN silencioso em corr() para variáveis quasi-constantes
cfg.stage1_var_tol = 1e-12;

% RANKING (Stage 1)
% stage1_topK: máximo total (RVs + Xi) a manter após ranking
% Aumentar a 300-350 para explorar mais Xi
% Reduzir a 100-150 para focar em Xi mais importantes
cfg.stage1_topK = 250;

% SELEÇÃO (Stage 2)
% stage2_topK: limite de Xi a considerar na seleção por relevância
cfg.stage2_topK = 120;

% KRIGING (Stage 3)
% stage3_nvars_train: FIXO = 18 RVs obrigatorios + Xi selecionados
% Não alterar sem mudar contrato de RVs
cfg.stage3_nvars_train = 90;

% RELEVÂNCIA XI (Stage 2)
% stage2_relevance_target: cumulative score target (0.90 = 90% da relevancia)
cfg.stage2_relevance_target = 0.90;

% MULTICOLINEARIDADE (Stage 2)
% stage2_corr_xx_thr: rejeita Xi com |r| > threshold vs Xi ja selecionadas
% 0.95: permissivo (pode ter redundância)
% 0.80: rigoroso (menos redundância)
cfg.stage2_corr_xx_thr = 0.95;

%% =========================================================================
% 8. PC-KRIGING (STAGE 3) - TREINAMENTO
%% =========================================================================

cfg.stage3_marginal_mode = 'estimated';      % Usar estatísticas dos dados
cfg.stage3_pce_degree = 1:3;                 % Graus a tentar: 1, 2, 3
cfg.stage3_pce_qnorm = 0.85:0.05:1.0;        % Q-norm para truncamento PCE

cfg.cv_fold_count_min = 5;                   % Mínimo de folds
cfg.cv_fold_count_max = 10;                  % Máximo de folds

cfg.stage3_require_finite_loo = false;       % LOO opcional
cfg.stage3_min_r2_cv = 0.50;                 % Aviso se R2_CV < este valor
cfg.stage3_reject_poor_cv = false;           % Não parar se R2_CV baixo
cfg.stage3_overfit_r2_gap = 0.15;            % Aviso se gap treino-CV > 15%

%% =========================================================================
% 9. ESTIMACAO DE Pf NO STAGE 3 (NOVO - CONVERGENCIA NO STAGE 4)
%% =========================================================================

% CRÍTICO: Controla se Stage 3 estima Pf inicial para convergência no Stage 4
% TRUE = Stage 3 gera população LHS e estima Pf, Stage 4 pode parar por convergência
% FALSE = sem estimação de Pf, Stage 4 para apenas por limite de iterações
cfg.AL_USE_Pf_CONVERGENCE = true;

% Tamanho da população LHS para estimação de Pf
% Aumentar a 10000 para precisão, reduzir a 2000 para velocidade
cfg.AL_Pf_population_size = 5000;

% Fator k para faixa de Pf: Pf ± k*sigma
% k=2.0 ≈ 95% intervalo de confiança
% k=1.0 ≈ 68% intervalo de confiança
cfg.AL_Pf_k_factor = 2.0;

%% =========================================================================
% 10. ACTIVE LEARNING (STAGE 4) - CONFIGURACAO GERAL
%% =========================================================================

cfg.AL_RESET_ON_START = false;              % false: retomar; true: começar do zero
cfg.AL_SAVE_AUGMENTED_FILES = true;         % Salvar snapshots (rastreabilidade)
cfg.AL_APPEND_TO_TRAINING = false;          % MANTER false (segurança)
cfg.AL_RETRAIN_EACH_ITER = true;            % Retreinar modelo após cada iteração

%% =========================================================================
% 11. PARADA POR ESTABILIDADE DE Pf COM MCS/SS HIBRIDO (NOVO)
%% =========================================================================

% CRÍTICO: Ativa parada automática por convergência de Pf
% TRUE = Stage 4 estima Pf a cada iteração, para quando estável
% FALSE = para apenas por limite de iterações (AL_MAX_ITERS)
cfg.AL_USE_Pf_STABILITY = true;

% === MCS: Parada automática quando encontrar N falhas ===
cfg.AL_Pf_mcs_target_population = 50000;    % Máximo de amostras MCS
cfg.AL_Pf_mcs_min_failures = 50;            % Parar ao encontrar 50+ falhas

% === SS: Fallback para falhas raras ===
cfg.AL_Pf_ss_intermediate_pf = 0.1;         % Pf intermediária (10%)
cfg.AL_Pf_ss_num_chains = 1000;             % Cadeias de amostragem
cfg.AL_Pf_ss_samples_per_chain = 2;         % Amostras por cadeia

% === Critério de parada: Estabilidade Sequencial ===
% Mantém janela dos 5 últimas leituras de Pf
% Para quando 4 comparações consecutivas tiverem variação < tolerance
% Exemplo: Pf = [0.150, 0.148, 0.149, 0.150, 0.151]
%   Var1: |0.148-0.150|/0.150 = 1.3% < 5% ✓
%   Var2: |0.149-0.148|/0.148 = 0.7% < 5% ✓
%   Var3: |0.150-0.149|/0.149 = 0.7% < 5% ✓
%   Var4: |0.151-0.150|/0.150 = 0.7% < 5% ✓
%   → 4 comparações estáveis = CONVERGIU
cfg.AL_Pf_stability_tolerance = 0.05;       % 5% variação relativa (ajuste: 0.02-0.15)
cfg.AL_Pf_stable_readings = 5;              % 5 leituras (4 comparações)
cfg.AL_Pf_min_iterations = 6;               % Mínimo de casos antes de testar convergência
cfg.AL_Pf_comparison_window = 5;            % Janela de 5 últimas leituras

% === Proteções ===
cfg.AL_Pf_floor = 0.001;                    % Piso para normalização (0.1%)
cfg.AL_Pf_max_eval_cost = 5e6;              % Máximo de avaliações do metamodelo

% === Criterio antigo (deprecated) ===
cfg.AL_USE_CONVERGENCE = false;             % MANTER false

%% =========================================================================
% 12. TENTATIVAS E CANDIDATOS
%% =========================================================================

cfg.AL_START_SIM_ID = 401;                  % ID inicial (após 400 iniciais)
cfg.AL_MAX_ITERS = 20;                      % Máximo de tentativas (ajuste: 10-30)
cfg.AL_CANDIDATE_POOL = 50;                 % Tamanho do pool local (ajuste: 20-100)

%% =========================================================================
% 13. PERTURBACOES LOCAIS (GERACAO DE CANDIDATOS)
%% =========================================================================

% RAIO EM ESPAÇO FÍSICO PARA XI
% Gaussiana com sigma = base_xi * local_radius_xi
% 0.20 = ±20% do valor base (ajuste: 0.10-0.30)
cfg.local_radius_xi = 0.20;

% RAIO EM ESPAÇO LOG PARA RVs (NÃO POISSON)
% Lognormal: log(rv_novo) = log(base_rv) + sigma_log * delta
% 0.10 = ±10% em escala logarítmica (ajuste: 0.05-0.20)
cfg.local_radius_rv = 0.10;

% RAIO EM ESPAÇO LOGIT PARA POISSON (COESÃO)
% Mapeia (0.01, 0.49) via logit(p) + sigma*delta
% 0.10 é default robusto (ajuste: 0.05-0.20)
cfg.poisson_logit_radius = 0.10;

%% =========================================================================
% 14. ESTABILIDADE LOCAL (DEPRECATED - MANTER COMPATIBILIDADE)
%% =========================================================================

cfg.stop_mode = 'pf_stability';             % Novo modo: parada por Pf estável
cfg.required_consecutive = 5;               % (deprecated)
cfg.relative_tolerance = 0.025;             % (deprecated)
cfg.min_stable_before_stop = 8;             % (deprecated)
cfg.relative_denominator_floor = 1e-8;      % (deprecated)
cfg.min_acceptable_std = 1e-3;              % (deprecated)

%% =========================================================================
% 15. ENVELOPE DE ALERTA DE DESLOCAMENTO
%% =========================================================================

% Fator de alerta para deslocamentos muito altos
% Limiar = recalque_lim * max_displacement_factor
% 1.5 = alerta se deslocamento > 1.5 * limite
cfg.max_displacement_factor = 1.5;

% Rejeitar automaticamente deslocamentos fora do envelope
% FALSE = aceitar com aviso (default, recomendado)
% TRUE = rejeitar caso inteiro
cfg.AL_REJECT_DISPLACEMENT_OUTLIERS = false;

%% =========================================================================
% 16. VALIDACAO DO CAMPO ESPACIAL
%% =========================================================================

% Casas decimais para arredondar coordenadas (detecta duplicatas)
% Default 6 (microns em metros)
cfg.spatial_coordinate_decimals = 6;

% Validações opcionais (deixar [] se desconhecido)
cfg.spatial_expected_points = [];           % Número esperado de pontos
cfg.spatial_expected_nx = [];                % Número de coordenadas X
cfg.spatial_expected_ny = [];                % Número de coordenadas Y

%% =========================================================================
% 17. TOLERANCIA PARA MATERIAIS VAZIOS OU REDUZIDOS (CRÍTICO - NOVO)
%% =========================================================================

% PROBLEMA: Material 3 pode ser reduzido ao máximo e retornar vazio em reconstruct_material_field_from_xi
% SOLUÇÃO: Tolerar tabelas vazias para materiais (mas requer ≥1 material válido)
%
% TRUE  = Ignora materiais vazios silenciosamente (para material 3 reduzido)
%         Log: "[Spatial] Material 3 vazio; ignorado por configuracao."
%         Requer: ≥1 material retorna pontos válidos
%         Python/RS2 usa FEZ original com todo material, apenas discretização é reduzida
%
% FALSE = Qualquer material vazio causa erro (comportamento anterior, rigoroso)
%         Valida presença de todos os 5 materiais
%
% AJUSTE MANUAL:
%   Material 3 normal:           spatial_allow_missing_materials = false
%   Material 3 reduzido:         spatial_allow_missing_materials = true  ← ATIVAR
%   Vários materiais potencialmente vazios: spatial_allow_missing_materials = true
%
% IMPORTANTE: Ignorar material vazio NÃO o remove do FEZ
%   - Apenas a discretização é reduzida no CSV de entrada
%   - Python/RS2 continua usando FEZ original
%   - Impacto na simulação depende de quanto material foi reduzido
cfg.spatial_allow_missing_materials = true;   % ATIVADO PARA ROBUSTEZ

end
