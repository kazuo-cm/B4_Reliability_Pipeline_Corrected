# B5 corrigido — confiabilidade com entradas físicas

## Escopo e arquivos

Este clone não continha os módulos B5 originais. Os arquivos abaixo são módulos
novos, independentes, com nomes MATLAB correspondentes aos arquivos. Não são
substituições transparentes de APIs B5 ausentes; use os pontos de entrada abaixo.
Não há ranking, seleção adicional, candidatos locais ou active learning no B5.

| Arquivo | Responsabilidade |
|---|---|
| `B5_Utils_CORRECTED.m` | Classe com normalização, previsão em lotes, IDs e utilitários numéricos |
| `B5_Predict_PCK_CORRECTED.m` | Função pública de previsão, delegando à classe |
| `B5_UQLab_Reliability_Skeleton_CORRECTED.m` | Carregamento e validação do modelo/contrato Stage 3 |
| `B5_Validate_LHS_Model_CORRECTED.m` | Alinhamento de tabelas Xi/RVs/resultados e métricas |
| `B5_Run_Reliability_Analysis_CORRECTED.m` | MCS com população fixa e FORM opcional |
| `B5_Compare_Pf_FORM_MCS_CORRECTED.m` | Frequências LHS observadas/preditas versus MCS/FORM |
| `B5_Official_Run_CORRECTED.m` | Coordenação e gravação dos resultados |

Dependências: MATLAB com suporte a tabelas, strings e expansão implícita,
UQLab com PCK e Reliability; `SafeCorrelation` também requer `corr`.
Não foram adicionadas dependências ao repositório.

## As dez fragilidades

1. **IDs antes de `ismember`.** Cada tabela deve ter a coluna de ID escolhida,
   sem valores ausentes, vazios, não finitos ou duplicados. Colunas `SampleID`
   e `SimulationID`, quando presentes, também são validadas. Os IDs salvos do
   treinamento são validados ao carregar o modelo.
2. **Variância quase nula antes de correlações.** B5 não calcula ranking.
   `SafeCorrelation(X,y,tol)` prepara extensões: remove colunas com
   `std(X) <= tol` e retorna a máscara `keep`. Se todas forem removidas,
   retorna uma correlação vazia, não um score fictício.
3. **NaN em correlações.** O utilitário exige dados finitos, pelo menos duas
   amostras e resposta não constante. Correlações residuais não finitas causam
   erro; exceções não são silenciadas nem convertidas em zero.
4. **Normalização robusta.** Todas as previsões recebem `X` físico, na ordem
   exata de `vars_train`. Aplicam `(X - muX) ./ sdX`, avaliam o PCK e retornam
   `yNorm .* sdY + muY`. Médias devem ser finitas; desvios devem ser finitos e
   estritamente positivos. Dimensões, entradas, saídas e resultados das
   transformações são verificados. As estatísticas nunca são reestimadas no B5.
   São aceitos os campos `muX/sdX/muY/sdY`, os campos B4 `*_original` e os campos
   equivalentes do contrato; fontes simultâneas devem concordar exatamente.
5. **CV condicional.** Exige métricas `Perf.R2_CV` e `Perf.LOO` finitas,
   LOO não negativo e `R2_CV >= 0.5`. A CV é **condicional ao conjunto já
   selecionado**; não mede a seleção dentro dos folds, nem valida externamente
   o pipeline inteiro. Métricas LHS e coincidências com IDs do treinamento
   também não demonstram independência dos dados.
6. **Campos espaciais.** Estes módulos consomem colunas Xi/RVs finitas; não
   reconstroem nem perturbam campos espaciais. Portanto, não há coordenadas,
   envelope de campo ou transições inter-material a validar aqui. Qualquer
   extensão que reconstrua campos deverá validar esses atributos **antes**
   de avaliar o surrogate; a validação de Xi não certifica o campo físico.
7. **Contrato uniforme.** O carregamento exige
   `model_input_representation = 'standardized'`,
   `input_normalization = 'standardization'` e
   `external_input_transform = '(X - muX) ./ sdX'`. Nomes no contrato,
   quando presentes, devem coincidir com `vars_train`, inclusive na ordem.
8. **Alinhamento seguro.** `local_match_ids` valida ambos os vetores antes de
   `setdiff` e `ismember`. As tabelas devem conter exatamente o mesmo conjunto
   de IDs e o mesmo tipo de ID; não há truncamento, conversão implícita,
   replicação, interseção silenciosa ou alinhamento por número de linha.
   Cada variável selecionada deve aparecer em exatamente uma tabela.
