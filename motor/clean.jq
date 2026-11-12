
.games[]
| select(.rules == "chess" and .rated == true)
| . as $g
| ($g.pgn // "" | split("[Result \"")[1]? // "" | split("\"")[0]) as $r
| select(
    ($r == "1-0" and $g.white.result == "win" and $g.black.result != "win")
    or ($r == "0-1" and $g.black.result == "win" and $g.white.result != "win")
    or ($r == "1/2-1/2" and $g.white.result != "win" and $g.black.result != "win")
  )
|
{
  uuid: .uuid,
  url: .url,
  fecha_unix: .end_time,
  modalidad: .time_class,
  reglas: .rules,
  clasificatoria: .rated,
  blancas: .white.username,
  negras: .black.username,
  rating_blancas: .white.rating,
  rating_negras: .black.rating,
  rating_previo_blancas: .white.rating,
  rating_previo_negras: .black.rating,
  resultado_blancas: .white.result,
  resultado_negras: .black.result,
  resultado_pgn: (.pgn | split("[Result \"")[1] | split("\"")[0]),
  eco_codigo: (.pgn | split("[ECO \"")[1] | split("\"")[0]),
  familia_eco: (.pgn | split("[ECO \"")[1] | split("\"")[0] | .[0:1]),
  pgn: .pgn,
  apertura_url: .eco
}
