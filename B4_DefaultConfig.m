function cfg = B4_DefaultConfig()
% =========================================================================
% Configuracao oficial do pipeline B4 para a estrategia:
%   - Xi + 18 random values
%   - Stage 0: alinhamento
%   - Stage 1: ranking
%   - Stage 2: selecao
%   - Stage 3: treino PCK
%   - Stage 4: AL com LHS local
%
% A diferenca principal desta versao e que a pasta base e descoberta
% automaticamente apartir do diretorio padrao do projeto.
% VERSÃO CORRIGIDA v6: Validação, normalização, configuração de Pf e
% tolerância a materiais espacialmente ausentes.
% =========================================================================

cfg = struct();

%% -------------------------------------------------------------------------
% Diretórios base
%% -------------------------------------------------------------------------

cfg.work_dir = 'C:\Kazuo-Script';
cfg.base_dir = fullfile(cfg.work_dir, 'RF_5Mat_3Var_400Sim');
cfg.out_dir = fullfile(cfg.work_dir, 'B4_Output_Official');

%% -------------------------------------------------------------------------
% Arquivos de entrada
%% -------------------------------------------------------------------------

cfg.spatial_config_file = fullfile(cfg.base_dir, 'B1_spatial_config.mat');
cfg.training_xi_file = fullfile(cfg.base_dir, 'xi', ...
    'X_xi_5mat_3var_400sim.csv');
cfg.training_results_file = fullfile(cfg.work_dir, 'RS2_Results_RF400.csv');

cfg.material_rv_file = fullfile(cfg.base_dir, 'random_values', ...
    'material_rv.csv');
cfg.liner_rv_file = fullfile(cfg.base_dir, 'random_values', ...
    'liner_rv.csv');

%% -------------------------------------------------------------------------
% Arquivos auxiliares do RS2 / Python
%% -------------------------------------------------------------------------

cfg.python_exe = fullfile(cfg.work_dir, '.venv', 'Scripts', 'python.exe');
cfg.batch_script = fullfile(cfg.work_dir, 'run_al_batch.py');

cfg.fez_file = fullfile(cfg.work_dir, ...
    'MetroParaiso-EstudoCaso_Partial_50%_RF.fez');

cfg.stage4_base_model_file = cfg.fez_file;
cfg.simulation_results_file = fullfile(cfg.work_dir, 'RS2_Results_RF400.csv');

%% -------------------------------------------------------------------------
% Saidas padrao
%% -------------------------------------------------------------------------

cfg.stage0_out_dir = fullfile(cfg.out_dir, 'stage0');
cfg.stage1_out_dir = fullfile(cfg.out_dir, 'stage1');
cfg.stage2_out_dir = fullfile(cfg.out_dir, 'stage2');
cfg.stage3_out_dir = fullfile(cfg.out_dir, 'stage3');
cfg.stage4_out_dir = fullfile(cfg.out_dir, 'stage4');

cfg.stage3_best_file = fullfile(cfg.stage3_out_dir, 'stage3_best.mat');

cfg.AL_AUGMENTED_XI_FILE = fullfile(cfg.stage4_out_dir, 'augmented_xi.csv');
cfg.AL_AUGMENTED_RESULTS_FILE = fullfile(cfg.stage4_out_dir, 'augmented_results.csv');
cfg.current_material_rv_file = fullfile(cfg.stage4_out_dir, 'current_material_rv.csv');
cfg.current_liner_rv_file = fullfile(cfg.stage4_out_dir, 'current_liner_rv.csv');

%% -------------------------------------------------------------------------
% Controle de execucao dos stages
%% -------------------------------------------------------------------------

cfg.run_stage0 = true;
cfg.run_stage1 = true;
cfg.run_stage2 = true;
cfg.run_stage3 = true;
cfg.run_stage4 = true;

cfg.stage4_execute_rs2 = true;
cfg.stage4_auto_loop = true;

%% -------------------------------------------------------------------------
% Critérios e limites
%% -------------------------------------------------------------------------

cfg.recalque_lim = 0.085;
cfg.border_tol = 0.01;
cfg.stage1_var_tol = 1e-12;
cfg.stage1_topK = 250;
cfg.stage2_topK = 120;
cfg.stage2_relevance_target = 0.90;
cfg.stage2_corr_xx_thr = 0.95;
cfg.stage3_nvars_train = 90;
cfg.stage3_marginal_mode = 'estimated';

%% -------------------------------------------------------------------------
% Confirmacoes e contratos
%% -------------------------------------------------------------------------

