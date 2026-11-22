---
title: "Player One: scouting de ajedrez en Chess.com con Nushell"
subtitle: "Trabajo Grupal"
author:
  - Juan Pablo Vargas
  - Trinidad Saez
date: "26 de noviembre de 2026"
lang: es
documentclass: article
fontsize: 11pt
geometry: margin=2.3cm
toc: true
toc-title: "Contenido"
colorlinks: true
linkcolor: black
---

# 1. Introducción

Player One es una consola escrita en Nushell que consulta la API pública de Chess.com (PubAPI) y ejecuta un pipeline reproducible de ciencia de datos: obtiene una muestra de jugadores, depura sus partidas, las explora y ajusta un modelo logístico para estimar la probabilidad de victoria.

Repositorio: <https://github.com/trini-tini/proyecto-player-one-chess> 

| Ruta | Contenido |
|---|---|
| `ch.nu` | Todos los comandos (un único archivo) |
| `jq/partidas.jq` | Filtro `jq` que convierte cada JSON de partidas en filas CSV |
| `motor/comandos_vw.txt` | Comandos y versión del motor externo (`vw`) |
| `data/partidas_limpias.csv` | Tabla depurada de partidas |
| `data/resumen_limpieza.json` | Filas perdidas en cada paso de la depuración |
| `data/exploracion/` | Tablas de `ch explore` |
| `data/modelo/` | Coeficientes y métricas de `ch model` |
| `informe/` | Este informe (fuente `informe.md` y `informe.pdf`) |

Herramientas: Nushell 0.114.1 con el plugin `polars` 0.114.1, `curl`, `jq` 1.7, GNU Parallel, Vowpal Wabbit 8.6.1 y Git.

# 2. Reglas generales y helper HTTP

Todas las consultas pasan por el helper `api-get` de `ch.nu`, que concentra las reglas de la PubAPI:

- **User-Agent:** `PlayerOne-UBB/1.0 (contacto: <correo>)`, donde el correo se lee de la variable de entorno `CHESS_EMAIL`. Si falta, el comando se detiene con un mensaje que explica cómo definirla.
- **Consultas seriales:** las llamadas se hacen una a una (`each`, `for`), nunca con `par-each` ni con GNU Parallel.
- **Caché de 12 horas:** cada respuesta se guarda en `cache/` con un nombre derivado de la URL (las `/` pasan a `__`). Si el archivo tiene menos de 12 horas (fecha de modificación de `ls`), se usa sin consultar la API.
- **Códigos de estado:** con `http get -e -f` se obtiene el código sin que Nushell lance un error.
    - 200: se guarda en caché y se devuelve el cuerpo.
    - 429: se espera 5, 10 y 15 segundos y se reintenta hasta 3 veces.
    - 404: se muestra un aviso claro y se devuelve `null`, para que cada comando decida qué hacer.
    - 410: la URL se anota en `cache/eliminadas_410.txt` y no se vuelve a solicitar.
- **Tipos:** las fechas Unix se convierten a `datetime` (UTC) con `into datetime`, y los ratings y conteos se mantienen como enteros.

 `api-get <url>` devuelve el JSON ya convertido en datos de Nushell, o `null` si el dato no está disponible.

# 3. Comandos sobre la PubAPI

## 3.1 `ch perfil <usuario>`

**API:** `GET /pub/player/{usuario}`. Devuelve un objeto con `username`, `name`, `title`, `status`, `country` (como URL), `followers`, `joined` y `last_online` (segundos Unix).

**Procesamiento:** el usuario se pasa a minúsculas, `country` se reduce a su código (`.../country/US` pasa a  `US`), y `joined` y `last_online` se convierten a fechas UTC. Se agregan `cuenta_cerrada` (si `status` empieza con `closed`, con un aviso) y `dias_desde_acceso`.

```text
> ch perfil hikaru   (salida resumida, 22-nov-2026)
usuario: hikaru, nombre: Hikaru Nakamura, titulo: GM, estado: premium,
cuenta_cerrada: false, pais: US, seguidores: 1438452,
registro: 2014-01-06 21:20:58 UTC, ultimo_acceso: 2026-11-22 12:59:20 UTC
```

## 3.2 `ch stats <usuario> [--modo]`

**API:** `GET /pub/player/{usuario}/stats`. Devuelve una clave por modalidad (`chess_rapid`, `chess_blitz`, `chess_bullet`, `chess_daily`, `chess960_daily`), cada una con `last.rating`, `best.rating` y `record` (`win`, `loss`, `draw`). También trae claves que no son modalidades de partidas: `tactics`, `lessons`, `puzzle_rush` y `fide` que se excluyen.

**Procesamiento:** una fila por modalidad con `rating_actual`, `mejor_rating` (vacío si la API no trae `best`), ganadas, perdidas, empatadas y `pct_victorias` = ganadas / total × 100. `--modo` acepta `blitz` o `chess_blitz` y avisa si el jugador no tiene esa modalidad.

**`pct_timeout`:** sí se encontró, pero solo dentro de `record` de las modalidades por correspondencia (`chess_daily` y `chess960_daily`), junto a `time_per_move`. Según la documentación de la PubAPI, `timeout_percent` corresponde al porcentaje de partidas perdidas por tiempo en los últimos 90 días. En rapid, blitz y bullet la API no lo entrega, por lo que la columna queda vacía. En la muestra del pipeline, 6 de los 10 jugadores tienen `chess_daily`, y uno de ellos (`anpeter-godchess`) tiene `timeout_percent` = 100.

