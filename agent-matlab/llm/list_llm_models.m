function [models, report] = list_llm_models(llm)
% LIST_LLM_MODELS Pide GET /v1/models a cada puerto del servidor LLM.
%   models : nombres de los modelos disponibles (vacío si el servidor no responde)
%   report : una línea por puerto con OK o el motivo del fallo

models = {};                                                % modelos encontrados
report = {};                                                % resultado de cada puerto
options = weboptions('Timeout', 5, 'HeaderFields', {'Authorization', ['Bearer ' llm.api_key]});
for port = llm.ports                                        % cada puerto configurado
    url = sprintf('http://%s:%d/v1/models', llm.ip, port);  % lista de modelos de LM Studio
    try
        reply = webread(url, options);                      % petición GET
        data = reply.data;                                  % lista de modelos
        if ~iscell(data)
            data = num2cell(data);                          % array de structs -> celda
        end
        ids = cellfun(@(d) char(d.id), data, 'UniformOutput', false); % nombre de cada modelo
        models = [models, ids(:)']; %#ok<AGROW>
        report{end + 1} = sprintf('%s: OK (%d modelos)', url, numel(ids)); %#ok<AGROW>
    catch err
        report{end + 1} = sprintf('%s: %s', url, err.message); %#ok<AGROW>
    end
end
models = unique(models, 'stable');                          % sin repetidos
end
