function R = B5_Compare_Pf_FORM_MCS_CORRECTED(C, inputTables, resultTable, reliability, options)
% Frequencia LHS nao e um novo MCS nem prova de validacao externa.
if nargin < 5
    options = struct();
end
validation = B5_Validate_LHS_Model_CORRECTED(C,inputTables,resultTable,options);
P = validation.predictions;
B5_Utils_CORRECTED.ValidateIDs(P.ID, 'Comparacao.ID');
validateattributes(C.limit_m, {'numeric'}, {'real','scalar','finite','positive'});
validateattributes(reliability.MCS.Pf, {'numeric'}, ...
    {'real','scalar','finite','>=',0,'<=',1});
method = ["LHS_observed"; "LHS_surrogate"; "MCS_surrogate"];
pf = [mean(P.Observed_m >= C.limit_m); ...
    mean(P.Predicted_m >= C.limit_m); reliability.MCS.Pf];
if isfield(reliability,'FORM') && strcmp(reliability.FORM.Status,'estimated')
    validateattributes(reliability.FORM.Pf, {'numeric'}, ...
        {'real','scalar','finite','>=',0,'<=',1});
    method(end+1,1) = "FORM_surrogate";
    pf(end+1,1) = reliability.FORM.Pf;
end
R.comparison = table(method,pf,'VariableNames',{'Method','Pf'});
R.validation = validation;
R.scope = 'LHS_frequency_and_surrogate_reliability_not_pipeline_validation';
end
