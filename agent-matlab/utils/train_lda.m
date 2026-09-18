function lda_model = train_lda(calib, varargin)
    % TRAIN_LDA Entrena el clasificador LDA de respaldo con los datos de calibración.
    %
    % TRAIN_LDA Trains the fallback LDA classifier with the calibration data.
    %
    % Clases / Classes: pulgar, D2, D3, D4, D5
    % Características / Features: [RMS normalizado (8), MAV normalizado (8)] = 16
    %                             [normalized RMS (8), normalized MAV (8)] = 16
    %
    % DECISIÓN: LDA | RAZÓN: rápido (<1 ms por predicción), interpretable y baseline
    %   estándar en control mioeléctrico | ALTERNATIVA DESCARTADA: SVM (más lento),
    %   Random Forest (más memoria)
    % DECISION: LDA | REASON: fast (<1 ms per prediction), interpretable and the standard
    %   baseline in myoelectric control | DISCARDED ALTERNATIVE: SVM (slower),
    %   Random Forest (more memory)
    %
    % DECISIÓN: LDA en forma cerrada (W, b) con contracción (shrinkage) | RAZÓN: RMS y MAV
    %   están muy correlacionados y la covarianza puede ser casi singular; la forma cerrada
    %   permite clasificar con un producto matricial | ALTERNATIVA DESCARTADA: predict() de
    %   ClassificationDiscriminant en cada ciclo (sobrecarga de varios ms)
    % DECISION: closed-form LDA (W, b) with shrinkage | REASON: RMS and MAV are highly
    %   correlated and the covariance can be near-singular; closed form classifies with a
    %   single matrix product | DISCARDED ALTERNATIVE: ClassificationDiscriminant predict()
    %   every cycle (several ms of overhead)
    %
    % DECISIÓN: fitcdiscr (Statistics Toolbox) solo como verificación cruzada opcional |
    %   RAZÓN: el fallback de emergencia no debe depender de una licencia | ALTERNATIVA
    %   DESCARTADA: depender solo de fitcdiscr
    % DECISION: fitcdiscr (Statistics Toolbox) only as an optional cross-check |
    %   REASON: the emergency fallback must not depend on a license |
    %   DISCARDED ALTERNATIVE: relying on fitcdiscr only
    %
    % Entradas / Inputs:
    %   calib    : struct de calibración (features Nx16, labels Nx1 cellstr, class_names)
    %              calibration struct (features Nx16, labels Nx1 cellstr, class_names)
    %   varargin : 'Shrinkage' (0.1), 'KFold' (5), 'Verbose' (true)
    %
    % Salidas / Outputs:
    %   lda_model : struct con W, b, class_names, cv_accuracy, toolbox_cv_accuracy,
    %               is_trained, n_samples
    %
    % Ejemplo / Example:
    %   load('config/calibration.mat', 'calib');
    %   lda_model = train_lda(calib);

    p = inputParser;
    addParameter(p, 'Shrinkage', 0.1, @(x) isnumeric(x) && x >= 0 && x <= 1);
    addParameter(p, 'KFold', 5, @(x) isnumeric(x) && x >= 2);
    addParameter(p, 'Verbose', true, @(x) islogical(x) || isnumeric(x));
    parse(p, varargin{:});
    opts = p.Results;

    lda_model = struct('W', [], 'b', [], 'class_names', {{}}, 'cv_accuracy', NaN, ...
        'toolbox_cv_accuracy', NaN, 'is_trained', false, 'n_samples', 0, ...
        'shrinkage', opts.Shrinkage);

    if isempty(calib) || ~isfield(calib, 'features') || isempty(calib.features)
        logger('WARN', 'train_lda', ['Calibración sin características; LDA no entrenado / ' ...
            'Calibration without features; LDA not trained']);
        return;
    end

    X = double(calib.features);
    y = cellstr(calib.labels(:));
    class_names = cellstr(calib.class_names(:))';

    keep = ismember(y, class_names) & all(isfinite(X), 2);
    X = X(keep, :);
    y = y(keep);

    if numel(unique(y)) < 2
        logger('WARN', 'train_lda', 'Menos de 2 clases / Fewer than 2 classes');
        return;
    end

    [W, b] = fit_closed_form(X, y, class_names, opts.Shrinkage);

    lda_model.W = W;
    lda_model.b = b;
    lda_model.class_names = class_names;
    lda_model.is_trained = true;
    lda_model.n_samples = size(X, 1);

    % Validación cruzada propia / own cross-validation
    lda_model.cv_accuracy = cross_validate(X, y, class_names, opts.Shrinkage, opts.KFold);

    % Verificación con el toolbox si está disponible / toolbox check if available
    if exist('fitcdiscr', 'file') == 2
        try
            mdl = fitcdiscr(X, y, 'DiscrimType', 'linear', 'Gamma', opts.Shrinkage, ...
                'ClassNames', class_names);
            cv_mdl = crossval(mdl, 'KFold', opts.KFold);
            lda_model.toolbox_cv_accuracy = 1 - kfoldLoss(cv_mdl);
        catch err
            logger('DEBUG', 'train_lda', 'fitcdiscr no disponible / unavailable: %s', ...
                err.message);
        end
    end

    if opts.Verbose
        logger('INFO', 'train_lda', ...
            'LDA entrenado / trained: N=%d, CV=%.1f%% (toolbox CV=%.1f%%)', ...
            lda_model.n_samples, 100 * lda_model.cv_accuracy, ...
            100 * lda_model.toolbox_cv_accuracy);
    end
