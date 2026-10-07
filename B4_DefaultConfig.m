function cfg = B4_DefaultConfig(workDir)
% =========================================================================
% B4_DefaultConfig - Configuracao central do pipeline B4
%
% Pipeline: PC-Kriging Normalizado + Active Learning Local com Pf Estável
% Versao: v7 - Com validação Pf, tolerância materiais reduzidos e contrato rigoroso
%
% USO:
%   cfg = B4_DefaultConfig();                % usando C:\Kazuo-Script default
%   cfg = B4_DefaultConfig('D:\Projeto');    % caminho customizado
%
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

cfg.configuration_version = 'B4_NormalizedPCK_LocalAL_Pf_Stable_Robust_v7';
cfg.seed = 100;

%% =========================================================================
% 2. DIRETORIOS BASE
%% =========================================================================

cfg.work_dir = char(workDir);
cfg.base_dir = fullfile(cfg.work_dir, 'RF_5Mat_3Var_400Sim');

%% =========================================================================
% 3. ARQUIVOS DE ENTRADA - STAGE 0
%% =========================================================================

cfg.spatial_config_file = ...
    fullfile(cfg.base_dir, 'B1_spatial_config.mat');

cfg.training_xi_file = fullfile(cfg.base_dir, 'xi', ...
    'X_xi_5mat_3var_400sim.csv');

cfg.training_results_file = ...
    fullfile(cfg.work_dir, 'RS2_Results_RF400.csv');

cfg.material_rv_file = fullfile(cfg.base_dir, ...
    'random_values', 'material_rv.csv');

cfg.liner_rv_file = fullfile(cfg.base_dir, ...
    'random_values', 'liner_rv.csv');

%% =========================================================================
% 4. INTERFACE PYTHON / RS2 - STAGE 4
%% =========================================================================

cfg.python_exe = ...
    fullfile(cfg.work_dir, '.venv', 'Scripts', 'python.exe');

cfg.batch_script = ...
    fullfile(cfg.work_dir, 'run_al_batch.py');

cfg.fez_file = fullfile(cfg.work_dir, ...
    'MetroParaiso-EstudoCaso_Partial_50%_RF.fez');

cfg.stage4_base_model_file = cfg.fez_file;

cfg.simulation_results_file = ...
    fullfile(cfg.work_dir, 'RS2_Results_RF400.csv');

cfg.rs2_expected_stage = 7;

% Contrato do batch Python: ajustar flags para o run_al_batch.py instalado.
% Cada item e um argumento separado (nao uma linha de shell).
% Saida: CSV com SampleID ou SimulationID e a coluna de deslocamento abaixo.
% Status (OK/SUCCESS/COMPLETED) e Stage sao validados quando presentes.
cfg.stage4_result_displacement_column = 'Displacement_m';
cfg.stage4_python_args = {'--xi-file','{xi_file}', ...
    '--material-rv-file','{material_rv_file}', ...
    '--liner-rv-file','{liner_rv_file}', ...
    '--field-file','{field_file}', '--results-file','{results_file}', ...
    '--model-file','{model_file}', '--sim-id','{sim_id}', ...
    '--expected-stage','{expected_stage}'};

%% =========================================================================
% 5. SAIDAS PADRAO - STAGES 0-4
%% =========================================================================

cfg.out_dir = fullfile(cfg.work_dir, ...
    'B4_Output_Official', 'pipeline');

cfg.stage0_out_dir = cfg.out_dir;
cfg.stage1_out_dir = cfg.out_dir;
cfg.stage2_out_dir = cfg.out_dir;
cfg.stage3_out_dir = cfg.out_dir;

cfg.stage4_out_dir = fullfile(cfg.work_dir, ...
    'B4_Output_Official', 'stage4');

cfg.stage3_best_file = ...
    fullfile(cfg.out_dir, 'stage3_best.mat');

cfg.AL_AUGMENTED_XI_FILE = ...
    fullfile(cfg.stage4_out_dir, 'augmented_xi.csv');

cfg.AL_AUGMENTED_RESULTS_FILE = ...
    fullfile(cfg.stage4_out_dir, 'augmented_results.csv');

cfg.current_material_rv_file = ...
    fullfile(cfg.stage4_out_dir, 'current_material_rv.csv');

cfg.current_liner_rv_file = ...
    fullfile(cfg.stage4_out_dir, 'current_liner_rv.csv');

%% =========================================================================
% 6. CONTROLE DE EXECUCAO DOS STAGES
%% =========================================================================

