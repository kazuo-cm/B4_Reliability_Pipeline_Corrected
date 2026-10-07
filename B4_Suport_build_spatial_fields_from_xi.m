function [xGrid, yGrid, cVals, phiVals, EVals] = ...
    B4_Suport_build_spatial_fields_from_xi(xi_row, cfg)
% =========================================================================
% Reconstruir campos espaciais usando o vetor COMPLETO de Xi.
%
% xi_row: vetor numerico completo ou tabela de uma linha com xi_1,...,xi_n.
% cfg.spatial_config_file: arquivo MAT contendo nMat e nXiTotal.
%
% Opcoes:
%   spatial_allow_missing_materials (default: false): pula retornos vazios
%       ou nao tabulares; exige ao menos um material com pontos validos.
%   spatial_expected_points, spatial_expected_nx, spatial_expected_ny:
%       dimensoes opcionais, verificadas mesmo quando materiais sao pulados.
%   spatial_coordinate_decimals (default: 6): precisao das coordenadas.
%
% Saidas: vetores coluna ordenados por X e depois Y.
% Nao aplica RVs, nao presume que Xi selecionado seja o Xi completo e nao
% exige suavidade entre materiais. Coordenadas coincidentes sao rejeitadas:
% o CSV do Stage 4 nao possui MaterialID para desambiguacao.
% =========================================================================

assert(isstruct(cfg) && isscalar(cfg), ...
    'Spatial: cfg deve ser uma estrutura escalar.');
assert(isfield(cfg, 'spatial_config_file'), ...
    'Spatial: cfg.spatial_config_file ausente.');

configValue = string(cfg.spatial_config_file);
assert(isscalar(configValue) && ~ismissing(configValue) && ...
    strlength(configValue) > 0, ...
    'Spatial: caminho de configuracao invalido.');
configFile = char(configValue);
assert(isfile(configFile), ...
    'Spatial: configuracao nao encontrada: %s.', configFile);
assert(~isempty(which('reconstruct_material_field_from_xi')), ...
    'Spatial: reconstrutor nao encontrado no MATLAB path.');

%% Configuracao espacial
S = load(configFile, 'nMat', 'nXiTotal');
assert(all(isfield(S, {'nMat', 'nXiTotal'})), ...
    'Spatial: configuracao deve conter nMat e nXiTotal.');
validateattributes(S.nMat, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'positive'});
validateattributes(S.nXiTotal, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'positive'});
nMat = double(S.nMat);
nXiTotal = double(S.nXiTotal);

%% Extrair Xi completo
if istable(xi_row)
    assert(height(xi_row) == 1, ...
        'Spatial: a tabela Xi deve conter exatamente uma linha.');
    variableNames = string(xi_row.Properties.VariableNames);
    xiNames = variableNames(startsWith(variableNames, "xi_"));
    assert(~isempty(xiNames), 'Spatial: tabela sem colunas xi_*.');
    indices = zeros(1, numel(xiNames));

    for k = 1:numel(xiNames)
        token = regexp(char(xiNames(k)), ...
            '^xi_([1-9][0-9]*)$', 'tokens', 'once');
        assert(~isempty(token), ...
            'Spatial: nome Xi invalido: %s.', char(xiNames(k)));
        indices(k) = str2double(token{1});
    end

    [indices, order] = sort(indices);
    xiNames = xiNames(order);
    assert(isequal(indices, 1:nXiTotal), ...
        ['Spatial: tabela deve conter exatamente ', ...
         'xi_1 ate xi_%d, sem lacunas.'], nXiTotal);
    xi_vec = zeros(1, nXiTotal);

    for k = 1:nXiTotal
        raw = xi_row.(char(xiNames(k)));
        if isnumeric(raw) || islogical(raw)
            value = double(raw);
        else
            value = str2double(string(raw));
        end
        assert(isscalar(value) && isreal(value) && isfinite(value), ...
            'Spatial: valor invalido em %s.', char(xiNames(k)));
        xi_vec(k) = value;
    end
elseif isnumeric(xi_row)
    assert(isvector(xi_row) && isreal(xi_row), ...
        'Spatial: Xi numerico deve ser um vetor real.');
    xi_vec = double(xi_row(:))';
else
    error('B4:InvalidSpatialXi', ...
        'Spatial: Xi deve ser vetor numerico ou tabela de uma linha.');
end

assert(numel(xi_vec) == nXiTotal, ...
    'Spatial: esperado Xi com %d valores; recebido %d.', ...
    nXiTotal, numel(xi_vec));
assert(all(isfinite(xi_vec)), 'Spatial: Xi contem NaN ou Inf.');