| modalidad | rating_actual | mejor_rating | ganadas | perdidas | empatadas | pct_victorias | pct_timeout |
|---|---:|---:|---:|---:|---:|---:|---:|
| chess_daily | 2239 | 2464 | 73 | 11 | 4 | 83.0 | 0 |
| chess960_daily | 1231 | 1489 | 1 | 2 | 0 | 33.3 | 0 |
| chess_rapid | 2838 | 2927 | 205 | 69 | 220 | 41.5 | |
| chess_bullet | 3394 | 3570 | 17389 | 2576 | 1202 | 82.2 | |
| chess_blitz | 3449 | 3503 | 36268 | 5575 | 4398 | 78.4 | |

: `ch stats hikaru` (22-nov-2026)

## 3.3 `ch partidas <usuario> <año> <mes> [-m] [-c] [-r]`

**API:** primero `GET /pub/player/{usuario}/games/archives`, que lista las URL de los meses con partidas; luego `GET /pub/player/{usuario}/games/{AAAA}/{MM}`, que devuelve `games`, una lista de partidas con `url`, `end_time`, `time_class`, `rules`, `rated`, `pgn` y los objetos `white` y `black` (cada uno con `username`, `rating` y `result`).

**Procesamiento:**

- Si el mes no está en la lista de archivos, o no tiene partidas, se avisa y no se consulta.
- El color del jugador se identifica comparando su nombre (en minúsculas) con `white.username`. Luego, se arman `rival`, `color`, `rating_propio`, `rating_rival` y `resultado`.
- `fecha_fin` es `end_time` convertido a fecha UTC.
- `eco` se extrae del PGN con la expresión `\[ECO "([A-E]\d{2})"\]`; queda vacío si no existe.
- Los filtros `--modo`, `--color` y `--resultado` se validan y se aplican al final.

**Traducción de `result`.** Según la sección *Game results codes* de la documentación:

| Resultado | Códigos |
|---|---|
| victoria | `win` |
| derrota | `checkmated`, `resigned`, `timeout`, `abandoned`, `lose`, `kingofthehill`, `threecheck`, `bughousepartnerlose` |
| empate | `agreed`, `repetition`, `stalemate`, `insufficient`, `50move`, `timevsinsufficient` |

Casos ambiguos y cómo se resolvieron:

- `timevsinsufficient`: al jugador se le acabó el tiempo, pero el rival no tenía material para dar mate. Por reglamento es tablas, así que cuenta como empate aunque haya un `timeout`.
- `abandoned`: el jugador abandonó la partida (se desconectó y no volvió). Es una derrota, igual que rendirse.
- `kingofthehill`, `threecheck` y `bughousepartnerlose`: son derrotas propias de variantes (el rival llevó el rey al centro, dio tres jaques, o perdió en bughouse). Se traducen como derrota para no dejar códigos sin traducción; en el pipeline no aparecen, porque solo se conserva `rules = chess`.
- Un código desconocido se traduce como vacío (`null`).

**Comparación con el PGN.** Cada partida se contrasta con la etiqueta `Result` del PGN (`1-0`, `0-1`, `1/2-1/2`) vista desde el color del jugador. El comando informa cuántas partidas tienen `*` y cuántas discrepan. En `ch partidas hikaru 2026 10` hubo 583 partidas, 0 discrepancias y 0 con `*`.

## 3.4 `ch top <modalidad> [--n]`

**API:** `GET /pub/leaderboards`. Devuelve una clave por ranking (`daily`, `daily960`, `live_rapid`, `live_blitz`, `live_bullet`, `live_bughouse`, `live_blitz960`, `live_threecheck`, `tactics`, `rush`, `battle`), cada una con una lista de jugadores con `rank`, `username`, `score`, `country`, `title`, `win_count`, `loss_count` y `draw_count`.

**Procesamiento:** la modalidad se valida contra las claves que entrega la propia API (si no existe, el error muestra las disponibles), `--n` se limita a 1–50 y `country` se reduce a su código.

| posicion | usuario | puntaje | pais | titulo | ganadas | perdidas | empatadas |
|---:|---|---:|---|---|---:|---:|---:|
| 1 | Hikaru | 3449 | US | GM | 37853 | 5692 | 4450 |
| 2 | MagnusCarlsen | 3397 | NO | GM | 5228 | 1149 | 860 |
| 3 | Firouzja2003 | 3391 | FR | GM | 8441 | 4761 | 1887 |
| 4 | DenLaz | 3370 | BY | GM | 3755 | 1335 | 980 |
| 5 | nihalsarin | 3333 | CL | GM | 17752 | 9392 | 3239 |

: `ch top live_blitz --n 5` (22-nov-2026)

## 3.5 `ch club <id-club>`

**API:** `GET /pub/club/{id}` (perfil: `name`, `members_count`, `created`, `last_activity`) y `GET /pub/club/{id}/members`, que separa a los miembros en tres grupos según su actividad: `weekly`, `monthly` y `all_time`, cada uno con `username` y `joined`.

**Procesamiento:** se muestran el nombre, la cantidad de miembros y las fechas de creación y de última actividad (convertidas a fecha). Luego, para cada grupo, su tamaño y sus miembros con la fecha de ingreso. Un grupo vacío muestra "Este grupo no tiene miembros"; si la lista de miembros responde 404, se muestra un aviso en lugar de fallar; si el club no existe, también se avisa.

