# Convierte un archivo data/raw/<usuario>_<AAAA>_<MM>.json en filas CSV,
# una por partida, vistas desde el jugador analizado.
# Uso: jq -r --arg archivo <usuario>_<AAAA>_<MM>.json -f jq/partidas.jq <archivo>
#
# Columnas: url, end_time, jugador, rival, color, time_class, rules,
#           result propio, rating propio, rating rival, Result del PGN, ECO

($archivo | sub("_[0-9]{4}_[0-9]{2}\\.json$"; "")) as $jugador
| .games[]
| (if ((.white.username // "") | ascii_downcase) == $jugador then "blancas" else "negras" end) as $color
| (if $color == "blancas" then .white else .black end) as $propio
| (if $color == "blancas" then .black else .white end) as $rival
| [
    .url,
    .end_time,
    $jugador,
    (($rival.username // "") | ascii_downcase),
    $color,
    .time_class,
    .rules,
    $propio.result,
    $propio.rating,
    $rival.rating,
    ([(.pgn // "") | capture("\\[Result \"(?<r>[^\"]+)\"\\]") | .r] | first // ""),
    ([(.pgn // "") | capture("\\[ECO \"(?<e>[A-E][0-9]{2})\"\\]") | .e] | first // "")
  ]
| @csv