cfg.initialRVAppliedConfirmed = true;
cfg.require_complete_rv_contract = true;

%% -------------------------------------------------------------------------
% Configuracao principal de AL
%% -------------------------------------------------------------------------

cfg.AL_RESET_ON_START = true;
cfg.AL_SAVE_AUGMENTED_FILES = true;
cfg.AL_APPEND_TO_TRAINING = false;
cfg.AL_RETRAIN_EACH_ITER = true;
cfg.AL_USE_CONVERGENCE = false;

cfg.AL_START_SIM_ID = 401;
cfg.AL_MAX_ITERS = 12;

cfg.AL_CANDIDATE_POOL = 50;
cfg.AL_LOCAL_KNN = 12;
cfg.AL_LOCAL_MIN_SIGMA = 1e-6;

cfg.AL_WEIGHT_U = 1.0;
cfg.AL_WEIGHT_SIGMA = 0.10;

cfg.stage4_field_output_dir = fullfile(cfg.stage4_out_dir, 'fields');
cfg.stage4_write_batch_input = true;
cfg.stage4_use_python = true;

%% -------------------------------------------------------------------------
% Estratégia local LHS
%% -------------------------------------------------------------------------

cfg.local_radius_xi = 0.20;
cfg.local_radius_rv = 0.10;
cfg.poisson_logit_radius = 0.10;

cfg.required_consecutive = 5;
cfg.relative_tolerance = 0.05;
cfg.stop_mode = 'rs2_successive';

%% -------------------------------------------------------------------------
% Logs e auditoria
%% -------------------------------------------------------------------------

cfg.save_audit_csv = true;
cfg.save_model_snapshots = true;
cfg.save_intermediate_tables = true;

%% -------------------------------------------------------------------------
% Flags de automacao do pipeline oficial
%% -------------------------------------------------------------------------

cfg.auto_resolve_paths = true;
cfg.default_base_root = cfg.work_dir;

%% -------------------------------------------------------------------------
% NOVO: Limites físicos e sanidade para Active Learning (CORREÇÃO #4)
%% -------------------------------------------------------------------------

cfg.max_displacement_factor = 1.5;  % Máximo permitido = recalque_lim × fator

%% -------------------------------------------------------------------------
% NOVO: Parâmetros de convergência e exploração (CORREÇÃO #5)
%% -------------------------------------------------------------------------

cfg.min_acceptable_std = 1e-3;      % Variância mínima de predições (alerta se < )
cfg.min_stable_before_stop = 8;     % Iterações mínimas antes de parar por convergência

%% -------------------------------------------------------------------------
% NOVO: Parâmetros de validação de campo espacial (CORREÇÃO #6)
%% -------------------------------------------------------------------------

cfg.field_smoothness_tol_delta_c = 0.5;    % Máximo Δ/C entre materiais (50%)
cfg.field_smoothness_tol_delta_phi = 0.5;  % Máximo Δ/φ entre materiais (50%)

% Permite materiais reduzidos/eliminados; exige ao menos um material válido.
% Use false para preservar a rejeição de qualquer material vazio/ausente.
cfg.spatial_allow_missing_materials = true;

%% -------------------------------------------------------------------------
% NOVO: Configuração de validação cruzada em PCE (CORREÇÃO #8)
%% -------------------------------------------------------------------------

% Número de folds é calculado dinamicamente: min(10, max(5, floor(nsamples/10)))
% Mas pode ser forçado aqui se desejado:
cfg.cv_fold_count_min = 5;
cfg.cv_fold_count_max = 10;

%% -------------------------------------------------------------------------
% ESTIMACAO DE Pf NO STAGE 3
%% -------------------------------------------------------------------------

% Habilita o bloco de população/referência de Pf nas versões do Stage 3
% que o implementam, independentemente de AL_USE_CONVERGENCE (critério local).
% O Stage 3 incluído neste repositório ainda não implementa esse bloco;
% o Stage 4 também deve consumir a referência para comparar iterações.
cfg.AL_USE_Pf_CONVERGENCE = true;

% Tamanho da população LHS para estimar Pf inicial e acompanhar sua evolução.
cfg.AL_Pf_population_size = 5000;

% Multiplicador k-sigma da incerteza preditiva para os limites de Pf.
% k=2 corresponde a uma faixa aproximada de 95% sob hipótese gaussiana.
cfg.AL_Pf_k_factor = 2.0;

% required_consecutive=5 e relative_tolerance=0.05 já definidos acima;
% a parada por estabilidade de Pf depende da implementação do Stage 4.

end