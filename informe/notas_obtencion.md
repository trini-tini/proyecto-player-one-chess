# Obtención de datos: `ch scout`

## 1. Fuente elegida

Se usó la fuente país, con Chile (`--pais CL`), en lugar de un club.

Razones:

- Tamaño: la lista de Chile entrega 10.000 nombres; un club como `chesscom` tiene solo 7 miembros en `all_time`, y la lista de miembros de otros clubes no siempre está disponible 
- Reproducibilidad: con país, el orden de recorrido depende de una semilla (`--semilla 42`), por lo que cualquiera puede repetir la misma muestra.
- Menos sesgo de afinidad: los miembros de un club comparten intereses o nivel (un club de principiantes, de un colegio, de un streamer), lo que haría la muestra más homogénea.

## 2. Orden con semilla

La lista del país viene en orden alfabético, por lo que recorrerla tal cual tomaría siempre a los mismos jugadores. Para cada nombre se calcula una clave numérica a partir del nombre y la semilla, y la lista se ordena por esa clave:

- se parte de `(semilla mod 2147483647) + 1`;
- cada carácter del nombre, según su posición, se mezcla con la fórmula de Park-Miller: `(acumulado + código + posición) × 48271 mod 2147483647`.

La misma semilla da siempre el mismo orden. Con `--semilla 7` la muestra cambia (por ejemplo, aparecen `bryanherrera25`, `anto-i-love-you` y `bnnjzz`).

## 3. Resultado de la corrida

La corrida oficial se hizo el 22-nov-2026  con `ch pipeline`, que ejecuta `ch scout --pais CL --semilla 42` con los demás valores predeterminados:

| Concepto | Valor |
|---|---|
| Perfiles revisados | 19 |
| Jugadores activos (últimos 90 días) | 19 |
| Cuentas omitidas (cerradas o inexistentes) | 0 |
| Descartados por tener menos de 20 partidas `chess` | 9 |
| Jugadores conservados | 10 |
| Partidas descargadas | 1.429 |
| Período | desde el 24-ago-2026 (meses descargados: agosto a noviembre de 2026) |

Descartados: `agu3214` y `alonso0702` con 0 partidas, `alfonsodevid`, `alexish1s` y `aldoibani` con 1, `actuallygus` con 4, `alanw_h` con 5, `aguspro1420` con 7 y `baltazarchess0433` con 13.

Partidas por jugador: `alvaropuchi`, `3squin4`, `apr2025` y `alex_geell` 200 cada uno, `benjamola122` 161, `alitro23` 126, `afantasmado` 114, `anderxdani` 94, `anpeter-godchess` 92 (91 `chess`) y `asdsdadasx` 42.

4 jugadores alcanzaron el tope de 200 partidas, por lo que de ellos se conservaron solo las más recientes.

El resumen queda guardado en `data/raw/resumen_scout.json`, con la fecha de obtención y el inicio del período. Los archivos de `data/raw/` no se suben al repositorio; después de esta corrida, el pipeline se vuelve a ejecutar con `ch pipeline --sin-descarga` para no cambiar la muestra.

## 4. Flags ajustadas

No se ajustó ninguna flag; se usaron los valores predeterminados:

- `--n 10` se completó con 19 de las 250 consultas permitidas (`--max-consultas`), así que no fue necesario ampliar el máximo de consultas.
- `--meses 3` se interpreta como tres bloques de 30 días hacia atrás desde la fecha de obtención, es decir, los mismos 90 días de `--dias-activo 90`. Se descargan los meses calendario que cubren ese período y se descartan las partidas anteriores a su inicio. Si `--meses × 30` fuera menor que `--dias-activo`, `ch scout` muestra un aviso.
- `--min-partidas 20` descartó a 9 de los 19 jugadores activos: muchos jugadores que se conectaron en los últimos 90 días jugaron muy pocas partidas en ese período. `--max-partidas 200` dejó una muestra con jugadores de distinta actividad (de 42 a 200 partidas).

## 5. Sesgo de la lista de Chile

La API no entrega la lista completa del país. La respuesta incluye el campo `comment`:

> Results are temporarily reduced to the first 10000 players for performance reasons

Los 10.000 nombres son los primeros en orden alfabético: van de `-kvn-` a `chacal_patriota`.

| Inicial | Nombres |
|---|---|
| Dígitos y `-` | 864 |
| a | 4.856 |
| b | 2.807 |
| c | 1.473 |
| d a z | 0 |

Esto significa que la muestra solo puede contener jugadores cuyo nombre empieza con un dígito, `-`, `a`, `b` o `c`. La semilla mezcla el orden dentro de esa lista, pero no corrige el corte.

No hay una razón evidente para que la inicial del nombre se relacione con el nivel de juego, pero la muestra no es aleatoria respecto de todos los jugadores chilenos, y así se considera al interpretar los resultados.

## 6. Observaciones

- Los 19 perfiles revisados estaban activos, por lo que en esta corrida el filtro de actividad no descartó jugadores; el filtro que más descartó fue el mínimo de partidas. Con solo 19 perfiles no se puede afirmar que la lista del país contenga únicamente cuentas activas.
- Las estadísticas de cada jugador se guardaron en `data/raw/stats_<usuario>.json`. Además de las modalidades, la respuesta trae claves que no son modalidades (`tactics`, `lessons`, `puzzle_rush` y `fide`), que `ch stats` excluye.
- El campo `timeout_percent` solo aparece en las modalidades por correspondencia (`chess_daily` y `chess960_daily`).
