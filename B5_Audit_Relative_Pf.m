function out = B5_Audit_Relative_Pf(report, rowInfo, varargin)
% Audit an already calculated B5 report without running UQLab or changing Pf.
% rowInfo has aligned Role, Scope and ReferenceRow columns (see README).
p = inputParser;
addParameter(p, 'ReferencePf', NaN, @local_pf_scalar);
addParameter(p, 'ReferenceMethod', "ReferencePf", @local_text_scalar);
addParameter(p, 'RunDir', "", @local_text_scalar);
addParameter(p, 'ModelFile', "", @local_text_scalar);
addParameter(p, 'Verbose', true, @(x) islogical(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;
assert(istable(report) && all(ismember({'Metodo', 'Pf', 'Status'}, ...
    report.Properties.VariableNames)), 'B5:AuditReport', ...
    'report must contain Metodo, Pf and Status.');
assert(istable(rowInfo) && height(rowInfo) == height(report) && ...
    all(ismember({'Role', 'Scope', 'ReferenceRow', 'AnalysisSucceeded'}, ...
    rowInfo.Properties.VariableNames)), ...
    'B5:AuditRows', 'rowInfo must align with every report row.');
n = height(report);
pf = report.Pf;
role = string(rowInfo.Role);
scope = string(rowInfo.Scope);
refs = rowInfo.ReferenceRow;
succeeded = rowInfo.AnalysisSucceeded;
assert(islogical(succeeded) && isequal(size(succeeded), [n, 1]), ...
    'B5:AuditAnalysisStatus', 'AnalysisSucceeded must be a logical column.');
assert(isnumeric(pf) && isreal(pf) && isequal(size(pf), [n, 1]), ...
    'B5:AuditPf', 'Pf must be a real numeric column.');
assert(all(ismember(role, ["reference", "estimate"])) && ...
    all(ismember(scope, ["training_al", "external", "base", "truncated", "unknown"])), ...
    'B5:AuditMetadata', 'Use documented Role and Scope values.');
assert(isnumeric(refs) && isreal(refs) && isequal(size(refs), [n, 1]) && ...
    all(isnan(refs) | (isfinite(refs) & refs >= 1 & refs <= n & refs == fix(refs))), ...
    'B5:AuditReferenceRows', 'ReferenceRow must be NaN or an existing row index.');
for i = find(~isnan(refs))'
    j = refs(i);
    assert(role(i) == "estimate" && role(j) == "reference" && ...
        scope(i) == scope(j) && ismember(scope(i), ["training_al", "external"]), ...
        'B5:AuditSameCases', 'Local references require matching empirical case-set scopes.');
end
counts = NaN(n, 1);
if ismember('SampleCount', rowInfo.Properties.VariableNames)
    counts = rowInfo.SampleCount;
    assert(isnumeric(counts) && isreal(counts) && isequal(size(counts), [n, 1]) && ...
        all(isnan(counts) | (isfinite(counts) & counts >= 0 & counts == fix(counts))), ...
        'B5:AuditSampleCount', 'SampleCount must contain nonnegative counts or NaN.');
end
runDir = string(opt.RunDir);
assert(~ismissing(runDir) && strlength(runDir) > 0, ...
    'B5:AuditRunDir', 'Provide the isolated run directory.');
if ~isfolder(runDir)
    mkdir(runDir);
end
automaticRows = find(role == "reference" & scope == "training_al");
assert(numel(automaticRows) <= 1 || ~isnan(opt.ReferencePf), ...
    'B5:AuditAmbiguousTraining', 'Identify a single RS2 training/AL reference.');
method = string(report.Metodo);
analysisStatus = string(report.Status);
timestamp = repmat(string(datetime('now', 'Format', ...
    'yyyy-MM-dd''T''HH:mm:ss.SSS')), n, 1);
referenceMethod = repmat("", n, 1);
referencePf = NaN(n, 1);
referenceSource = repmat("", n, 1);
referenceCount = NaN(n, 1);
absoluteDifference = NaN(n, 1);
relativeDifference = NaN(n, 1);
calculationStatus = repmat("not_calculated", n, 1);
reason = repmat("", n, 1);
comparisonScope = repmat("", n, 1);
interpretation = repmat("", n, 1);
formula = repmat("100*abs(PfEstimate-ReferencePf)/ReferencePf", n, 1);
for i = 1:n
    if role(i) == "reference"
        comparisonScope(i) = "empirical_reference:" + scope(i);
        interpretation(i) = "Empirical case-set reference, not global Pf truth.";
        reason(i) = "Reference row; no arbitrary zero relative difference.";
        if ~local_valid_pf(pf(i))
            reason(i) = reason(i) + " Invalid empirical Pf.";
        end
        if ~succeeded(i)
            reason(i) = reason(i) + " Empirical reference analysis failed.";
        end
    else
        j = NaN;
        if ~isnan(refs(i))
            j = refs(i);
            referenceSource(i) = "same_cases";
        elseif ~isnan(opt.ReferencePf)
            referenceSource(i) = "explicit";
            referencePf(i) = opt.ReferencePf;
            referenceMethod(i) = string(opt.ReferenceMethod);
        elseif ~isempty(automaticRows)
            j = automaticRows(1);
            referenceSource(i) = "automatic";
        end
        if ~isnan(j)
            referencePf(i) = pf(j);
            referenceMethod(i) = method(j);
            referenceCount(i) = counts(j);
        end
        if referenceSource(i) == "same_cases"
            comparisonScope(i) = "same_cases:" + scope(i);
            interpretation(i) = "Case-set surrogate/RS2 discrepancy; not global accuracy or convergence.";
        else
            comparisonScope(i) = "diagnostic:" + scope(i) + "_vs_" + referenceSource(i);
            interpretation(i) = "Diagnostic difference only; not evidence of accuracy or convergence.";
            if referenceSource(i) == "automatic"
                interpretation(i) = interpretation(i) + ...
                    " Adaptive RS2 training/AL is not necessarily representative of global Pf.";
            end
        end
        if scope(i) == "truncated"
            interpretation(i) = interpretation(i) + " Truncation changes the distribution.";
        end
        if referenceSource(i) == ""
            reason(i) = "No explicit reference or RS2 training/AL reference available.";
        elseif referencePf(i) == 0
            reason(i) = "Reference Pf is zero; relative division undefined (no artificial eps).";
        elseif ~local_valid_pf(referencePf(i))
            reason(i) = "Reference Pf is nonfinite or outside [0,1].";
        end
        if ~isnan(j) && ~succeeded(j)
            reason(i) = strtrim(reason(i) + " Reference analysis failed.");
        end
        if ~succeeded(i)
            reason(i) = strtrim(reason(i) + " Method analysis failed.");
        end
        if ~local_valid_pf(pf(i))
            reason(i) = strtrim(reason(i) + " Method Pf is nonfinite or outside [0,1].");
        end
        if reason(i) == ""
            absoluteDifference(i) = abs(pf(i) - referencePf(i));
            relativeDifference(i) = 100 * absoluteDifference(i) / referencePf(i);
            calculationStatus(i) = "calculated";
        elseif succeeded(i) && (isnan(j) || succeeded(j)) && ...
                local_valid_pf(pf(i)) && local_valid_pf(referencePf(i))
            absoluteDifference(i) = abs(pf(i) - referencePf(i));
        end
    end
    reason(i) = reason(i) + " Analysis status: " + analysisStatus(i) + ".";
    if ismember('Reason', rowInfo.Properties.VariableNames)
        detail = string(rowInfo.Reason(i));
        if ~ismissing(detail) && strlength(detail) > 0
            reason(i) = reason(i) + " " + detail;
        end
    end
end
audit = table(timestamp, method, pf, referenceMethod, referencePf, ...
    referenceSource, absoluteDifference, relativeDifference, formula, ...
    calculationStatus, reason, comparisonScope, interpretation, ...
    repmat(string(opt.ModelFile), n, 1), repmat(runDir, n, 1), ...
    counts, referenceCount, analysisStatus, ...
    'VariableNames', {'Timestamp', 'Method', 'PfEstimate', 'ReferenceMethod', ...
    'ReferencePf', 'ReferenceSource', 'AbsoluteDifference', ...
    'RelativeDifferencePercent', 'Formula', 'CalculationStatus', 'Reason', ...
    'ComparisonScope', 'Interpretation', 'ModelFile', 'runDir', ...
    'SampleCount', 'ReferenceSampleCount', 'AnalysisStatus'});
report.ErroRelativoPf_pct = relativeDifference;
report.ReferenciaErro = referenceMethod;
report.ComparisonScope = comparisonScope;
report.Interpretation = interpretation;
out = struct('report', report, 'relativeErrorAudit', audit, ...
    'relativeErrorAuditFile', fullfile(runDir, 'pf_relative_error_audit.csv'), ...
    'relativeErrorAuditMatFile', fullfile(runDir, 'pf_relative_error_audit.mat'));
writetable(audit, out.relativeErrorAuditFile);
relativeErrorAudit = audit;
relativeErrorAuditFile = out.relativeErrorAuditFile;
save(out.relativeErrorAuditMatFile, 'out', 'relativeErrorAudit', 'relativeErrorAuditFile');
if opt.Verbose
    fprintf('[B5 Pf audit] WARNING: differences are diagnostic, not proof of global accuracy/convergence.\n');
    for i = 1:n
        fprintf(['[B5 Pf audit] %s | Pf=%.10g | ref=%s (%.10g) | source=%s | ' ...
            'ref N=%.10g | abs=%.10g | relative=%.10g%% | %s | %s | %s\n'], ...
            method(i), pf(i), referenceMethod(i), referencePf(i), referenceSource(i), ...
            referenceCount(i), absoluteDifference(i), relativeDifference(i), ...
            calculationStatus(i), interpretation(i), reason(i));
    end
end
end

function valid = local_valid_pf(x)
valid = isfinite(x) && x >= 0 && x <= 1;
end

function valid = local_pf_scalar(x)
valid = isnumeric(x) && isreal(x) && isscalar(x);
end

function valid = local_text_scalar(x)
valid = (ischar(x) && isrow(x)) || (isstring(x) && isscalar(x));
end