cfg.run_stage0 = true;   % Alinhamento Xi + 18 RVs
cfg.run_stage1 = true;   % Ranking de variaveis
cfg.run_stage2 = true;   % Selecao de variaveis
cfg.run_stage3 = true;   % Treinamento PC-Kriging
cfg.run_stage4 = true;   % Active Learning

cfg.stage4_execute_rs2 = true;   % Executa Python/RS2
cfg.stage4_auto_loop = true;      % Loop automatico de AL

%% =========================================================================
% 7. CONFIRMACAO - 18 RVs APLICADOS NAS SIMULACOES INICIAIS (CRITICO)
%% =========================================================================

cfg.initialRVAppliedConfirmed = true;

%% =========================================================================
% 8. ESTADO LIMITE E RANKING
%% =========================================================================

% recalque_lim: Deslocamento total máximo aceitável [m]
%   - Define função de estado limite: g = recalque_lim - deslocamento
%   - Falha quando g <= 0 (deslocamento >= limite)
%   AJUSTE:
%     - Material 3 normal: 0.085 m
%     - Material 3 reduzido: 0.095 m (ATUAL - maior tolerância)

cfg.recalque_lim = 0.095;      % m - limite de deslocamento (material 3 reduzido)
cfg.border_tol = 0.01;         % m - zona de fronteira

cfg.stage1_var_tol = 1e-12;    % filtro de variancia baixa

cfg.stage1_topK = 250;         % maximo total selecionado (18 RVs + Xi)
cfg.stage2_topK = 120;         % apos filtro de correlacao X-X
cfg.stage3_nvars_train = 90;   % 18 RVs obrigatorios + 72 Xi

cfg.stage2_relevance_target = 0.90;  % cumulative score threshold
cfg.stage2_corr_xx_thr = 0.95;       % maxima correlacao X-X entre selecionados

%% =========================================================================
% 9. PC-KRIGING (STAGE 3) - TREINAMENTO
%% =========================================================================

cfg.stage3_marginal_mode = 'estimated';
cfg.stage3_pce_degree = 1:3;
cfg.stage3_pce_qnorm = 0.85:0.05:1.0;

cfg.cv_fold_count_min = 5;
cfg.cv_fold_count_max = 10;

cfg.stage3_require_finite_loo = false;
cfg.stage3_min_r2_cv = 0.50;
cfg.stage3_reject_poor_cv = false;
cfg.stage3_overfit_r2_gap = 0.15;

%% =========================================================================
% 10. ESTIMACAO DE Pf NO STAGE 3 (NOVO - CONVERGENCIA NO STAGE 4)
%% =========================================================================

% AL_USE_Pf_STABILITY: Ativa estimacao de Pf e parada por convergencia
%
% Se TRUE (RECOMENDADO):
%   - Stage 3 gera populacao LHS FIXA (gaussiana) com AL_Pf_population_size amostras
%   - Estima Pf_initial, Pf_low, Pf_high, largura relativa
%   - Armazena em Pf_population para Stage 4 usar como referencia
%   - Stage 4 estima Pf apos retreinar e para quando 5 leituras tiverem variacao < 5%
%
% Se FALSE:
%   - Stage 3 nao gera populacao Pf
%   - Stage 4 para apenas por limite de iteracoes (AL_MAX_ITERS)
%
% AJUSTE MANUAL:
%   - Ativar (true) para simulacoes com Material 3 reduzido (usa AL com Pf estavel)
%   - Desativar (false) para simulacoes normais se velocidade é prioridade

cfg.AL_USE_Pf_STABILITY = true;

% Parametros da populacao LHS FIXA para estimacao de Pf no Stage 3
% (nao muda entre iteracoes; usado como referencia para convergencia)
cfg.AL_Pf_population_size = 5000;  % amostras LHS
cfg.AL_Pf_k_factor = 2.0;          % sigma-factor para faixa (k=2 ≈ 95% CI)

%% =========================================================================
% 11. ACTIVE LEARNING (STAGE 4) - CONTROLE DE EXECUCAO
%% =========================================================================

% AL_RESET_ON_START: Limpar snapshots e exportacoes existentes
%   - false = retomar a partir do ultimo snapshot (se existir) - RECOMENDADO
%   - true = comeca do zero (recomendado para novo experimento)

cfg.AL_RESET_ON_START = false;              % false: retomar; true: comeca do zero

% AL_SAVE_AUGMENTED_FILES: Salvar Xi/RVs acumulados apos cada iteracao
%   - true = salva CSV para rastreabilidade (RECOMENDADO)
%   - false = sem snapshots (mais rapido, menos rastreabilidade)
%   - DEVE SER TRUE se AL_RETRAIN_EACH_ITER = true

