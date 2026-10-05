function tests = test_B5_Audit_Relative_Pf
tests = functiontests(localfunctions);
end

function setup(testCase)
testCase.TestData.runDir = tempname;
mkdir(testCase.TestData.runDir);
end

function teardown(testCase)
rmdir(testCase.TestData.runDir, 's');
end

function testExplicitReference(testCase)
[report, rows] = local_fixture;
out = local_run(testCase, report, rows, 'ReferencePf', 0.085784);
a = out.relativeErrorAudit;
verifyEqual(testCase, a.ReferenceSource(5), "explicit");
verifyEqual(testCase, a.RelativeDifferencePercent(5), ...
    100 * abs(0.0475 - 0.085784) / 0.085784);
verifyEqual(testCase, a.ReferencePf(5), 0.085784);
verifyTrue(testCase, isnan(a.ReferenceSampleCount(5)));
verifyTrue(testCase, all(isnan(a.RelativeDifferencePercent(1:2))));
verifyEqual(testCase, a.ReferenceSource(3:4), repmat("same_cases", 2, 1));
verifyEqual(testCase, a.ReferencePf(3), report.Pf(1));
end

function testAutomaticReference(testCase)
[report, rows] = local_fixture;
out = local_run(testCase, report, rows);
a = out.relativeErrorAudit;
verifyEqual(testCase, a.ReferenceSource(5:9), repmat("automatic", 5, 1));
verifyEqual(testCase, a.ReferencePf(5:9), repmat(report.Pf(2), 5, 1));
verifyEqual(testCase, a.ReferenceSampleCount(5:9), repmat(1200, 5, 1));
verifyTrue(testCase, contains(a.Interpretation(5), "not necessarily representative"));
verifyTrue(testCase, contains(a.Interpretation(8), "Truncation changes"));
verifyTrue(testCase, startsWith(a.ComparisonScope(8), "diagnostic:truncated"));
end

function testIntegerPfUsesFloatingPointArithmetic(testCase)
[report, rows] = local_fixture;
report.Pf = uint8(ones(9, 1));
report.Pf(5) = 0;
out = local_run(testCase, report, rows, 'ReferencePf', uint8(1));
verifyEqual(testCase, out.relativeErrorAudit.AbsoluteDifference(5), 1);
verifyEqual(testCase, out.report.ErroRelativoPf_pct(5), 100);
verifyEqual(testCase, out.report.Pf, report.Pf);
end

function testZeroReference(testCase)
[report, rows] = local_fixture;
report.Pf(2) = 0;
out = local_run(testCase, report, rows);
verifyTrue(testCase, isnan(out.report.ErroRelativoPf_pct(5)));
verifyTrue(testCase, contains(out.relativeErrorAudit.Reason(5), "zero"));
verifyEqual(testCase, out.relativeErrorAudit.AbsoluteDifference(5), report.Pf(5));
out = local_run(testCase, report, rows, 'ReferencePf', 0);
verifyEqual(testCase, out.relativeErrorAudit.ReferenceSource(5), "explicit");
verifyTrue(testCase, isnan(out.report.ErroRelativoPf_pct(5)));
end

function testNaNAndFailedAnalysis(testCase)
[report, rows] = local_fixture;
report.Pf(2) = NaN;
report.Pf(6) = NaN;
rows.AnalysisSucceeded(5) = false;
report.Status(5) = "FAILED";
rows.Reason(5) = "UQLab unavailable.";
out = local_run(testCase, report, rows);
verifyTrue(testCase, all(isnan(out.report.ErroRelativoPf_pct(5:9))));
verifyTrue(testCase, contains(out.relativeErrorAudit.Reason(6), "Method Pf is nonfinite"));
out = local_run(testCase, report, rows, 'ReferencePf', 0.1);
verifyTrue(testCase, isnan(out.report.ErroRelativoPf_pct(5)));
verifyTrue(testCase, contains(out.relativeErrorAudit.Reason(5), "Method analysis failed"));
verifyTrue(testCase, contains(out.relativeErrorAudit.Reason(5), "UQLab unavailable"));
verifyTrue(testCase, isnan(out.relativeErrorAudit.AbsoluteDifference(5)));
verifyEqual(testCase, out.relativeErrorAudit.CalculationStatus(7), "calculated");
end

function testMissingAndFailedReference(testCase)
[report, rows] = local_fixture;
rows.Scope(2) = "unknown";
rows.ReferenceRow(4) = NaN;
out = local_run(testCase, report, rows);
verifyTrue(testCase, contains(out.relativeErrorAudit.Reason(5), "No explicit reference"));
[report, rows] = local_fixture;
rows.AnalysisSucceeded(2) = false;
out = local_run(testCase, report, rows);
verifyTrue(testCase, contains(out.relativeErrorAudit.Reason(5), "Reference analysis failed"));
verifyTrue(testCase, isnan(out.report.ErroRelativoPf_pct(5)));
end

