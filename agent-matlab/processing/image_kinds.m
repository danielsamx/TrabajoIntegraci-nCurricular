function [kinds, titles, descriptions] = image_kinds()
% IMAGE_KINDS Las 3 imágenes posibles para el LLM: clave, título y descripción para el prompt.

kinds = {'features', 'waves', 'envelope'};
titles = {'Matriz de características', 'Ondas normalizadas', 'Envolvente general'};
descriptions = {
    ['Matriz de características: una fila por canal (CH1 a CH8) y una columna por característica ' ...
     '(RMS, MAV, WL = longitud de onda, ZC = cruces por cero, SSC = cambios de pendiente); cada ' ...
     'celda muestra su valor y es más oscura cuanto mayor es.']
    ['Ondas normalizadas: señal filtrada del último segundo de cada canal (CH1 arriba, CH8 abajo), ' ...
     'dividida por su RMS máximo.']
    ['Envolvente general: una sola curva, la media de las envolventes RMS de los 8 canales en el ' ...
     'último segundo (0 = reposo, 1 = máximo).']};
end
