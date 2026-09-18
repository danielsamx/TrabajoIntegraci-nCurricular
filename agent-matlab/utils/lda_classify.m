function [label, confidence, posteriors] = lda_classify(lda_model, features)
    % LDA_CLASSIFY Clasificación rápida con el modelo LDA en forma cerrada.
    %
    % LDA_CLASSIFY Fast classification with the closed-form LDA model.
    %
    % DECISIÓN: softmax de las funciones discriminantes como confianza | RAZÓN: con
    %   covarianza compartida, softmax(W*x + b) es exactamente la probabilidad posterior de
    %   LDA | ALTERNATIVA DESCARTADA: distancia de Mahalanobis cruda (no acotada en [0,1])
    % DECISION: softmax of the discriminant functions as confidence | REASON: with shared
    %   covariance, softmax(W*x + b) is exactly the LDA posterior probability |
    %   DISCARDED ALTERNATIVE: raw Mahalanobis distance (not bounded to [0,1])
    %
    % Entradas / Inputs:
    %   lda_model : struct devuelto por train_lda / struct returned by train_lda
    %   features  : vector 1x16 [rms_norm, mav_norm]
    %
    % Salidas / Outputs:
    %   label      : clase ganadora ('pulgar','D2'..'D5') o '' si no hay modelo
    %                winning class or '' if there is no model
    %   confidence : probabilidad posterior de la clase ganadora / winner posterior
    %   posteriors : vector 1xK de probabilidades / 1xK probability vector
    %
    % Ejemplo / Example:
    %   [label, conf] = lda_classify(lda_model, [rms_norm, mav_norm]);

    label = '';
    confidence = 0;
    posteriors = [];

    if isempty(lda_model) || ~isfield(lda_model, 'is_trained') || ~lda_model.is_trained
        return;
    end

    x = double(features(:)');
    if numel(x) ~= size(lda_model.W, 2)
        error('lda_classify:size', ...
            'Se esperaban %d características / %d features expected (got %d)', ...
            size(lda_model.W, 2), size(lda_model.W, 2), numel(x));
    end
    x(~isfinite(x)) = 0;

    scores = x * lda_model.W' + lda_model.b';
    scores = scores - max(scores);          % estabilidad numérica / numerical stability
    posteriors = exp(scores) / sum(exp(scores));

    [confidence, k] = max(posteriors);
    label = lda_model.class_names{k};
end