function testInvalidExplicitReferenceDoesNotFallback(testCase)
[report, rows] = local_fixture;
for value = [Inf, -1, 2]
    out = local_run(testCase, report, rows, 'ReferencePf', value);
    verifyEqual(testCase, out.relativeErrorAudit.ReferenceSource(5), "explicit");
    verifyTrue(testCase, isnan(out.report.ErroRelativoPf_pct(5)));
end
end

function testExternalReplacementRecalculated(testCase)
[report, rows] = local_fixture;
training = local_run(testCase, report, rows);
report.Metodo(4) = "RF_5Mat_3Var_400Sim_metamodelo";
report.Pf(4) = 0.0475;
rows.Scope(4) = "external";
rows.ReferenceRow(4) = 1;
rows.SampleCount(4) = 400;
external = local_run(testCase, report, rows);
verifyEqual(testCase, external.relativeErrorAudit.ReferencePf(4), report.Pf(1));
verifyEqual(testCase, external.report.ErroRelativoPf_pct(4), ...
    100 * abs(report.Pf(4) - report.Pf(1)) / report.Pf(1));
verifyNotEqual(testCase, external.report.ErroRelativoPf_pct(4), ...
    training.report.ErroRelativoPf_pct(4));
% An external evaluation without matching RS2 uses only the diagnostic fallback.
rows.ReferenceRow(4) = NaN;
external = local_run(testCase, report, rows);
verifyEqual(testCase, external.relativeErrorAudit.ReferenceSource(4), "automatic");
verifyEqual(testCase, external.relativeErrorAudit.ComparisonScope(4), ...
    "diagnostic:external_vs_automatic");
end

function testSilentPersistenceAndConsistency(testCase)
[report, rows] = local_fixture;
console = evalc('out = local_run(testCase, report, rows);');
verifyEqual(testCase, console, '');
a = out.relativeErrorAudit;
verifyEqual(testCase, height(a), height(report));
verifyEqual(testCase, out.report.Pf, report.Pf);
verifyEqual(testCase, out.report.Status, report.Status);
verifyEqual(testCase, out.report.ErroRelativoPf_pct, a.RelativeDifferencePercent);
verifyEqual(testCase, out.report.ReferenciaErro, a.ReferenceMethod);
csv = readtable(out.relativeErrorAuditFile, 'TextType', 'string');
verifyEqual(testCase, csv.Method, a.Method);
verifyEqual(testCase, csv.RelativeDifferencePercent, a.RelativeDifferencePercent, 'AbsTol', 1e-10);
verifyEqual(testCase, csv.ReferencePf, a.ReferencePf, 'AbsTol', 1e-12);
verifyEqual(testCase, csv.CalculationStatus, a.CalculationStatus);
verifyEqual(testCase, csv.Reason, a.Reason);
verifyEqual(testCase, csv.ComparisonScope, a.ComparisonScope);
saved = load(out.relativeErrorAuditMatFile);
verifyEqual(testCase, saved.relativeErrorAudit, a);
verifyEqual(testCase, saved.relativeErrorAuditFile, out.relativeErrorAuditFile);
verifyEqual(testCase, saved.out, out);
verifyTrue(testCase, all(a.ModelFile == ""));
end

function testVerboseInterpretation(testCase)
[report, rows] = local_fixture;
console = evalc(['out = B5_Audit_Relative_Pf(report, rows, ' ...
    '''RunDir'', testCase.TestData.runDir, ''Verbose'', true);']);
verifyTrue(testCase, contains(console, "WARNING"));
verifyTrue(testCase, contains(console, "Truncation changes"));
verifyTrue(testCase, contains(console, "ref N=1200"));
verifyEqual(testCase, count(string(console), "[B5 Pf audit]"), height(report) + 1);
end

function testRejectMismatchedLocalReference(testCase)
[report, rows] = local_fixture;
rows.ReferenceRow(3) = 2;
verifyError(testCase, @() local_run(testCase, report, rows), 'B5:AuditSameCases');
end

function out = local_run(testCase, report, rows, varargin)
out = B5_Audit_Relative_Pf(report, rows, 'RunDir', ...
    testCase.TestData.runDir, 'Verbose', false, varargin{:});
end

function [report, rows] = local_fixture
report = table(["RS2 RF400"; "RS2 treinamento/AL"; "surrogate RF400"; ...
    "surrogate treinamento/AL"; "FORM base"; "MCS base"; "SS base"; ...
    "FORM truncada"; "MCS truncada"], ...
    [0.1; 0.085784; 0.08; 0.085; 0.0475; 0.06; 0.062; 0.04; 0.045], ...
    repmat("OK", 9, 1), 'VariableNames', {'Metodo', 'Pf', 'Status'});
rows = table(["reference"; "reference"; repmat("estimate", 7, 1)], ...
    ["external"; "training_al"; "external"; "training_al"; ...
    repmat("base", 3, 1); repmat("truncated", 2, 1)], ...
    [NaN; NaN; 1; 2; NaN(5, 1)], true(9, 1), ...
    [400; 1200; 400; 1200; NaN; 10000; NaN; NaN; 10000], repmat("", 9, 1), ...
    'VariableNames', {'Role', 'Scope', 'ReferenceRow', 'AnalysisSucceeded', ...
    'SampleCount', 'Reason'});
end