cfg.AL_SAVE_AUGMENTED_FILES = true;         % true: salvar snapshots (rastreabilidade)

% AL_APPEND_TO_TRAINING: Modificar arquivo original de treinamento
%   - false = MATLAB nao altera dados originais (seguro, FIXO)
%   - true = evitar sempre (corrupcao de dados)

cfg.AL_APPEND_TO_TRAINING = false;          % MANTER false (seguranca)

% AL_RETRAIN_EACH_ITER: Retreinar Stages 0-3 apos cada caso novo valido
%   - true = retreinamento completo (RECOMENDADO)
%   - false = sem retreinamento (mais rapido, menos acurado)

cfg.AL_RETRAIN_EACH_ITER = true;            % true: retreinar model a cada iteracao

%% =========================================================================
% 12. PARADA POR ESTABILIDADE DE Pf COM POPULACAO MCS FIXA
%% =========================================================================

% AL_USE_Pf_STABILITY ja ativado em § 10
% Aqui definimos os parametros de parada e metodos numericos

% === MCS: populacao fixa; numero de falhas valida a convergencia ===
%
% Mecanismo: Avalia metamodelo em AL_Pf_mcs_target_population amostras
%            Avalia toda a populacao, sem parada antecipada enviesada.
%            Exige AL_Pf_mcs_min_failures para permitir convergencia.
%
% AJUSTE MANUAL:
%   Convergencia rapida (AL com poucas iteracoes):
%     AL_Pf_mcs_target_population = 20000  (em vez de 50000)
%     AL_Pf_mcs_min_failures = 20          (em vez de 50)
%   Convergencia conservadora (mais iteracoes):
%     AL_Pf_mcs_target_population = 50000
%     AL_Pf_mcs_min_failures = 100

cfg.AL_Pf_mcs_target_population = 50000;    % populacao maxima para MCS
cfg.AL_Pf_mcs_min_failures = 50;            % minimo de falhas para convergencia

% === SS: parametros legados (nao usados por este Stage 4) ===
%
% Sem falhas suficientes, Stage 4 nao declara convergencia por Pf.
% Nao ha fallback SS implementado; aumentar a populacao para eventos raros.
%
% AJUSTE MANUAL:
%   Falhas raras (<0.1%):
%     AL_Pf_ss_intermediate_pf = 0.05      (5% em vez de 10%)
%     AL_Pf_ss_num_chains = 2000           (em vez de 1000)
%   Falhas muito raras (<0.01%):
%     AL_Pf_ss_intermediate_pf = 0.01
%     AL_Pf_ss_num_chains = 5000

cfg.AL_Pf_ss_intermediate_pf = 0.1;         % Pf intermediaria (10%)
cfg.AL_Pf_ss_num_chains = 1000;             % cadeias de amostragem
cfg.AL_Pf_ss_samples_per_chain = 2;         % amostras por cadeia

% === Criterio de convergencia: 5 leituras com variacao SEQUENCIAL < 5% ===
%
% Mecanismo:
%   - Mantem janela dos 5 ultimas estimativas de Pf
%   - Compara cada leitura com a ANTERIOR (nao com a primeira)
%   - Se 4 comparacoes consecutivas tiverem variacao < 5%, convergiu
%   - Exemplo de convergencia:
%       Iter 1: Pf=0.150
%       Iter 2: Pf=0.148  (variacao: |0.148-0.150|/max(0.150,0.001) = 1.3% < 5%) ✓
%       Iter 3: Pf=0.149  (variacao: |0.149-0.148|/max(0.148,0.001) = 0.7% < 5%) ✓
%       Iter 4: Pf=0.150  (variacao: |0.150-0.149|/max(0.149,0.001) = 0.7% < 5%) ✓
%       Iter 5: Pf=0.151  (variacao: |0.151-0.150|/max(0.150,0.001) = 0.7% < 5%) ✓
%       → 4 comparacoes estaveis = CONVERGIU (apos mínimo de 6 casos novos)
%
% AJUSTE MANUAL:
%   Parada rapida (menos iteracoes):
%     AL_Pf_stability_tolerance = 0.10       (10% em vez de 5%)
%     AL_Pf_stable_readings = 3              (3 em vez de 5)
%     AL_Pf_min_iterations = 4               (4 em vez de 6)
%   Parada conservadora (mais iteracoes):
%     AL_Pf_stability_tolerance = 0.02       (2% em vez de 5%)
%     AL_Pf_stable_readings = 7              (7 em vez de 5)
%     AL_Pf_min_iterations = 10              (10 em vez de 6)

