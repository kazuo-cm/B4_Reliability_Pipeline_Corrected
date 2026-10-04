function B4_Stage2_SelectVariables(cfg)
% Selecao obrigatoria dos 18 RVs + Xi relevantes.

fprintf('\n[Etapa2] Selecao Xi + RVs obrigatorios...\n');

S = load(fullfile(cfg.out_dir, 'stage1_screening.mat'));

X = double(S.X_filtered);
y = double(S.y(:));
vars = string(S.vars_filtered(:))';
rankT = S.rankT;
Xi = S.Xi;
RV = S.RV;
sampleID = S.sampleID;
rvNames = string(S.rvNames(:))';
Stage0Contract = S.Stage0Contract;

validateattributes(cfg.stage2_topK, {'numeric'}, ...
    {'scalar','integer','>=',18});
validateattributes(cfg.stage2_relevance_target, {'numeric'}, ...
    {'scalar','real','finite','>',0,'<=',1});
validateattributes(cfg.stage2_corr_xx_thr, {'numeric'}, ...
    {'scalar','real','finite','>=',0,'<=',1});

[found, rvLoc] = ismember(rvNames, vars);
assert(all(found) && numel(rvLoc) == 18, ...
    'Stage2: RV obrigatorio ausente.');

rankT = sortrows(rankT, 'Score', 'descend');
xiRank = rankT(~ismember(string(rankT.Variable), rvNames),:);

% topK inclui os 18 RVs.
kmax = min(cfg.stage2_topK - 18, height(xiRank));
rankT2 = xiRank(1:kmax,:);

if kmax > 0
    weights = double(rankT2.Score);
    assert(all(isfinite(weights)) && all(weights >= 0), ...
        'Stage2: scores invalidos.');

    total = sum(weights);

    if total > 0
        weights = weights / total;
    else
        warning('B4:ZeroXiScores', ...
            'Stage2: scores Xi nulos; usando pesos iguais.');
        weights = ones(kmax,1) / kmax;
    end

    cumulativeWeight = cumsum(weights);
    k = find(cumulativeWeight >= cfg.stage2_relevance_target, ...
        1, 'first');

    if isempty(k)
        k = kmax;
    end

    topXi = string(rankT2.Variable(1:k));
else
    cumulativeWeight = zeros(0,1);
    topXi = strings(0,1);
end

% Comeca com TODOS os RVs obrigatorios.
selectedLoc = rvLoc(:)';

[foundXi, xiLoc] = ismember(topXi, vars);
assert(all(foundXi), 'Stage2: Xi do ranking nao encontrado.');

for j = 1:numel(xiLoc)
    candidateLoc = xiLoc(j);
    maxCorrelation = 0;

    for existingLoc = selectedLoc
        c = corr(X(:,candidateLoc), X(:,existingLoc), ...
            'Rows', 'complete');

        if isfinite(c)
            maxCorrelation = max(maxCorrelation, abs(c));
        end
    end

    if maxCorrelation <= cfg.stage2_corr_xx_thr
        selectedLoc(end+1) = candidateLoc; %#ok<AGROW>
    end
end

vars_sel = vars(selectedLoc);
X_sel = X(:,selectedLoc);

assert(isequal(vars_sel(1:18), rvNames), ...
    'Stage2: ordem dos RVs obrigatorios inconsistente.');

selectedTable = table(vars_sel(:), ...
    ismember(vars_sel(:), rvNames), ...
    'VariableNames', {'Variable','MandatoryRV'});

writetable(selectedTable, ...
    fullfile(cfg.out_dir, 'stage2_selected_vars.csv'));

save(fullfile(cfg.out_dir, 'stage2_selection.mat'), ...
    'X_sel','vars_sel','X','vars','y','rankT','rankT2', ...
    'sampleID','Xi','RV','rvNames','selectedLoc', ...
    'cumulativeWeight','Stage0Contract','cfg','-v7.3');

fprintf('[Etapa2] Selecionadas: 18 RVs + %d Xi = %d.\n', ...
    numel(vars_sel)-18, numel(vars_sel));
end