end

% -------------------------------------------------------------------------------------------
function [W, b] = fit_closed_form(X, y, class_names, shrinkage)
    % FIT_CLOSED_FORM Ajusta W y b de LDA con covarianza combinada y contracción.
    % FIT_CLOSED_FORM Fits LDA W and b with pooled covariance and shrinkage.
    n_classes = numel(class_names);
    n_features = size(X, 2);
    mu = zeros(n_classes, n_features);
    prior = zeros(n_classes, 1);
    pooled = zeros(n_features);
    global_mean = mean(X, 1);

    for k = 1:n_classes
        mask = strcmp(y, class_names{k});
        prior(k) = sum(mask);
        if prior(k) == 0
            mu(k, :) = global_mean;
            continue;
        end
        Xk = X(mask, :);
        mu(k, :) = mean(Xk, 1);
        centered = Xk - mu(k, :);
        pooled = pooled + centered' * centered;
    end

    dof = max(size(X, 1) - n_classes, 1);
    pooled = pooled / dof;
    sigma = (1 - shrinkage) * pooled + shrinkage * diag(diag(pooled));
    ridge = 1e-6 * max(trace(sigma) / n_features, eps);
    sigma = sigma + ridge * eye(n_features);

    prior = max(prior, 1) / sum(max(prior, 1));
    W = (sigma \ mu')';                                   % K x D
    b = -0.5 * sum(W .* mu, 2) + log(prior);              % K x 1
end

% -------------------------------------------------------------------------------------------
function accuracy = cross_validate(X, y, class_names, shrinkage, k_fold)
    % CROSS_VALIDATE Validación cruzada k-fold reproducible (semilla fija local).
    % CROSS_VALIDATE Reproducible k-fold cross-validation (fixed local seed).
    n = size(X, 1);
    k_fold = min(k_fold, n);
    stream = RandStream('mt19937ar', 'Seed', 0);
    folds = mod(randperm(stream, n), k_fold) + 1;
    correct = 0;
    for f = 1:k_fold
        test_mask = folds == f;
        train_mask = ~test_mask;
        if numel(unique(y(train_mask))) < 2
            continue;
        end
        [W, b] = fit_closed_form(X(train_mask, :), y(train_mask), class_names, shrinkage);
        scores = X(test_mask, :) * W' + b';
        [~, predicted] = max(scores, [], 2);
        correct = correct + sum(strcmp(class_names(predicted)', y(test_mask)));
    end
    accuracy = correct / n;
end
