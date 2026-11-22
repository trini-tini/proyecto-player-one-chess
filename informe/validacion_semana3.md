# Validación con curl y jq — Semana 3

## Objetivo

Validar la información obtenida desde la API pública de Chess.com mediante una consulta independiente utilizando `curl` y `jq`, y compararla con los resultados del comando `ch puzzle --tablero`.

## 1. Consulta inicial

Se ejecutó el siguiente comando:

```bash
curl -s https://api.chess.com/pub/puzzle | jq '{title, fen}'
```

La consulta produjo un error de interpretación JSON:

```text
jq: parse error: Invalid numeric literal at line 1, column 10
```

Al revisar la respuesta HTTP, se identificó que Chess.com devolvía un código 403, correspondiente a un bloqueo de Cloudflare. La respuesta era HTML en lugar de JSON.

## 2. Consulta con User-Agent personalizado

Se utilizó el mismo identificador HTTP configurado en el proyecto:

```nu
^curl -sS -A $"PlayerOne-UBB/1.0 \(contacto: ($env.CHESS_EMAIL)\)" https://api.chess.com/pub/puzzle | ^jq '{title, fen}'
```

La consulta respondió correctamente y permitió extraer los campos solicitados.

Resultado:

```json
{
  "title": "That's Forking Deep 🤯",
  "fen": "r1b1k2r/1p3ppp/p2Q1n2/q1pPp3/1n2B3/1P1N4/P1PB1PPP/R3K2R b Qkq - 0 1"
}
```

## 3. Comparación con ch puzzle --tablero

Se ejecutó previamente el comando:

```nu
ch puzzle --tablero
```

El comando mostró un tablero de 8×8 construido a partir de la posición FEN y devolvió el mismo título y la misma cadena FEN obtenidos mediante `curl` y `jq`.

Por lo tanto, se comprobó la coincidencia entre los datos entregados por `ch puzzle` y los extraídos mediante la consulta independiente.

## 4. Conclusión

La validación permitió comprobar que:

- La API de Chess.com entrega los campos `title` y `fen` correctamente cuando la solicitud incluye el User-Agent del proyecto.
- El comando `ch puzzle --tablero` mostró la posición correspondiente al FEN consultado.
- La extracción independiente mediante `curl` y `jq` produjo los mismos valores observados en el comando del proyecto.

Esta prueba muestra evidencia de consistencia entre la respuesta de la API y la información presentada por Player One.

## 5. Validación de un resultado intermedio del pipeline

Se tomó la última partida de `alvaropuchi` en `data/partidas_limpias.csv` (corrida oficial del 22-nov-2026):

```text
url,fecha_fin,jugador,rival,color,modalidad,eco,familia_eco,resultado,rating_previo,rating_rival
https://www.chess.com/game/live/187728523870,2026-11-21 23:06:11,alvaropuchi,davidzurita23,negras,rapid,C42,C,victoria,377,357
```

Se descargó el archivo mensual del jugador y se buscó la misma partida por su URL:

```bash
curl -sS -A "PlayerOne-UBB/1.0 (contacto: $CHESS_EMAIL)" \
  https://api.chess.com/pub/player/alvaropuchi/games/2026/11 > /tmp/ap.json

jq -c --arg u "https://www.chess.com/game/live/187728523870" '.games[] | select(.url == $u)
  | {fecha: (.end_time | strftime("%Y-%m-%d %H:%M:%S")), time_class, rated,
     blanco: .white.username, negro: .black.username, result_negras: .black.result,
     rating_negras: .black.rating, rating_blancas: .white.rating,
     eco: (.pgn | capture("ECO \"(?<e>[A-E][0-9]{2})").e)}' /tmp/ap.json
```

```json
{"fecha":"2026-11-21 23:06:11","time_class":"rapid","rated":true,"blanco":"Davidzurita23","negro":"AlvaroPuchi","result_negras":"win","rating_negras":385,"rating_blancas":357,"eco":"C42"}
```

`rating_previo` es el rating del jugador en su partida anterior de la misma modalidad, así que también se buscó con `jq`:

```bash
jq -c --arg u "https://www.chess.com/game/live/187728523870" '[.games[] | select(.time_class == "rapid" and .rules == "chess")]
  | sort_by(.end_time) | (map(.url) | index($u)) as $i | .[$i-1]
  | {url, fecha: (.end_time | strftime("%Y-%m-%d %H:%M:%S")),
     rating_propio: (if (.white.username | ascii_downcase) == "alvaropuchi" then .white.rating else .black.rating end)}' /tmp/ap.json
```

```json
{"url":"https://www.chess.com/game/live/187728383426","fecha":"2026-11-21 22:56:07","rating_propio":377}
```

| Columna | `partidas_limpias.csv` | API (`curl` + `jq`) | Coincide |
|---|---|---|---|
| `fecha_fin` | 2026-11-21 23:06:11 | 2026-11-21 23:06:11 | Sí |
| `rival` | davidzurita23 | Davidzurita23 (en minúsculas) | Sí |
| `color` | negras | `black` = AlvaroPuchi | Sí |
| `modalidad` | rapid | rapid | Sí |
| `eco` / `familia_eco` | C42 / C | C42 | Sí |
| `resultado` | victoria | `win` | Sí |
| `rating_previo` | 377 | 377 (partida anterior en rapid) | Sí |
| `rating_rival` | 357 | 357 | Sí |

La fila limpia coincide con la API en todas sus columnas. La consulta también muestra la fuga descrita en `informe/hallazgos_exploratorios.md`: tras ganar, el jugador pasó de 377 a 385 puntos; el 357 del rival ya incluye la pérdida de esta partida.
