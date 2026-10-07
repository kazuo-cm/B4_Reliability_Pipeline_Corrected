function result = B4_Run_Reliability_Metamodel(cfg)
% Executor B4: Stage 4 controla treinamento inicial e retreinamento.
if nargin < 1
    cfg = B4_DefaultConfig();
end
result = struct();
if cfg.run_stage4
    outAL = B4_Stage4_ActiveLearning(cfg);
    result.activeLearning = outAL;
    result.status = outAL.status;
    result.stopReason = outAL.stopReason;
    result.modelFile = outAL.modelFile;
    result.auditFile = outAL.auditFile;
else
    if cfg.run_stage0
        B4_Stage0_AlignData(cfg);
    end
    if cfg.run_stage1
        B4_Stage1_RankVariables(cfg);
    end
    if cfg.run_stage2
        B4_Stage2_SelectVariables(cfg);
    end
    if cfg.run_stage3
        B4_Stage3_TrainPCK(cfg);
    end
    result.status = "COMPLETED";
    result.stopReason = "STAGE4_DISABLED";
    result.modelFile = string(cfg.stage3_best_file);
    result.auditFile = "";
end
end