Con `ch club chesscom` se obtiene el club `@chess.com`, con 7 miembros, 0 en `weekly`, 0 en `monthly` y 7 en `all_time`.

## 3.6 `ch pais <ISO> [--n]`

**API:** `GET /pub/country/{ISO}/players`. Devuelve `players`, una lista de nombres de usuario, y `comment`.

**Procesamiento:** se valida que el código tenga dos letras, se informa la cantidad de nombres de la lista y se muestran los primeros `n` (10 por omisión). Para Chile la lista tiene 10.000 nombres, porque la API la recorta: el campo `comment` dice *"Results are temporarily reduced to the first 10000 players for performance reasons"*. Los primeros son `-kvn-`, `0-mingus-0` y `0003onane`.

## 3.7 `ch puzzle [--random]`

**API:** `GET /pub/puzzle` (puzzle diario) o `GET /pub/puzzle/random`. Ambos devuelven `title`, `url`, `publish_time`, `fen`, `pgn` e `image`.

**Procesamiento:** se muestran `titulo`, `fen` e `imagen`. La opción `--tablero` se describe en la sección 7.

# 4. Comparación con `curl` y `jq`

Para cada comando se hizo una consulta independiente con `curl` (con el mismo User-Agent) y `jq`, y se comparó con la salida del comando en Nushell. Sin User-Agent, Chess.com responde 403 (bloqueo de Cloudflare) con una página HTML.

```bash
UA="PlayerOne-UBB/1.0 (contacto: $CHESS_EMAIL)"
curl -sS -A "$UA" https://api.chess.com/pub/player/hikaru/stats \
  | jq -c 'to_entries | map(select(.value.record?) | {k: .key,
      last: .value.last.rating, best: .value.best.rating, rec: .value.record})'
curl -sS -A "$UA" https://api.chess.com/pub/player/hikaru/games/2026/10 \
  | jq '[.games[] | select(.time_class == "blitz")] | length'
curl -sS -A "$UA" https://api.chess.com/pub/leaderboards \
  | jq -c '.live_blitz[:5] | map({rank, username, score})'
curl -sS -A "$UA" https://api.chess.com/pub/country/CL/players \
  | jq -c '{total: (.players | length), primeros: .players[:3], comment}'
curl -sS -A "$UA" https://api.chess.com/pub/club/chesscom/members \
  | jq -c '{weekly: (.weekly | length), monthly: (.monthly | length),
      all_time: (.all_time | length)}'
curl -sS -A "$UA" https://api.chess.com/pub/puzzle | jq -r .fen
```

| Comando de Nushell | Consulta `curl` + `jq` | Resultado |
|---|---|---|
| `ch perfil hikaru` | `/player/hikaru`: `username`, `status`, `country`, `followers` | Coinciden (premium, US, 1.438.452 seguidores) |
| `ch stats hikaru` | `/player/hikaru/stats`: `last`, `best` y `record` | Coinciden las 5 modalidades; `timeout_percent` solo en las daily |
| `ch partidas hikaru 2026 10 -m blitz` | `/games/2026/10` con `time_class == "blitz"` | 240 partidas en ambos |
| `ch top live_blitz --n 5` | `/leaderboards`: `.live_blitz[:5]` | Mismos 5 jugadores, posiciones y puntajes |
| `ch pais CL --n 3` | `/country/CL/players` | 10.000 nombres; mismos 3 primeros |
| `ch club chesscom` | `/club/chesscom/members` | 0, 0 y 7 miembros |
| `ch puzzle --tablero` | `/puzzle`: `fen` | Mismo FEN (sección 7) |
| Fila de `partidas_limpias.csv` | `/games/2026/11` de `alvaropuchi` | Coinciden las 11 columnas (sección 5.2) |

: Comparaciones del 22-nov-2026

# 5. Pipeline 

El pipeline tiene un comando por etapa y `ch pipeline` las ejecuta en orden:

```text
ch scout --pais CL  ->  ch clean  ->  ch explore  ->  ch model
```

`ch pipeline --sin-descarga` reutiliza los archivos de `data/raw/` y vuelve a ejecutar la depuración, la exploración y la modelación. Se comprobó que así se obtienen exactamente los mismos archivos de salida (mismas sumas MD5).

## 5.1 Obtención: `ch scout`

Fuente elegida: país (Chile, `--pais CL`)

- **Tamaño:** La lista de Chile tiene 10.000 nombres, mientras que un club como `chesscom` tiene solo 7 miembros.
- **Reproducibilidad:** El orden de recorrido depende de una semilla, así que cualquiera puede repetir el orden de los candidatos.
- **Menos sesgo de afinidad:** Los miembros de un club comparten intereses o nivel, lo que haría la muestra más homogénea.

**Orden con semilla:** La lista del país viene en orden alfabético. Para cada nombre se calcula una clave a partir del nombre y de la semilla, y la lista se ordena por esa clave. Se parte de `(semilla mod 2147483647) + 1`, y cada carácter se mezcla con la fórmula de Park-Miller: `(acumulado + código + posición) × 48271 mod 2147483647`. Solo se usan `split chars`, `enumerate`, `reduce` y `str index-of`. La misma semilla da siempre el mismo orden

**Recorrido:** Se consulta el perfil de cada candidato en ese orden:

