function files = generate_images(v, f, cfg)
% GENERATE_IMAGES Guarda como PNG las imágenes marcadas en cfg.image.send (las que recibe el LLM).
%   files : celda con las rutas, en el orden features, waves, envelope, heatmap

persistent figures                                          % una figura invisible por imagen (se reutiliza)
kinds = image_kinds();                                      % las 4 imágenes posibles
files = {};
for k = 1:numel(kinds)
    kind = kinds{k};
    if ~cfg.image.send.(kind)                               % el usuario no la quiere enviar
        continue;
    end
    if ~isfield(figures, kind) || ~isgraphics(figures.(kind)) % primera vez o figura cerrada
        figures.(kind) = figure('Visible', 'off', 'Color', 'w', ...
            'Position', [100 100 cfg.image.width cfg.image.height]);
        axes(figures.(kind));                               % ejes de la figura
    end
    ax = findobj(figures.(kind), 'Type', 'axes');           % sus ejes
    if isempty(ax)                                          % la leyenda o el colorbar no cuentan
        ax = axes(figures.(kind));
    end
    draw_emg_image(ax(end), kind, v, f, cfg);               % mismo dibujo que en el dashboard
    file = fullfile(tempdir, ['emg_' kind '.png']);         % archivo temporal
    imwrite(print(figures.(kind), '-RGBImage', '-r0'), file); % captura y guarda
    files{end + 1} = file; %#ok<AGROW>
end
end
