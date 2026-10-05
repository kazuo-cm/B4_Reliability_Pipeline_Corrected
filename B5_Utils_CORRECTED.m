classdef B5_Utils_CORRECTED
    % Validacoes compartilhadas; entradas publicas sempre em unidades fisicas.
    methods (Static)
        function N = Normalization(S)
            keys = {'muX','sdX','muY','sdY'};
            contractKeys = {'input_mu','input_sigma','output_mu','output_sigma'};
            for k = 1:numel(keys)
                key = keys{k};
                candidates = {};
                if isfield(S, key)
                    candidates{end+1} = S.(key);
                end
                original = [key '_original'];
                if isfield(S, original)
                    candidates{end+1} = S.(original);
                end
                if isfield(S, 'Stage3Contract') && ...
                        isfield(S.Stage3Contract, contractKeys{k})
                    candidates{end+1} = S.Stage3Contract.(contractKeys{k});
                end
                assert(~isempty(candidates), 'B5:Normalization', ...
                    'Estatistica de normalizacao ausente: %s.', key);
                for j = 1:numel(candidates)
                    validateattributes(candidates{j}, {'numeric'}, ...
                        {'real','vector','nonempty','finite'});
                    candidates{j} = double(candidates{j}(:)');
                    assert(isequal(candidates{1}, candidates{j}), ...
                        'B5:Normalization', 'Estatisticas conflitantes: %s.', key);
                end
                N.(key) = candidates{1};
            end
            B5_Utils_CORRECTED.ValidateNormalization(N);
        end

        function ValidateNormalization(N)
            validateattributes(N.muX, {'numeric'}, {'real','vector','nonempty','finite'});
            validateattributes(N.sdX, {'numeric'}, {'real','vector','nonempty','finite','positive'});
            validateattributes(N.muY, {'numeric'}, {'real','scalar','finite'});
            validateattributes(N.sdY, {'numeric'}, {'real','scalar','finite','positive'});
            assert(numel(N.muX) == numel(N.sdX), 'B5:Normalization', ...
                'muX e sdX devem ter a mesma dimensao.');
        end

        function Xscaled = Standardize(X, N)
            B5_Utils_CORRECTED.ValidateNormalization(N);
            validateattributes(X, {'numeric'}, {'real','2d','finite'});
            assert(size(X,2) == numel(N.muX), 'B5:InputDimension', ...
                'Numero de colunas diferente do treinamento.');
            Xscaled = (double(X) - double(N.muX(:)')) ./ double(N.sdX(:)');
            assert(all(isfinite(Xscaled(:))), 'B5:Normalization', ...
                'Normalizacao de X produziu NaN ou Inf.');
        end

        function y = B5_Predict_PCK(modelPCK, X, muX, sdX, muY, sdY, batchSize)
            if nargin < 8
                batchSize = 10000;
            end
            validateattributes(batchSize, {'numeric'}, ...
                {'scalar','real','finite','integer','positive'});
            N = struct('muX',muX,'sdX',sdX,'muY',muY,'sdY',sdY);
            B5_Utils_CORRECTED.ValidateNormalization(N);
            validateattributes(X, {'numeric'}, {'real','2d','finite'});
            assert(size(X,2) == numel(muX), 'B5:InputDimension', ...
                'Numero de colunas diferente do treinamento.');
            y = zeros(size(X,1),1);
            for first = 1:batchSize:size(X,1)
                rows = first:min(first + batchSize - 1, size(X,1));
                Xscaled = B5_Utils_CORRECTED.Standardize(X(rows,:), N);
                yNorm = uq_evalModel(modelPCK, Xscaled);
                validateattributes(yNorm, {'numeric'}, {'real','finite'});
                assert(isvector(yNorm) && numel(yNorm) == numel(rows), ...
                    'B5:Prediction', 'O PCK deve retornar uma resposta por amostra.');
                y(rows) = double(yNorm(:)) .* double(sdY) + double(muY);
                assert(all(isfinite(y(rows))), 'B5:Prediction', ...
                    'Desnormalizacao de Y produziu NaN ou Inf.');
            end
        end

        function ids = ValidateIDs(ids, label)
            if isnumeric(ids)
                validateattributes(ids, {'numeric'}, {'real','vector','nonempty','finite'});
            else
                assert(isstring(ids) || iscellstr(ids) || iscategorical(ids), ...
                    'B5:IDs', '%s: tipo de ID nao suportado.', label);
                ids = string(ids);
                assert(isvector(ids) && ~isempty(ids) && ...
                    all(~ismissing(ids(:))) && all(strlength(strtrim(ids(:))) > 0), ...
                    'B5:IDs', '%s: IDs vazios ou ausentes.', label);
            end
            ids = ids(:);
            assert(numel(unique(ids)) == numel(ids), 'B5:DuplicateIDs', ...
                '%s: IDs duplicados; alinhamento rejeitado.', label);
        end

        function ValidateTableIDs(T, idColumn, label)
            assert(istable(T) && height(T) > 0, 'B5:Table', ...
                '%s: tabela vazia ou invalida.', label);
            assert(any(strcmp(T.Properties.VariableNames, idColumn)), ...
                'B5:IDs', '%s: coluna %s ausente.', label, idColumn);
            columns = unique([{char(idColumn)}, {'SampleID','SimulationID'}]);
            for k = 1:numel(columns)
                if any(strcmp(T.Properties.VariableNames, columns{k}))
                    B5_Utils_CORRECTED.ValidateIDs(T.(columns{k}), ...
                        [label '.' columns{k}]);
                end
            end
        end

        function names = ValidateNames(names, label)
            names = string(names(:)');
            assert(~isempty(names) && all(~ismissing(names)) && ...
                all(strlength(strtrim(names)) > 0) && ...
                numel(unique(names)) == numel(names), 'B5:Names', ...
                '%s: nomes vazios ou duplicados.', label);
        end

        function [r, keep] = SafeCorrelation(X, y, varianceTolerance)
            % Extensao de sensibilidade: nunca substituir correlacoes NaN por zero.
            if nargin < 3
                varianceTolerance = 1e-12;
            end
            validateattributes(varianceTolerance, {'numeric'}, ...
                {'scalar','real','finite','nonnegative'});
            validateattributes(X, {'numeric'}, {'real','2d','nonempty','finite'});
            validateattributes(y, {'numeric'}, {'real','vector','nonempty','finite'});
            y = double(y(:));
            assert(size(X,1) == numel(y) && numel(y) >= 2, ...
                'B5:Correlation', 'Amostras insuficientes ou dimensoes diferentes.');
            sx = std(double(X),0,1);
            sy = std(y);
            assert(all(isfinite(sx)) && isfinite(sy) && sy > varianceTolerance, ...
                'B5:Correlation', 'Variancia da resposta nula ou estatisticas invalidas.');
            keep = sx > varianceTolerance;
            if ~any(keep)
                r = zeros(0,1);
                return
            end
            r = corr(double(X(:,keep)), y);
            assert(all(isfinite(r(:))), 'B5:Correlation', ...
                'Correlacao nao finita; revisar dados.');
        end

        function value = PerturbPositiveRV(value, logIncrement)
            % Trabalhar no log evita overflow intermediario em value .* exp(delta).
            validateattributes(value, {'numeric'}, {'real','finite','positive'});
            validateattributes(logIncrement, {'numeric'}, {'real','finite'});
            assert(isscalar(logIncrement) || isequal(size(value),size(logIncrement)), ...
                'B5:RV', 'Perturbacao deve ser escalar ou ter o tamanho do RV.');
            logValue = log(double(value)) + double(logIncrement);
            assert(all(isfinite(logValue(:))) && ...
                all(logValue(:) >= log(realmin('double'))) && ...
                all(logValue(:) <= log(realmax('double'))), ...
                'B5:RV', 'Perturbacao fora do intervalo numerico representavel.');
            value = exp(logValue);
            assert(all(isfinite(value(:))) && all(value(:) > 0), ...
                'B5:RV', 'Perturbacao produziu overflow ou underflow.');
        end
    end
end
