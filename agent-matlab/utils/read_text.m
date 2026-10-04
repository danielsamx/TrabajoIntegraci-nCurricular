function text = read_text(file)
% READ_TEXT Lee un archivo de texto en UTF-8 (para conservar las tildes).

fid = fopen(file, 'r', 'n', 'UTF-8');                       % abre el archivo como UTF-8
if fid < 0
    error('No se pudo abrir %s', file);                     % el archivo no existe
end
text = fread(fid, [1 Inf], '*char');                        % lee todo el contenido
fclose(fid);                                                % cierra el archivo
text = strrep(text, char([13 10]), newline);                % saltos de línea de Windows -> \n
end