9. **População Pf fixa.** MCS gera uma única matriz física com `n_mcs` linhas
   e a preserva em `R.Pf_population`. Ela pode ser reutilizada por
   `options.Pf_population`, com dimensão idêntica e nomes de colunas explícitos
   em `options.Pf_population_names`, na ordem treinada. Não há reamostragem por lote,
   parada após certo número de falhas ou alegação de convergência Stage 3.
   O usuário deve manter a mesma distribuição física ao reutilizá-la.
10. **Overflow/underflow em RVs.** Não existem perturbações locais no B5.
    Para extensões de RVs positivos, `PerturbPositiveRV(value,logIncrement)`
    calcula `log(value) + logIncrement`, verifica representabilidade antes de
    `exp` e rejeita overflow/underflow, em vez de alterar silenciosamente a
    distribuição por clamping. Não é uma transformação para Poisson nem
    implementa os limites físicos específicos de cada material.

## Ajuste necessário no exportador B4

`B4_Stage3_TrainPCK.m` já treinava com `Xtr_scaled`, mas exportava
`external_input_transform = 'none'` e não incluía `model_input_representation`.
Foi corrigido **somente esse metadado**, adicionando também `cv_scope`.
`input_representation = 'physical'` continua descrevendo as entradas públicas;
`model_input_representation = 'standardized'` descreve as entradas do PCK.
O treinamento, a seleção e as estatísticas não foram alterados.

Arquivos MAT antigos com esse contrato incompleto serão rejeitados: regenere
o artefato com o exportador corrigido. Não inferir silenciosamente o espaço
do modelo nem remover as verificações para aceitar um MAT antigo.

O cálculo CV já existente no B4 não foi reimplementado nesta mudança. A
disponibilidade de `CV_Rsquared` depende do artefato/implementação de treinamento;
não presumir que `Meta.CV` produza esse campo em toda versão do UQLab. Se o
treinamento não gerar métricas CV finitas, ele precisa de validação k-fold
efetiva antes de exportar o modelo; o B5 não fabrica métricas nem transforma
automaticamente LOO em R² de k-fold.

`valid_for_global_pf_sampling = false` permanece inalterado. O input UQLab
salvo no Stage 3 é uma aproximação Gaussiana **normalizada**, não a distribuição
física conjunta para Pf. B5 exige um `physical_input_options` explícito, com
todos os nomes na ordem treinada, marginais com momentos finitos e desvio
positivo e, quando aplicável, a cópula/dependência física correta. Fornecer
esse input não certifica generalização global: o B5 emite um aviso, e o usuário
deve validar a cobertura do treinamento e o erro do surrogate na região de falha.

## Uso

Adicione os arquivos ao MATLAB path e inicialize/configure o UQLab.
Use caminhos absolutos para os arquivos de modelo, CSVs e saída.

```matlab
cfgB4 = B4_DefaultConfig();
C = B5_UQLab_Reliability_Skeleton_CORRECTED(cfgB4.stage3_best_file);

% Xphysical: N x numel(C.names), unidades físicas e ordem de C.names.
yPred = C.predict(Xphysical);
% Equivalente, inclusive com controle do tamanho dos lotes:
N = C.normalization;
yPred = B5_Predict_PCK_CORRECTED(C.modelPCK, Xphysical, ...
    N.muX, N.sdX, N.muY, N.sdY, 10000);
```

Orquestração completa:

```matlab
cfg.model_file = cfgB4.stage3_best_file;
cfg.out_dir = fullfile(cfgB4.out_dir, 'B5_corrected');
% physicalInputOptions deve ser definido a partir da distribuição física
% validada do problema, não copiando C.modelPCK ou o inputModel do Stage 3.
cfg.physical_input_options = physicalInputOptions;
cfg.reliability_options = struct('n_mcs',50000,'seed',1,'run_form',true);
cfg.lhs_input_tables = {xiTable, materialRVTable, linerRVTable};
cfg.lhs_results = resultsTable;
cfg.validation_options = struct('id_column','SampleID', ...
    'response_column','Displacement_m');
R = B5_Official_Run_CORRECTED(cfg);
```

As tabelas podem ser objetos `table` ou caminhos absolutos de CSVs.
Para `SimulationID`, escolha explicitamente `id_column = 'SimulationID'`
em todas as tabelas. Nomes de colunas são preservados na leitura dos CSVs.
O ID selecionado deve designar a mesma amostra em cada arquivo. Todos os
arquivos devem representar o mesmo conjunto de amostras; filtre explicitamente
antes da chamada quando quiser validar apenas um subconjunto.

`lhs_input_tables` e `lhs_results` são opcionais, mas devem ser fornecidos
juntos. A execução oficial verifica os dados LHS antes da análise de Pf.
O estado limite é `g = limit_m - displacement`, com falha em `g <= 0`.
FORM e MCS usam a mesma função de previsão física. Erros UQLab são propagados.
FORM exige diagnóstico `Results.History.ExitFlag` compatível com UQLab 2.1:
parada pelos dois critérios de tolerância ou `g_X = 0`. Limite de iterações,
gradiente nulo sem convergência e diagnósticos ausentes/desconhecidos são
rejeitados, mesmo quando UQLab retornar um Pf finito. Isso não prova que o ponto
encontrado é o mínimo global. FORM pode ser desativado com `run_form = false`.

