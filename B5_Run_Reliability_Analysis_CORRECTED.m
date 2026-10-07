function R = B5_Run_Reliability_Analysis_CORRECTED(C, physicalInputOptions, options)
% MCS usa uma populacao fisica fixa; FORM usa o mesmo estado limite.
if nargin < 3
    options = struct();
end
if ~isfield(options,'n_mcs'), options.n_mcs = 50000; end
if ~isfield(options,'seed'), options.seed = 1; end
if ~isfield(options,'run_form'), options.run_form = true; end
validateattributes(options.n_mcs, {'numeric'}, {'real','scalar','finite','integer','positive'});
validateattributes(options.seed, {'numeric'}, ...
    {'real','scalar','finite','integer','nonnegative','<=',2^32-1});
validateattributes(options.run_form, {'logical'}, {'scalar'});
validateattributes(C.limit_m, {'numeric'}, {'real','scalar','finite','positive'});
names = B5_Utils_CORRECTED.ValidateNames(C.names, 'vars_train');
assert(isstruct(physicalInputOptions) && isscalar(physicalInputOptions) && ...
    isfield(physicalInputOptions,'Marginals') && ...
    numel(physicalInputOptions.Marginals) == numel(names), ...
    'B5:Marginals', 'Forneca marginais fisicas para todas as variaveis selecionadas.');
assert(isfield(physicalInputOptions.Marginals,'Name'), ...
    'B5:Marginals', 'Cada marginal fisica deve ter Name.');
inputNames = B5_Utils_CORRECTED.ValidateNames( ...
    {physicalInputOptions.Marginals.Name}, 'Marginals.Name');
assert(isequal(inputNames,names), 'B5:Marginals', ...
    'Marginais fisicas devem seguir a ordem de vars_train.');
oldRng = rng;
restoreRng = onCleanup(@() rng(oldRng));
rng(options.seed,'twister');
physicalInput = uq_createInput(physicalInputOptions,'-private');
assert(numel(physicalInput.Marginals) == numel(names), ...
    'B5:Marginals', 'Numero de marginais criado diferente do contrato.');
for j = 1:numel(names)
    moments = physicalInput.Marginals(j).Moments;
    validateattributes(moments, {'numeric'}, {'real','vector','numel',2,'finite'});
    assert(moments(2) > 0, 'B5:Marginals', ...
        'Desvio padrao fisico nulo ou negativo: %s.', names(j));
end
if isfield(options,'Pf_population')
    assert(isfield(options,'Pf_population_names'), 'B5:Population', ...
        'Populacao reutilizada requer Pf_population_names na ordem das colunas.');
    populationNames = B5_Utils_CORRECTED.ValidateNames( ...
        options.Pf_population_names, 'Pf_population_names');
    assert(isequal(populationNames,names), 'B5:Population', ...
        'Colunas da populacao Pf diferentes da ordem treinada.');
    X = options.Pf_population;
    assert(size(X,1) == options.n_mcs, 'B5:Population', ...
        'Pf_population deve ter exatamente n_mcs linhas; nao sera reamostrada.');
else
    X = uq_getSample(physicalInput,options.n_mcs,'MC');
end
validateattributes(X, {'numeric'}, {'real','2d','nonempty','finite'});
assert(size(X,1) == options.n_mcs && size(X,2) == numel(names), ...
    'B5:Population', 'Dimensoes da populacao Pf invalidas.');
if isfield(C.Stage3Contract,'valid_for_global_pf_sampling') && ...
        ~C.Stage3Contract.valid_for_global_pf_sampling
    warning('B5:GlobalPfScope', ...
        ['Stage 3 nao certifica Pf global. A distribuicao fisica foi fornecida ', ...
         'explicitamente; extrapolacao e erro do surrogate ainda precisam de validacao.']);
end
g = C.limit_m - C.predict(X);
validateattributes(g, {'numeric'}, {'real','vector','nonempty','finite'});
assert(numel(g) == options.n_mcs, 'B5:Prediction', 'Tamanho de g invalido.');
nFailures = sum(g(:) <= 0);
pf = nFailures / options.n_mcs;
R.MCS.Pf = pf;
R.MCS.N = options.n_mcs;
R.MCS.NFailures = nFailures;
R.MCS.StandardError = sqrt(pf * (1-pf) / options.n_mcs);
if nFailures == 0
    R.MCS.CoV = Inf;
    R.MCS.Status = 'no_failures_not_proof_of_zero_risk';
    R.MCS.ZeroFailuresUpper95 = -expm1(log(0.05) / options.n_mcs);
else
    R.MCS.CoV = R.MCS.StandardError / pf;
    R.MCS.Status = 'estimated';
end
R.Pf_population = X;
R.Pf_population_names = names;
R.seed = options.seed;
R.population_scope = 'fixed_physical_population_no_convergence_claim';
R.FORM.Status = 'not_requested';
if options.run_form
    Gopts.Type = 'Model';
    Gopts.mHandle = @(x) C.limit_m - C.predict(x);
    Gopts.isVectorized = true;
    gModel = uq_createModel(Gopts,'-private');
    Aopts.Type = 'Reliability';
    Aopts.Method = 'FORM';
    Aopts.Input = physicalInput;
    Aopts.Model = gModel;
    Aopts.LimitState.Threshold = 0;
    Aopts.LimitState.CompOp = '<=';
    analysis = uq_createAnalysis(Aopts,'-private');
    assert(isfield(analysis.Results,'History') && ...
        numel(analysis.Results.History) == 1 && ...
        isfield(analysis.Results.History,'ExitFlag'), 'B5:FORMConvergence', ...
        'UQLab nao forneceu diagnostico de convergencia FORM.');
    exitFlag = string(analysis.Results.History.ExitFlag);
    assert(isscalar(exitFlag) && ~ismissing(exitFlag) && ...
        (strcmp(exitFlag,'g_X = 0') || ...
        startsWith(exitFlag,'|Uk-Uk+1| < StopEpsilon _AND_')), ...
        'B5:FORMConvergence', 'FORM nao convergiu: %s.', strjoin(exitFlag,', '));
    formPf = analysis.Results.Pf;
    validateattributes(formPf, {'numeric'}, {'real','scalar','finite','>=',0,'<=',1});
    R.FORM.Pf = double(formPf);
    R.FORM.Status = 'estimated';
    R.FORM.ExitFlag = exitFlag;
    R.FORM.Results = analysis.Results;
end
end