1. Las cuentas cerradas o inexistentes se omiten y se cuentan.
2. Un jugador es activo si su `last_online` está dentro de `--dias-activo` días.
3. De cada activo se descargan sus partidas del período. Se conservan como máximo las `--max-partidas` más recientes, y el jugador se conserva solo si tiene al menos `--min-partidas` partidas con `rules = chess`.
4. Se guardan las partidas en `data/raw/<usuario>_<AAAA>_<MM>.json` (con la misma estructura de la API, clave `games`) y las estadísticas en `data/raw/stats_<usuario>.json`.
5. El recorrido se detiene al reunir `--n` jugadores o al alcanzar `--max-consultas`.

`ch scout` también acepta la fuente club (`--club <id>` con `--actividad weekly`, `monthly` o `all_time`), que recorre los miembros de ese grupo. Exige exactamente una de las dos fuentes. Se probó con `ch scout --club chess-com --n 2 --actividad weekly`: el grupo tenía 1 miembro, así que el comando avisó que no completó N.

**Período:** `--meses 3` se interpreta como 3 bloques de 30 días hacia atrás desde la fecha de obtención, es decir, los mismos 90 días de `--dias-activo`. Se descargan los meses calendario que cubren ese período y se descartan las partidas anteriores a su inicio. Si `--meses × 30` es menor que `--dias-activo`, se muestra un aviso.

**Corrida oficial (22-nov-2026).** Se usaron todos los valores predeterminados.

| Concepto | Valor |
|---|---|
| Perfiles revisados | 19 |
| Jugadores activos (últimos 90 días) | 19 |
| Cuentas omitidas (cerradas o inexistentes) | 0 |
| Descartados por menos de 20 partidas `chess` | 9 |
| Jugadores conservados | 10 |
| Partidas descargadas | 1.429 |
| Período | desde el 24-ago-2026 (agosto a noviembre) |

Los 9 descartados tenían entre 0 y 13 partidas estándar en el período. Los conservados tienen entre 42 y 200 partidas; cuatro (`alvaropuchi`, `3squin4`, `apr2025` y `alex_geell`) alcanzaron el tope de 200.

**Flags:** No se ajustó ninguna:

- `--n 10` se completó con 19 de las 250 consultas permitidas.
- `--meses 3` cubre el período de `--dias-activo 90`.
- `--min-partidas 20` descartó a casi la mitad de los activos, que juegan muy poco. Bajarlo habría sumado jugadores con 1 a 13 partidas, que aportan poca información sobre sí mismos.

**Sesgo de la lista:** La API recorta la lista a 10.000 nombres, y la documentación no garantiza su orden. En nuestra consulta (22-nov-2026), los 10.000 nombres iban en orden alfabético de `-kvn-` a `chacal_patriota`: 864 empiezan con dígitos o `-`, 4.856 con `a`, 2.807 con `b` y 1.473 con `c`. La muestra solo puede contener jugadores cuyo nombre empieza así. La semilla mezcla el orden dentro de la lista, pero no corrige el corte. No hay una razón evidente para que la inicial del nombre se relacione con el nivel de juego, pero la muestra no es aleatoria respecto de todos los jugadores chilenos.

## 5.2 Depuración: `ch clean`

**Conversión a CSV:** Los JSON de `data/raw/` se procesan con GNU Parallel y `jq`, en archivos locales:

```nu
^parallel --keep-order 'jq -r --arg archivo {/} -f jq/partidas.jq {}' ::: ...$archivos
```

El filtro `jq/partidas.jq` toma el nombre del jugador analizado desde el nombre del archivo y emite una fila por partida, vista desde ese jugador: `url`, `end_time`, `jugador`, `rival`, `color`, `time_class`, `rules`, `rated`, `result` propio, rating propio, rating del rival, la etiqueta `Result` del PGN y el ECO. `--keep-order` mantiene el orden de los archivos para que la salida sea reproducible. El resultado se guarda en `data/partidas_crudas.csv` (intermedio, no versionado).

**Pasos y filas perdidas** (`data/resumen_limpieza.json`):

| Paso | Decisión | Filas |
|---|---|---:|
| Filas originales | Una por partida y jugador analizado | 1.429 |
| 1. `rules = chess` | Se descartan las variantes (por ejemplo, chess960) | −1 |
| 2. Clasificatorias | Se descartan las partidas con `rated = false` | −7 |
| 3. Datos faltantes | Se descartan filas sin URL, fecha, rival, ratings o resultado traducido | 0 |
| 4. Resultado vs PGN | Se cuentan discrepancias y `*`; se conserva el de la API | 0 y 0 |
| 5. Duplicados | Si dos jugadores de la muestra se enfrentan, queda la fila del de menor nombre | 0 |
| 6. Sin `rating_previo` | Se descarta la primera partida de cada jugador y modalidad | −22 |
| Filas finales | `data/partidas_limpias.csv` | 1.399 |

Justificación de cada decisión:

- **Partidas no clasificatorias:** En una partida amistosa (`rated = false`) el rating no cambia y Chess.com no empareja por nivel. En una corrida de prueba, las 33 partidas no clasificatorias tenían una diferencia de rating media de 822 puntos (contra 25 en las clasificatorias) y distorsionaban el ajuste. Por eso se excluyen.
- **ECO:** Ninguna fila quedó sin ECO. Si faltara, la fila se conserva con `eco` y `familia_eco` vacíos, porque el ECO no es un predictor del modelo.
- **Resultado:** Se traduce `result` con la misma tabla de la sección 3.3 y se contrasta con la etiqueta `Result` del PGN. No hubo discrepancias ni partidas con `*`.
- **`rating_previo`:** Es el rating del jugador en su partida anterior de la misma modalidad, ordenando por fecha de término. Se calcula antes de quitar duplicados, para usar el historial completo de cada jugador. La primera partida de cada jugador y modalidad no tiene partida anterior dentro del período, así que se descarta.
- **Fechas:** `end_time` se convierte a `fecha_fin` en UTC y se guarda en el CSV con formato `AAAA-MM-DD HH:MM:SS`. Como un CSV solo guarda texto, `ch explore` y `ch model` la vuelven a convertir a fecha (`datetime` en UTC) al leerla, y trabajan con ese tipo.
- **Familia ECO:** Es la letra inicial del código (A a E).

La tabla final tiene las columnas `url`, `fecha_fin`, `jugador`, `rival`, `color`, `modalidad`, `eco`, `familia_eco`, `resultado`, `rating_previo` y `rating_rival`. Tiene 660 victorias, 657 derrotas y 82 empates.

Validación con `curl` y `jq`: Se tomó la última partida de `alvaropuchi` en la tabla limpia y se buscó en la API por su URL:

```bash
jq -c --arg u "https://www.chess.com/game/live/187728523870" \
  '.games[] | select(.url == $u) | {fecha: (.end_time | strftime("%Y-%m-%d %H:%M:%S")),
   time_class, rated, blanco: .white.username, negro: .black.username,
   result_negras: .black.result, rating_negras: .black.rating,
   rating_blancas: .white.rating, eco: (.pgn | capture("ECO \"(?<e>[A-E][0-9]{2})").e)}' ap.json
```

| Columna | `partidas_limpias.csv` | API (`curl` + `jq`) |
|---|---|---|
| `fecha_fin` | 2026-11-21 23:06:11 | 2026-11-21 23:06:11 |
| `rival` / `color` | davidzurita23 / negras | Davidzurita23 con blancas |
| `modalidad` / `eco` | rapid / C42 | rapid / C42 |
| `resultado` | victoria | `win` |
| `rating_previo` | 377 | 377 (partida anterior en rapid) |
| `rating_rival` | 357 | 357 |

Las 11 columnas coinciden. La consulta también muestra el problema de `rating_rival` que se analiza en la sección 5.4: tras ganar, el jugador pasó de 377 a 385 puntos, y el 357 del rival ya incluye la pérdida de esta partida.

## 5.3 Exploración: `ch explore`

`ch explore` lee `data/partidas_limpias.csv`, lo convierte en un DataFrame con el plugin `polars` de Nushell (`polars into-df`) y calcula las tablas con `polars group-by`, `polars agg`, `polars with-column`, `polars when`/`polars otherwise` y `polars sort-by`. Cada tabla se guarda en `data/exploracion/`.

| Modalidad | Partidas | % victorias |
|---|---:|---:|
| blitz | 560 | 42,14 |
| bullet | 295 | 53,22 |
| daily | 3 | 66,67 |
| rapid | 541 | 48,98 |

: Victorias por modalidad

| Color | Modalidad | Partidas | % victorias |
|---|---|---:|---:|
| blancas | blitz | 278 | 41,37 |
| blancas | bullet | 149 | 51,68 |
| blancas | rapid | 273 | 51,65 |
| negras | blitz | 282 | 42,91 |
| negras | bullet | 146 | 54,79 |
| negras | rapid | 268 | 46,27 |

: Victorias por color y modalidad (sin daily, con 3 partidas)

| ECO | Partidas | | Familia | Partidas | % victorias |
|---|---:|---|---|---:|---:|
| B01 | 122 | | A | 355 | 47,89 |
| A00 | 105 | | B | 422 | 50,24 |
| D02 | 84 | | C | 391 | 46,29 |
| D00 | 79 | | D | 229 | 41,92 |
| A40 | 69 | | E | 2 | 50,00 |
| B00 | 69 | | | | |
| C20 | 54 | | | | |
| C00 | 44 | | | | |
| C45 | 37 | | | | |
| B30 | 35 | | | | |

: Top 10 de códigos ECO y victorias por familia de apertura

Las tablas de victorias por tramo de `d`, partidas por mes y partidas por jugador se presentan junto a los hallazgos.

### Hallazgo 1: la diferencia de rating parece decidir el resultado, pero es un efecto de la fuga en `rating_rival`

| Tramo de `d` | Partidas | % victorias |
|---|---:|---:|
| ≤ −51 | 32 | 12,50 |
| −50 a −26 | 119 | 2,52 |
| −25 a −1 | 552 | 32,43 |
| 0 | 34 | 61,76 |
| 1 a 25 | 491 | 60,49 |
| 26 a 50 | 123 | 91,87 |
| ≥ 51 | 48 | 89,58 |

: Victorias por tramo de `d = rating_previo − rating_rival` (tramos de 25 puntos, porque el promedio de |d| es 22)

Según Elo, una diferencia de 25 a 50 puntos debería dar entre un 54 % y un 57 % de victorias, no un 92 %. El salto se explica porque la API entrega el rating del rival después de la partida, es decir, si el jugador gana, el rival pierde puntos y `d` sube; si pierde, `d` baja. Para comprobarlo, se estimó el rating del rival antes de la partida sumándole el cambio de rating del propio jugador (los cambios de ambos son aproximadamente simétricos). Con esa diferencia aproximada, el porcentaje de victorias queda casi plano: 46,2 % (≤ −26), 42,6 % (−25 a −1), 53,5 % (0), 49,5 % (1 a 25) y 58,7 % (≥ 26).

