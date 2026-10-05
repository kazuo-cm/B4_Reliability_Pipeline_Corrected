function R = B5_Validate_LHS_Model_CORRECTED(C, inputTables, resultTable, options)
% Alinha Xi/RVs/resultados por ID; nunca pela posicao das linhas.
if nargin < 4
    options = struct();
end
if ~isfield(options,'id_column'), options.id_column = 'SampleID'; end
if ~isfield(options,'response_column'), options.response_column = 'Displacement_m'; end
if ~iscell(inputTables), inputTables = {inputTables}; end
assert(~isempty(inputTables), 'B5:Table', 'Nenhuma tabela de entrada.');
Tr = local_read_table(resultTable);
B5_Utils_CORRECTED.ValidateTableIDs(Tr, options.id_column, 'Resultados');
assert(any(strcmp(Tr.Properties.VariableNames,options.response_column)), ...
    'B5:Response', 'Coluna da resposta ausente.');
ids = B5_Utils_CORRECTED.ValidateIDs(Tr.(options.id_column), 'Resultados');
y = Tr.(options.response_column);
validateattributes(y, {'numeric'}, {'real','vector','nonempty','finite'});
assert(numel(y) == height(Tr), 'B5:Response', 'Resposta deve ser escalar por ID.');
y = double(y(:));
names = B5_Utils_CORRECTED.ValidateNames(C.names, 'vars_train');
X = zeros(height(Tr),numel(names));
assigned = false(1,numel(names));
for k = 1:numel(inputTables)
    T = local_read_table(inputTables{k});
    B5_Utils_CORRECTED.ValidateTableIDs(T, options.id_column, sprintf('Entrada %d',k));
    rows = local_match_ids(ids, T.(options.id_column));
    for j = 1:numel(names)
        name = char(names(j));
        if any(strcmp(T.Properties.VariableNames,name))
            assert(~assigned(j), 'B5:Variables', ...
                'Variavel %s presente em mais de uma tabela.', name);
            column = T.(name);
            validateattributes(column, {'numeric'}, {'real','vector','nonempty','finite'});
            assert(numel(column) == height(T), 'B5:Variables', ...
                'Variavel %s deve ter um valor por ID.', name);
            X(:,j) = double(column(rows));
            assigned(j) = true;
        end
    end
end
assert(all(assigned), 'B5:Variables', 'Variaveis selecionadas ausentes: %s.', ...
    strjoin(names(~assigned),', '));
yPred = C.predict(X);
validateattributes(yPred, {'numeric'}, {'real','vector','nonempty','finite'});
assert(numel(yPred) == numel(y), 'B5:Prediction', 'Numero de previsoes invalido.');
yPred = double(yPred(:));
residual = yPred - y;
assert(all(isfinite(residual)), 'B5:Metrics', 'Residuos nao finitos.');
R.predictions = table(ids,y,yPred,residual, ...
    'VariableNames',{'ID','Observed_m','Predicted_m','Residual_m'});
R.RMSE_m = norm(residual) / sqrt(numel(y));
R.MAE_m = mean(abs(residual));
denominator = norm(y - mean(y));
if denominator > 0
    R.R2 = 1 - (norm(residual) / denominator)^2;
    assert(isfinite(R.R2), 'B5:Metrics', 'R2 nao finito.');
    R.R2_status = 'defined';
else
    R.R2 = NaN;
    R.R2_status = 'undefined_constant_response';
    warning('B5:ConstantResponse', 'Resposta constante: R2 indefinido, nao substituido por zero.');
end
assert(isfinite(R.RMSE_m) && isfinite(R.MAE_m), 'B5:Metrics', 'Metricas nao finitas.');
R.scope = 'matched_LHS_samples_not_external_pipeline_validation';
if isfield(C,'trainingIDs')
    trainingIDs = B5_Utils_CORRECTED.ValidateIDs(C.trainingIDs, 'Treinamento');
    assert(strcmp(class(ids),class(trainingIDs)), 'B5:IDs', ...
        'IDs de validacao/treinamento devem ter o mesmo tipo.');
    R.training_overlap_count = sum(ismember(ids,trainingIDs));
    if R.training_overlap_count > 0
        warning('B5:TrainingOverlap', ...
            '%d IDs coincidem com o treinamento; nao assumir validacao externa.', ...
            R.training_overlap_count);
    end
end
end

function T = local_read_table(source)
if istable(source)
    T = source;
else
    assert((ischar(source) || (isstring(source) && isscalar(source))) && ...
        isfile(source), 'B5:Table', 'Tabela ou caminho de CSV invalido.');
    T = readtable(source, 'VariableNamingRule','preserve');
end
end

function rows = local_match_ids(referenceIDs, sourceIDs)
referenceIDs = B5_Utils_CORRECTED.ValidateIDs(referenceIDs, 'IDs de referencia');
sourceIDs = B5_Utils_CORRECTED.ValidateIDs(sourceIDs, 'IDs de origem');
assert(strcmp(class(referenceIDs),class(sourceIDs)), 'B5:IDs', ...
    'Tipos de ID diferentes; conversao implicita nao permitida.');
assert(isempty(setdiff(referenceIDs,sourceIDs)) && ...
    isempty(setdiff(sourceIDs,referenceIDs)), 'B5:IDMismatch', ...
    'Tabelas devem conter exatamente o mesmo conjunto de IDs.');
[found,rows] = ismember(referenceIDs,sourceIDs);
assert(all(found), 'B5:IDMismatch', 'Falha no alinhamento por ID.');
end
