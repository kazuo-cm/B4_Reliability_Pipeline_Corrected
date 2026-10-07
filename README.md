# B4_Reliability_Pipeline_Corrected
Pipeline B4 corrigido: 10 fragilidades críticas resolvidas (6 fases). Integridade de dados, normalização numérica, validação CV, campo espacial.

## Stage 4: integração e uso

Arquivos MATLAB: `B4_Stage4_ActiveLearning.m`, `B4_DefaultConfig.m` e
`B4_Run_Reliability_Metamodel.m`. O executor incluído chama Stage 4 com saída
`outAL.status`, `stopReason`, `modelFile` e `auditFile`, sem duplicar o treinamento
inicial. O executor original citado no relato não estava neste repositório.

```matlab
cfg = B4_DefaultConfig('C:\Kazuo-Script');
% Ajuste os argumentos ao contrato do seu run_al_batch.py antes de executar.
result = B4_Run_Reliability_Metamodel(cfg);
```

**Dependências externas, não incluídas:** MATLAB com JVM e Statistics and Machine
Learning Toolbox, UQLab, Stages 0–1 originais, suporte
`B4_Suport_build_spatial_fields_from_xi`, `run_al_batch.py`, RS2 e dados/FEZ.
A integração real não foi executada neste ambiente, que não possui MATLAB/RS2.
Não há suíte de testes existente. A execução em produção precisa ser validada
com esses componentes; não são produzidas observações fictícias.

### Contratos externos

- CSVs de entrada: uma coluna `SampleID` **ou** `SimulationID`, IDs únicos,
  Xi em `xi_1`…`xi_N` e os 18 RVs com os nomes exatos do contrato Stage 3,
  distribuídos sem duplicatas entre os CSVs de materiais e liners.
- Configure `cfg.stage4_result_displacement_column` para a coluna real de
  deslocamento (padrão `Displacement_m`, em metros), tanto no treino como na
  saída RS2.
- `cfg.stage4_python_args` é uma lista de argumentos, não um comando de shell.
  As flags padrão são um contrato proposto e precisam corresponder ao script
  instalado, que não está neste repositório. Placeholders disponíveis:
  `{xi_file}`, `{material_rv_file}`, `{liner_rv_file}`, `{field_file}`,
  `{results_file}`, `{model_file}`, `{sim_id}`, `{expected_stage}`.
  O script deve gravar o CSV indicado em `{results_file}` após concluir RS2.
- A saída deve conter exatamente uma linha para o ID solicitado e deslocamento
  finito, não negativo. Se presentes, `Status` deve ser `OK`, `SUCCESS` ou
  `COMPLETED`, e `Stage` deve corresponder a `cfg.rs2_expected_stage`.
  Logs e entradas de cada tentativa ficam em `simulation_<ID>`.
- Com `cfg.stage4_execute_rs2 = false`, apenas resultados reais já presentes
  em `cfg.simulation_results_file` são lidos, sempre pelo ID exato.
- Suporte espacial: `[x,y,c,phi,E] =
  B4_Suport_build_spatial_fields_from_xi(xi,cfg)`. Saídas são arrays numéricos
  alinhados ou células por material; grades retangulares também são aceitas.
  O CSV exportado tem `MaterialID,X,Y,c,phi,E`. Células vazias são permitidas
  somente com `spatial_allow_missing_materials=true`; campo inteiramente vazio
  ou parcialmente inválido é rejeitado. O `cfg` completo é propagado ao suporte.

### Retreinamento, Pf e arquivos

Após aceitar um resultado real, Stage 4 salva os CSVs acumulados, executa
Stages 0–3 e recarrega o modelo e sua normalização. Confere se o treinamento
consumiu todos os casos aceitos. CSVs originais não são alterados.
Com `AL_RESET_ON_START=false`, os quatro CSVs acumulados são reutilizados
quando completos; o histórico de estabilidade começa novamente nessa execução.
Se houver observações acumuladas ainda não incorporadas ao modelo e todo
treinamento estiver desativado, a retomada é interrompida sem sobrescrever os
CSVs. Ative treinamento inicial ou `AL_RETRAIN_EACH_ITER` para incorporá-las.
Pastas de tentativas anteriores não são sobrescritas.

Pf usa uma população LHS física fixa, gerada por coluna sob demanda para evitar
uma matriz enorme com todos os Xi. Só os inputs selecionados são avaliados;
não se normaliza duas vezes a população do Stage 3. É a aproximação Gaussiana
estimada do Stage 3, **não** uma certificação de confiabilidade global.
Convergência exige retreinamento real, mínimo de casos novos, falhas suficientes
em cada leitura da janela e comparações consecutivas abaixo da tolerância.
Sem falhas suficientes, não há convergência automática nem fallback SS.
Desativar retreinamento também desativa a parada Pf.

Saídas: `audit_al_stage4.csv`, `pf_history.mat`, `stage4_result.mat`,
`augmented_xi.csv`, `augmented_results.csv`, `current_material_rv.csv`,
`current_liner_rv.csv` e snapshots `augmented_{xi,rv,results}_iterN.csv`.
`FAILED`/`RETRAIN_OR_PF_FAILED` indica que o último caso aceito pode ainda não
estar incorporado ao modelo; consulte a auditoria antes de usar o modelo.