### Hallazgo 2: no hay una ventaja medible por jugar con blancas

Las blancas ganan el 47,72 % de 702 partidas (± 3,69 con 95 % de confianza) y las negras el 46,63 % de 697 (± 3,70). La diferencia (1,1 puntos) es mucho menor que el margen, y por modalidad no tiene un signo constante: en rapid ganan más las blancas, en blitz y bullet las negras. En este nivel de juego, la ventaja teórica de las blancas no se distingue del ruido.

### Hallazgo 3: la muestra se concentra en pocos jugadores y en las semanas más recientes

| Jugador | Filas | % de la muestra | Rating previo medio | % victorias |
|---|---:|---:|---:|---:|
| alex_geell | 199 | 14,22 | 663 | 51,26 |
| apr2025 | 199 | 14,22 | 1.429 | 44,72 |
| alvaropuchi | 198 | 14,15 | 357 | 48,48 |
| 3squin4 | 191 | 13,65 | 707 | 47,64 |
| benjamola122 | 159 | 11,37 | 802 | 54,09 |
| alitro23 | 125 | 8,93 | 363 | 46,40 |
| afantasmado | 112 | 8,01 | 498 | 31,25 |
| anderxdani | 91 | 6,50 | 359 | 60,44 |
| anpeter-godchess | 87 | 6,22 | 139 | 32,18 |
| asdsdadasx | 38 | 2,72 | 536 | 52,63 |

: Partidas por jugador

| Mes | Agosto (desde el 24) | Septiembre | Octubre | Noviembre (hasta el 22) |
|---|---:|---:|---:|---:|
| Partidas | 5 | 91 | 396 | 907 |

: Evolución mensual de partidas

Los cuatro jugadores que alcanzaron el tope de 200 partidas suman el 56 % de las filas. Como el tope conserva las partidas más recientes, noviembre concentra el 65 % de la muestra. Esta distribución viene del diseño de la obtención (ventana de 90 días y tope por jugador), no de un cambio en la actividad de los jugadores.

## 5.4 Modelación: `ch model`

**Variables:** El objetivo es `y = 1` si el jugador analizado ganó (empate y derrota valen 0). Los predictores son `d = rating_previo − rating_rival` (dividida por 100 para que el coeficiente se interprete  "por cada 100 puntos"), `blancas` (1 si jugó con blancas) y la modalidad en variables indicadoras, con rapid como base.

**Partición cronológica:** Las filas se ordenan por `fecha_fin`; el 70 % más antiguo (979 filas, hasta el 13-nov-2026) se usa para entrenar y el 30 % más reciente (420 filas, del 13 al 22-nov) para evaluar. No se usa una partición aleatoria por tres razones:

- El objetivo es anticipar partidas futuras, y una partición aleatoria permitiría entrenar con partidas posteriores a las que se evalúan.
- Las partidas de un mismo jugador en una misma sesión están muy relacionadas. `rating_previo` de una partida es el rating de salida de la anterior, así que una partición aleatoria dejaría partidas casi idénticas a ambos lados.
- Los ratings cambian con el tiempo, y la partición cronológica mide si el modelo sigue sirviendo cuando eso ocurre.

**Motor externo: Vowpal Wabbit 8.6.1:** Se eligió `vw` por cuatro razones:

- Es un programa de línea de comandos con la pérdida logística incorporada (`--loss_function logistic`). Se llama desde Nushell como cualquier comando externo, sin escribir un script en otro lenguaje, como exigirían R o Python.
- Su entrada es un formato de texto simple (`etiqueta |espacio rasgos`) que Nushell genera directamente. Así toda la preparación de los datos queda en Nushell.
- Entrega por separado los puntajes crudos (`-p`) y los coeficientes con sus nombres (`--invert_hash`), de modo que la conversión a probabilidades y las métricas se calculan en Nushell.
- Con una semilla fija (`--random_seed`), el ajuste es reproducible. Nushell prepara todo: lee y transforma los datos, construye las variables, hace la partición, escribe los archivos de entrada (`1 |p d:0.25 blancas blitz`), convierte la salida a probabilidades y calcula las métricas. `vw` solo ajusta el modelo y entrega los puntajes. Los comandos quedan en `motor/comandos_vw.txt`:

```text
vw -d data/modelo/entrenamiento.vw -f data/modelo/modelo.vw --loss_function logistic
   --passes 500 -c -k --holdout_off --random_seed 42 --quiet
vw -t -d data/modelo/entrenamiento.vw -i data/modelo/modelo.vw --invert_hash data/modelo/pesos.txt --quiet
vw -t -d data/modelo/prueba.vw -i data/modelo/modelo.vw -p data/modelo/puntajes_prueba.txt --quiet
```

- `--loss_function logistic` ajusta una regresión logística.
- `--passes 500` hace 500 pasadas por los datos (`-c` crea la caché necesaria y `-k` la reemplaza). Con 10 pasadas los coeficientes aún no se estabilizaban (el de `d` pasaba de 5,40 a 6,76 en una corrida de prueba).
- `--holdout_off` usa todo el entrenamiento (sin `--holdout_off`, `vw` reserva un 10 % en las pasadas múltiples).
- `--random_seed 42` fija la semilla.
- `--invert_hash` entrega los coeficientes con su nombre, y `-p` los puntajes crudos de la prueba.

