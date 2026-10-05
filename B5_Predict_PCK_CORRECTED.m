function y = B5_Predict_PCK_CORRECTED(modelPCK, X, muX, sdX, muY, sdY, batchSize)
% Avalia X fisico usando as estatisticas originais do Stage 3.
if nargin < 8
    batchSize = 10000;
end
y = B5_Utils_CORRECTED.B5_Predict_PCK( ...
    modelPCK, X, muX, sdX, muY, sdY, batchSize);
end