MCS retorna `Pf`, `N`, `NFailures`, `StandardError` e `CoV`. Se não houver
falhas, `CoV = Inf`, o status explicita a limitação e
`ZeroFailuresUpper95` fornece o limite binomial unilateral de 95%; `Pf = 0`
não é prova de risco nulo. Frequências LHS não recebem interpretação de
intervalo de confiança binomial iid nem são chamadas de MCS independente.

Para reutilizar a população sem alterar o estado global do gerador aleatório:

```matlab
opts = cfg.reliability_options;
opts.Pf_population = R.reliability.Pf_population;
opts.Pf_population_names = R.reliability.Pf_population_names;
Rfixed = B5_Run_Reliability_Analysis_CORRECTED(C,physicalInputOptions,opts);
assert(isequal(Rfixed.Pf_population,R.reliability.Pf_population));
```

São gravados `B5_results.mat` (incluindo população fixa e contrato),
`B5_LHS_predictions.csv` e `B5_Pf_comparison.csv` (quando houver dados LHS).
O uso de uma mesma pasta sobrescreve essas saídas.

## Verificação e regressões para executar no MATLAB

O repositório não possui suíte de testes, nem MATLAB/Octave/UQLab no ambiente
de implementação. Os exemplos abaixo são verificações manuais propostas,
**não testes executados**. A revisão estática não substitui executar FORM/MCS
com a versão instalada do UQLab e dados reais.

```matlab
N = struct('muX',[10 100],'sdX',[2 20],'muY',0.1,'sdY',0.01);
assert(isequal(B5_Utils_CORRECTED.Standardize([12 80],N),[1 -1]));
assert(isequal(B5_Utils_CORRECTED.Standardize([10 100],N),[0 0]));

rejected = false;
try
    B5_Utils_CORRECTED.ValidateIDs([1 2 2],'teste');
catch ME
    rejected = strcmp(ME.identifier,'B5:DuplicateIDs');
end
assert(rejected);

bad = N; bad.sdX(2) = 0;
rejected = false;
try
    B5_Utils_CORRECTED.Standardize([12 80],bad);
catch
    rejected = true;
end
assert(rejected);

% O tamanho explicito de lote deve ser respeitado e validado.
rejected = false;
try
    B5_Predict_PCK_CORRECTED([],zeros(0,2),N.muX,N.sdX,N.muY,N.sdY,0);
catch
    rejected = true;
end
assert(rejected);

[r,keep] = B5_Utils_CORRECTED.SafeCorrelation([ones(3,1),(1:3)'],(1:3)');
assert(isequal(keep,[false true]) && abs(r-1) < 1e-12);
assert(abs(B5_Utils_CORRECTED.PerturbPositiveRV(2,log(3))-6) < 1e-12);

% Testar alinhamento fora de ordem, sem depender do UQLab:
Ctest.names = ["x1" "x2"];
Ctest.predict = @(X) sum(X,2);
Ctest.trainingIDs = [100;101];
Ti = table([2;1],[20;10],[2;1], ...
    'VariableNames',{'SampleID','x1','x2'});
Tr = table([1;2],[11;22], ...
    'VariableNames',{'SampleID','Displacement_m'});
V = B5_Validate_LHS_Model_CORRECTED(Ctest,Ti,Tr);
assert(V.RMSE_m == 0 && isequal(V.predictions.Predicted_m,[11;22]));

% No modelo real, comparar lotes com a transformacao direta:
S = load(cfg.model_file,'Xtr');
C = B5_UQLab_Reliability_Skeleton_CORRECTED(cfg.model_file);
N = C.normalization;
expected = uq_evalModel(C.modelPCK,(S.Xtr-N.muX)./N.sdX);
expected = double(expected(:)).*N.sdY+N.muY;
batched = B5_Predict_PCK_CORRECTED(C.modelPCK,S.Xtr, ...
    N.muX,N.sdX,N.muY,N.sdY,7);
assert(norm(expected-batched,Inf) <= 1e-10*max(1,norm(expected,Inf)));
```

Verifique também rejeição de IDs extras/ausentes, duplicatas em cada tabela,
`muY = NaN`, `sdY <= 0`, nomes fora de ordem, previsões NaN/Inf, contrato
antigo e perturbações fora do intervalo representável. Para resposta observada
constante, R² é explicitamente indefinido (`NaN` com aviso e status), enquanto
RMSE/MAE continuam definidos; isso não é um NaN silencioso.