cfg.AL_Pf_stability_tolerance = 0.05;       % 5% variacao relativa maxima
cfg.AL_Pf_stable_readings = 5;              % 5 leituras consecutivas = 4 comparacoes
cfg.AL_Pf_min_iterations = 6;               % minimo 6 retreinamentos
cfg.AL_Pf_comparison_window = 5;            % janela de 5 ultimas estimativas

% === Protecoes ===
% AL_Pf_floor: Piso para normalizacao em variacao relativa
%   - Evita divisao por zero quando Pf_anterior é muito pequeno
%   - Tipicamente 0.1% da probabilidade de falha

cfg.AL_Pf_floor = 0.001;                    % piso = 0.1%

% AL_Pf_max_eval_cost: Limite maximo de avaliacoes do metamodelo
%   - Protege contra loops infinitos
%   - Tipicamente iter * AL_Pf_mcs_target_population

cfg.AL_Pf_max_eval_cost = 5e6;              % maximo 5M avaliacoes

% === Criterio antigo (DEPRECATED - usar AL_USE_Pf_STABILITY) ===

cfg.AL_USE_CONVERGENCE = false;             % MANTER false (usar AL_USE_Pf_STABILITY)

%% =========================================================================
% 13. CONFIGURACAO DE TENTATIVAS E CANDIDATOS
%% =========================================================================

% AL_START_SIM_ID: ID inicial para tentativas do AL
%   - Comeca em 401 (apos 400 simulacoes iniciais)
%   - Incrementa automaticamente para cada tentativa

cfg.AL_START_SIM_ID = 401;          % ID inicial para tentativas do AL

% AL_MAX_ITERS: Limite maximo de tentativas de AL
%   - Default 20 (apos isso, para independentemente de convergencia)
%   - Reduzir a 10 para simulacoes rapidas
%   - Aumentar a 30 para convergencia muito conservadora

cfg.AL_MAX_ITERS = 20;              % limite maximo de tentativas

% AL_CANDIDATE_POOL: Tamanho do pool LHS local
%   - Numero de candidatos gerados ao redor de cada caso de fronteira
%   - 50 é equilibrio entre exploracao e velocidade
%   - Aumentar a 100 para melhor exploracao (mais lento)
%   - Reduzir a 20 para velocidade (menos exploracao)

cfg.AL_CANDIDATE_POOL = 50;         % tamanho do pool LHS local

%% =========================================================================
% 14. PERTURBACOES LOCAIS (GERACAO DE CANDIDATOS)
%% =========================================================================

% local_radius_xi: Raio relativo de perturbacao para Xi [fracao]
%   - Gaussiana com media = base_xi, sigma = base_xi * local_radius_xi
%   - 0.20 significa +/- 20% do valor base
%   - Aumentar a 0.30 para maior exploracao
%   - Reduzir a 0.10 para perturbacoes menores (mais local)

cfg.local_radius_xi = 0.20;         % raio relativo para Xi (20%)

% local_radius_rv: Raio multiplicativo em log-space para RVs [fracao]
%   - Lognormal: log(rv_novo) = log(base_rv) + sigma_log * delta
%   - 0.10 significa +/- 10% em escala logaritmica
%   - Aumentar a 0.20 para maior exploracao
%   - Reduzir a 0.05 para perturbacoes menores

cfg.local_radius_rv = 0.10;         % raio em log-space para RVs (10%)

% poisson_logit_radius: Raio em espaco logit para Poisson (coesao) [fracao]
%   - Poisson em (0.01, 0.49): mapear via logit(p) + sigma*delta
%   - 0.10 é default robusto
%   - Aumentar a 0.20 para maior variabilidade
%   - Reduzir a 0.05 para variacoes menores

cfg.poisson_logit_radius = 0.10;    % raio em logit-space para Poisson (10%)

%% =========================================================================
% 15. ESTABILIDADE LOCAL (DEPRECATED - MANTER PARA COMPATIBILIDADE)
%% =========================================================================

cfg.stop_mode = 'pf_stability';             % novo modo (Pf estavel)
cfg.required_consecutive = 5;               % (deprecated)
cfg.relative_tolerance = 0.025;             % (deprecated)
cfg.min_stable_before_stop = 8;             % (deprecated)
cfg.relative_denominator_floor = 1e-8;      % (deprecated)
cfg.min_acceptable_std = 1e-3;              % (deprecated)