allowMissing = local_option(cfg, 'spatial_allow_missing_materials', false);
assert(isscalar(allowMissing) && ...
    (islogical(allowMissing) || isnumeric(allowMissing)) && ...
    isreal(allowMissing) && isfinite(double(allowMissing)) && ...
    any(double(allowMissing) == [0, 1]), ...
    'Spatial: spatial_allow_missing_materials deve ser booleano escalar.');

%% Reconstruir materiais
materialFields = cell(nMat, 1);
requiredColumns = {'X', 'Y', 'C', 'phi', 'E'};
materialStatus = strings(1, nMat);

for matID = 1:nMat
    field = reconstruct_material_field_from_xi(xi_vec, configFile, matID);

    if ~istable(field) || height(field) == 0
        assert(allowMissing, ...
            'Spatial: material %d retornou campo vazio ou nao tabular.', matID);
        fprintf('[Spatial] Material %d vazio ou ausente; pulando.\n', matID);
        materialFields{matID} = table( ...
            zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
            zeros(0, 1), zeros(0, 1), 'VariableNames', requiredColumns);
        materialStatus(matID) = "EMPTY";
        continue;
    end

    assert(all(ismember(requiredColumns, field.Properties.VariableNames)), ...
        'Spatial: material %d sem X, Y, C, phi ou E.', matID);
    field = field(:, requiredColumns);

    for k = 1:numel(requiredColumns)
        columnName = requiredColumns{k};
        values = field.(columnName);
        assert(isnumeric(values) && isreal(values) && ...
            size(values, 2) == 1 && all(isfinite(values(:))), ...
            'Spatial: coluna %s invalida no material %d.', columnName, matID);
        field.(columnName) = double(values);
    end

    assert(all(field.C > 0), ...
        'Spatial: coesao nao positiva no material %d.', matID);
    assert(all(field.phi > 0 & field.phi < 90), ...
        'Spatial: phi fora de (0,90) no material %d.', matID);
    assert(all(field.E > 0), ...
        'Spatial: E nao positivo no material %d.', matID);
    materialFields{matID} = field;
    materialStatus(matID) = "OK";
end

Tfield = vertcat(materialFields{:});
statusSummary = char(strjoin(string(1:nMat) + "=" + materialStatus, ', '));
if height(Tfield) == 0
    error('B4:NoValidMaterials', ...
        'Spatial: nenhum material retornou pontos validos. Status: %s', ...
        statusSummary);
end
fprintf('[Spatial] Materiais reconstruidos: %s\n', statusSummary);

%% Coordenadas e ordenacao
decimals = local_option(cfg, 'spatial_coordinate_decimals', 6);
validateattributes(decimals, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', '>=', 0, '<=', 15});
coordinateKeys = round([Tfield.X, Tfield.Y], decimals);
assert(size(unique(coordinateKeys, 'rows'), 1) == height(Tfield), ...
    ['Spatial: coordenadas repetidas ao arredondar para %d casas. ', ...
     'O CSV sem MaterialID nao permite desambiguar pontos compartilhados.'], ...
    decimals);
Tfield = sortrows(Tfield, {'X', 'Y'});

%% Dimensoes opcionais da malha
expectedPoints = local_option(cfg, 'spatial_expected_points', []);
expectedNx = local_option(cfg, 'spatial_expected_nx', []);
expectedNy = local_option(cfg, 'spatial_expected_ny', []);

if ~isempty(expectedPoints)
    validateattributes(expectedPoints, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'integer', 'positive'});
    assert(height(Tfield) == expectedPoints, ...
        'Spatial: esperado %d pontos; recebido %d.', ...
        expectedPoints, height(Tfield));
end
if ~isempty(expectedNx)
    validateattributes(expectedNx, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'integer', 'positive'});
    nx = numel(unique(round(Tfield.X, decimals)));
    assert(nx == expectedNx, ...
        'Spatial: esperado %d coordenadas X; recebido %d.', expectedNx, nx);
end
if ~isempty(expectedNy)
    validateattributes(expectedNy, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'integer', 'positive'});
    ny = numel(unique(round(Tfield.Y, decimals)));
    assert(ny == expectedNy, ...
        'Spatial: esperado %d coordenadas Y; recebido %d.', expectedNy, ny);
end

%% Saidas
xGrid = Tfield.X;
yGrid = Tfield.Y;
cVals = Tfield.C;
phiVals = Tfield.phi;
EVals = Tfield.E;
end

function value = local_option(cfg, name, defaultValue)
if isfield(cfg, name) && ~isempty(cfg.(name))
    value = cfg.(name);
else
    value = defaultValue;
end
end
