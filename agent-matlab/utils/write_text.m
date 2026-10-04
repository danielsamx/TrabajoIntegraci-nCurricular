function write_text(file, text)
% WRITE_TEXT Guarda texto en un archivo UTF-8 (reemplaza su contenido).

fid = fopen(file, 'w', 'n', 'UTF-8');                       % abre el archivo para escribir
if fid < 0
    error('No se pudo escribir %s', file);                  % sin permiso o ruta inválida
end
fprintf(fid, '%s', text);                                   % escribe el texto (en UTF-8)
fclose(fid);                                                % cierra el archivo
end