Nushell aplica la sigmoide `p = 1 / (1 + e^(−z))` a esos puntajes.

**Comparación en el conjunto de prueba:** Las probabilidades se acotan a $[10^{-15}, 1 - 10^{-15}]$ para la pérdida logarítmica, y la exactitud usa el umbral 0,5.

| Alternativa | Probabilidad | Exactitud | Pérdida logarítmica |
|---|---|---:|---:|
| (a) Constante | proporción de victorias del entrenamiento (0,458) | 0,495 | 0,698 |
| (b) Elo | $E = 1/(1 + 10^{-d/400})$ | 0,710 | 0,656 |
| (c) Logística (`vw`) | sigmoide del puntaje de `vw` | 0,707 | 0,544 |

La constante predice siempre "no gana", así que su exactitud es la proporción de no victorias en la prueba. Elo y la logística aciertan alrededor del 71 %. La logística tiene una pérdida logarítmica bastante menor, porque asigna probabilidades más extremas cuando `d` es grande.

**Coeficientes** (`data/modelo/coeficientes.json`, escala logit):

| Término | Coeficiente | Lectura |
|---|---:|---|
| Constante | −0,098 | rapid, negras, `d = 0`: probabilidad 0,476 |
| `d` (por 100 puntos) | 5,532 | +25 puntos de `d` suben el logit en 1,38 |
| `blancas` | 0,208 | con `d = 0` en rapid: 0,527 con blancas contra 0,476 con negras |
| `blitz` | −0,357 | menor probabilidad que en rapid con igual `d` |
| `bullet` | −0,358 | menor probabilidad que en rapid con igual `d` |
| `daily` | 0,938 | no es interpretable (ver nota) |

La pendiente de Elo en escala logit es $\ln(10)/400 \times 100 = 0{,}576$ por cada 100 puntos. El coeficiente de `d` del modelo es 9,6 veces mayor.

Nota sobre `daily`: el entrenamiento tiene solo 2 partidas daily, de un mismo jugador, y ambas son victorias. Cuando una categoría gana siempre, el coeficiente de máxima verosimilitud crece sin límite, así que el 0,938 es solo el valor en que se detuvo `vw`. Por lo mismo, `ch duelo -m daily` no es confiable.

**Verificación del ajuste:** los coeficientes se compararon con una regresión logística por máxima verosimilitud (método de Newton) ajustada aparte con los mismos datos de entrenamiento, sin las 2 partidas daily: constante −0,098 contra −0,098, `d` 5,53 contra 5,79, `blancas` 0,21 contra 0,21, `blitz` −0,36 contra −0,37 y `bullet` −0,36 contra −0,38. `vw` llega prácticamente a la misma solución.

**Sesgo de `rating_rival`:** Es posterior a la partida y para estimar el orden de magnitud del sesgo se calculó el promedio de |rating posterior − `rating_previo`| de los jugadores analizados: 10,6 puntos. El promedio de |d| es 22,1, así que el cambio de una sola partida equivale a la mitad de una diferencia. Como ese cambio tiene el signo del resultado (+ al ganar, − al perder), `d` contiene parte del resultado que se quiere predecir.

Esto explica 3 cosas:

1. el coeficiente de `d` es casi 10 veces el de Elo;
2. la logística supera a Elo en pérdida logarítmica, porque aprendió a confiar en una señal que ya incluye el resultado;
3. incluso la exactitud de Elo (0,71) está inflada. Con la diferencia estimada antes de la partida (Hallazgo 1), el porcentaje de victorias apenas varía con `d`.

En resumen, el modelo no sirve para anticipar partidas futuras con la precisión que aparenta. Para eso habría que usar el rating del rival antes de la partida, que la API no entrega directamente.

**Composición de la muestra y generalización**

- **Fuente:** 10 jugadores de Chile cuyo nombre empieza con dígito, `-`, `a`, `b` o `c` (sesgo de la lista de la API, sección 5.1).
- **Ratings:** `rating_previo` va de 100 a 1.480 (mediana 626); el promedio por jugador, de 139 a 1.429. Son jugadores aficionados, de nivel bajo a intermedio. La mediana es 388 en rapid, 709 en blitz y 617 en bullet.
- **Concentración:** 4 jugadores suman el 56 % de las filas, y la composición cambia entre entrenamiento y prueba. Por ejemplo, `anderxdani` tiene 16 filas en entrenamiento y 75 en prueba, y `benjamola122` 149 y 10. El modelo aprende sobre todo de los jugadores más activos y se evalúa con una mezcla distinta.
- **Generalización:** Los resultados no se pueden extender a todos los jugadores de Chile ni a jugadores de nivel alto. Los efectos de modalidad pueden reflejar quién juega cada modalidad, más que la modalidad misma.

El color no muestra una ventaja medible, descriptivamente, la diferencia entre blancas y negras (47,72 % y 46,63 %) es mucho menor que el margen de ± 3,7 puntos. En el modelo, el coeficiente de `blancas` (0,21) es positivo, pero se estima junto a una `d` con fuga y su signo cambia según la modalidad en los datos (sección 5.3). No hay evidencia suficiente para afirmar una ventaja.

# 6. `ch duelo <usuario1> <usuario2> [--modo]`

**Funcionamiento:** Obtiene el rating actual de cada jugador en la modalidad con `ch stats` (que usa `last.rating` de la API) y calcula `d = rating1 − rating2`. Con esa `d` estima:

- **Elo:** $1/(1 + 10^{-d/400})$.
- **Modelo:** la sigmoide de constante + coeficiente de `d` × d/100 + coeficiente de la modalidad, con los coeficientes de `data/modelo/coeficientes.json`. Como antes de la partida no se sabe quién juega con blancas, se promedian las probabilidades con blancas y con negras.

Si la modalidad no está en el modelo, se avisa y se usa la base (rapid). Si un jugador no tiene rating en la modalidad, el comando lo informa. Por ejemplo, `ch duelo alvaropuchi anderxdani -m blitz` falla porque `alvaropuchi` no tiene blitz.

```text
> ch duelo apr2025 3squin4 -m rapid
Modalidad: rapid; d = 446
| usuario | rating | prob_elo | prob_modelo |
| apr2025 |   1219 |     0.93 |        1.00 |
| 3squin4 |    773 |     0.07 |        0.00 |
```

| `d` | −200 | −100 | −50 | −25 | 0 | 25 | 50 | 100 | 200 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Elo | 0,24 | 0,36 | 0,43 | 0,46 | 0,50 | 0,54 | 0,57 | 0,64 | 0,76 |
| Modelo | 0,00 | 0,00 | 0,06 | 0,20 | 0,50 | 0,80 | 0,94 | 1,00 | 1,00 |

: Probabilidad de victoria del jugador 1 en rapid según `d`

**En qué casos difieren:** Coinciden solo cuando los ratings son iguales. Con 25 puntos de diferencia, Elo da 54 % y el modelo 80 %; desde unos 100 puntos, el modelo da prácticamente certeza, mientras Elo aún deja un 24–36 % al más débil. La mayor diferencia está entre 50 y 100 puntos (0,36–0,37). El modelo es tan extremo porque su coeficiente de `d` se aprendió con el rating del rival posterior a la partida (sección 5.4). En `ch duelo`, en cambio, ambos ratings son actuales, es decir, anteriores a cualquier partida futura, así que esa fuga ya no está. Para un duelo real, la estimación de Elo es más confiable. El modelo solo agrega el ajuste por modalidad.

# 7. `ch puzzle --tablero`

Construye la posición del FEN como un tablero de texto de 8 × 8, usando solo comandos de strings y listas de Nushell:

1. Se toma el primer campo del FEN (`split row " " | first`), que describe la posición.
2. Se separa en las 8 filas, de la 8 a la 1 (`split row "/"`).
3. Cada fila se separa en caracteres (`split chars`). Un dígito $n$ se reemplaza por $n$ casillas vacías (`·`) y una letra por su pieza con un registro: mayúsculas para las blancas (♔♕♖♗♘♙) y minúsculas para las negras (♚♛♜♝♞♟).
4. Se une con espacios, se antepone el número de fila y al final se agregan las columnas `a` a `h`.

```text
> ch puzzle --tablero
8 · ♖ · · · · · ·
7 · · · · ♜ · ♟ ♚
6 · · ♟ · · · ♖ ♟
5 · ♝ · ♟ · · · ♙
4 · · · ♗ ♙ · · ·
3 ♜ · · · · ♙ ♙ ·
2 ♟ · ♙ · · · · ♔
1 · · · · · · · ·
  a b c d e f g h
```

El tablero corresponde al FEN `1R6/4r1pk/2p3Rp/1b1p3P/3BP3/r4PP1/p1P4K/8 w - - 0 1` del puzzle diario. Por ejemplo, la fila 8 (`1R6`) es una casilla vacía, una torre blanca en b8 y seis casillas vacías. El mismo FEN se obtuvo con `curl` + `jq`.

# 8. Conclusiones

- Player One implementa en un único archivo de Nushell los comandos de consulta de la PubAPI y un pipeline reproducible. Las llamadas son seriales, con caché, User-Agent desde una variable de entorno y manejo de los códigos 429, 404 y 410. Todos los comandos se contrastaron con consultas independientes de `curl` y `jq`.
- La muestra (10 jugadores chilenos, 1.399 partidas) está limitada por el recorte alfabético de la lista del país y concentrada en los jugadores más activos. Sus resultados no se pueden generalizar.
- Con los datos de la API, la diferencia de rating parece casi determinar el resultado, y el modelo logístico mejora la pérdida logarítmica de Elo (0,544 contra 0,656). Sin embargo, la mayor parte de esa capacidad viene de que `rating_rival` es posterior a la partida. Con la diferencia estimada antes de jugar, el resultado casi no depende de `d`, coherente con que Chess.com empareja rivales de nivel muy similar.
- No hay evidencia de una ventaja por jugar con blancas en esta muestra.
- Como mejora, se podría reconstruir el rating del rival antes de la partida (descargando también el historial del rival, o restando su cambio estimado) y volver a ajustar el modelo sin la fuga.

# Anexo: reproducir los resultados

```nu
$env.CHESS_EMAIL = "su_correo@ejemplo.cl"
use ch.nu *
ch pipeline                 # descarga una muestra nueva (borra data/raw/)
ch pipeline --sin-descarga  # repite depuración, exploración y modelo con data/raw/
```

`data/raw/` no se versiona, porque contiene las respuestas de la API. Los resultados de este informe corresponden a la corrida del 22-nov-2026. Una corrida nueva descarga partidas más recientes, por lo que las cifras cambiarán.

El informe se compila desde `informe/` con:

```bash
pandoc informe.md -H preambulo.tex --pdf-engine=lualatex -o informe.pdf
```
