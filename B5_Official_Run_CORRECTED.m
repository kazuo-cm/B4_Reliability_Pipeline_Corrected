function R = B5_Official_Run_CORRECTED(cfg)
% Coordenacao sem ranking, candidatos locais ou retreinamento.
assert(isstruct(cfg) && isscalar(cfg), 'B5:Config', 'cfg deve ser struct escalar.');
required = {'model_file','physical_input_options','out_dir'};
assert(all(isfield(cfg,required)), 'B5:Config', ...
    'cfg requer model_file, physical_input_options e out_dir.');
if ~isfield(cfg,'reliability_options'), cfg.reliability_options = struct(); end
if ~isfield(cfg,'validation_options'), cfg.validation_options = struct(); end
hasInputs = isfield(cfg,'lhs_input_tables');
hasResults = isfield(cfg,'lhs_results');
assert(hasInputs == hasResults, 'B5:Config', ...
    'Forneca lhs_input_tables e lhs_results juntos.');
C = B5_UQLab_Reliability_Skeleton_CORRECTED(cfg.model_file);
if hasInputs
    % Rejeitar dados invalidos antes de executar FORM/MCS.
    validation = B5_Validate_LHS_Model_CORRECTED( ...
        C,cfg.lhs_input_tables,cfg.lhs_results,cfg.validation_options);
end
R.reliability = B5_Run_Reliability_Analysis_CORRECTED( ...
    C,cfg.physical_input_options,cfg.reliability_options);
if hasInputs
    comparison = B5_Compare_Pf_FORM_MCS_CORRECTED(C, ...
        cfg.lhs_input_tables,cfg.lhs_results,R.reliability,cfg.validation_options);
    R.validation = validation;
    R.comparison = comparison.comparison;
end
R.Stage3Contract = C.Stage3Contract;
R.cv_scope = C.cv_scope;
if ~isfolder(cfg.out_dir)
    mkdir(cfg.out_dir);
end
if hasInputs
    writetable(R.validation.predictions,fullfile(cfg.out_dir,'B5_LHS_predictions.csv'));
    writetable(R.comparison,fullfile(cfg.out_dir,'B5_Pf_comparison.csv'));
end
save(fullfile(cfg.out_dir,'B5_results.mat'),'R','-v7.3');
end