%% =========================================================================
% 16. ENVELOPE DE ALERTA DE DESLOCAMENTO (CORREÇÃO #4)
%% =========================================================================

% max_displacement_factor: Fator de alerta para deslocamentos muito altos
%   - Limiar de alerta = recalque_lim * max_displacement_factor
%   - Se deslocamento observado > limiar:
%       * Log: "Warning: resultado valido aceito com alerta de envelope"
%       * File: displacement_outlier_warning.txt (para inspecao)
%   - 1.5 significa alerta se deslocamento > 1.5 * limite
%
% AL_REJECT_DISPLACEMENT_OUTLIERS: Rejeitar automaticamente outliers
%   - false = aceitar com aviso (RECOMENDADO)
%   - true = rejeitar caso inteiro (pode perder informacao valiosa)
%
% AJUSTE MANUAL:
%   Tolerante (aceitar outliers com aviso):
%     max_displacement_factor = 2.0
%     AL_REJECT_DISPLACEMENT_OUTLIERS = false
%   Rigoroso (rejeitar outliers):
%     max_displacement_factor = 1.2
%     AL_REJECT_DISPLACEMENT_OUTLIERS = true

cfg.max_displacement_factor = 1.5;          % fator de alerta
cfg.AL_REJECT_DISPLACEMENT_OUTLIERS = false;  % false: aviso; true: rejeitar

%% =========================================================================
% 17. VALIDACAO DO CAMPO ESPACIAL (5 MATERIAIS)
%% =========================================================================

% spatial_coordinate_decimals: Casas decimais para arredondar coordenadas
%   - Detecta pontos coincidentes apos arredondamento
%   - Default 6 (microns em metros)
%   - Aumentar a 5 se coordenadas sao muito proximas
%   - Reduzir a 7 se coordenadas sao muito diferentes

cfg.spatial_coordinate_decimals = 6;        % casas decimais para arredondar

% spatial_expected_points: Numero esperado de pontos no campo (opcional)
%   - Se definido (not []), valida exatamente este numero
%   - Util para detectar mudancas involuntarias na discretizacao
%   - Default [] (sem validacao)

cfg.spatial_expected_points = [];           % (opcional) deixar vazio se desconhecido

% spatial_expected_nx/ny: Numero esperado de coordenadas X e Y (opcional)
%   - Se definidos, validam dimensoes da malha
%   - Default [] (sem validacao)

cfg.spatial_expected_nx = [];                % (opcional)
cfg.spatial_expected_ny = [];                % (opcional)

%% =========================================================================
% 18. TOLERANCIA PARA MATERIAIS VAZIOS OU REDUZIDOS (CORREÇÃO #6)
%% =========================================================================

% spatial_allow_missing_materials: Tolerar materiais vazios
%
% Se TRUE:
%   - Materiais que retornam tabela vazia sao ignorados silenciosamente
%   - Requer que PELO MENOS UM material retorne pontos validos
%   - Util para simulacoes com material reduzido ao maximo (ex: material 3)
%   - Log mostra:
%       [Spatial] Material 3 vazio; ignorado por configuracao.
%       [Spatial] Status dos materiais: 1=OK, 2=OK, 3=EMPTY_SKIPPED, 4=OK, 5=OK
%       [Spatial] Materiais com pontos: 4/5 | Total de pontos: 1524.
%
% Se FALSE:
%   - Qualquer material vazio causa erro
%   - Valida presenca rigorosa de todos os 5 materiais
%   - Comportamento anterior (mais restritivo)
%
% IMPORTANTE:
%   - Ignorar material vazio nao o remove do FEZ (Python/RS2)
%   - Apenas remove sua discretizacao do CSV de entrada
%   - Python/RS2 usa FEZ original, que ainda contém todo material
%   - Impacto na simulacao depende de quanto material foi reduzido
%
% AJUSTE MANUAL:
%   Material 3 normal (5 materiais sempre presentes):
%     spatial_allow_missing_materials = false   % (default, rigoroso)
%   Material 3 reduzido ao maximo ou eliminado:
%     spatial_allow_missing_materials = true    % ATIVAR (tolerancia)
%   Varios materiais potencialmente vazios:
%     spatial_allow_missing_materials = true    % ATIVAR (robustez)

cfg.spatial_allow_missing_materials = true;   % ATIVADO para material 3 reduzido

%% =========================================================================
% 19. CONTRATO E VALIDACOES (CORREÇÃO #1)
%% =========================================================================

% require_complete_rv_contract: Obriga 18 RVs sempre presentes
%   - true = valida que modelo tem exatamente 18 RVs obrigatorios

cfg.require_complete_rv_contract = true;

% validate_input_normalization: Valida Z-score em Stage 3
%   - true = verifica que entradas estao normalizadas corretamente

cfg.validate_input_normalization = true;

% validate_output_denormalization: Valida recuperacao de escala
%   - true = verifica que saida denormalizada é finita

cfg.validate_output_denormalization = true;

end
