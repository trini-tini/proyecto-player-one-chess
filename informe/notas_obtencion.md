# Obtención de datos: `ch scout`

## 1. Fuente elegida

Se usó la fuente país, con Chile (`--pais CL`), en lugar de un club.

Razones:

- Tamaño: la lista de Chile entrega 10.000 nombres; un club como `chesscom` tiene solo 7 miembros en `all_time`, y otros devuelven 404 en la lista de miembros (por ejemplo, `chess-com-developer-community`).
- Reproducibilidad: con país, el orden de recorrido depende de una semilla (`--semilla 42`), por lo que cualquiera puede repetir la misma muestra.
- Menos sesgo de afinidad: los miembros de un club comparten intereses o nivel (un club de principiantes, de un colegio, de un streamer), lo que haría la muestra más homogénea.

## 2. Orden con semilla

La lista del país viene en orden alfabético, por lo que recorrerla tal cual tomaría siempre a los mismos jugadores. Para cada nombre se calcula una clave numérica a partir del nombre y la semilla, y la lista se ordena por esa clave:

- se parte de `(semilla mod 2147483647) + 1`;
- cada carácter del nombre, según su posición, se mezcla con la fórmula de Park-Miller: `(acumulado + código + posición) × 48271 mod 2147483647`.

La misma semilla da siempre el mismo orden. Con `--semilla 7` la muestra cambia (por ejemplo, aparecen `bryanherrera25`, `anto-i-love-you` y `bnnjzz`).

## 3. Resultado de la corrida

Se ejecutó `ch scout --pais CL` con todos los valores predeterminados:

| Concepto | Valor |
|---|---|
| Perfiles revisados | 12 |
| Jugadores activos (últimos 90 días) | 12 |
| Cuentas omitidas (cerradas o inexistentes) | 0 |
| Descartados por tener menos de 20 partidas `chess` | 2 (`canddatoss` con 7, `ch1c0terry` con 17) |
| Jugadores conservados | 10 |
| Partidas descargadas | 1.199 |
| Meses descargados | agosto, septiembre y octubre de 2026 |

Partidas por jugador: `3squin4` 200, `apr2025` 200, `alvaropuchi` 187, `alejandroyes` 172, `benjamola122` 147, `benyon_712` 146, `agustini6` 49, `afantasmado` 44, `aguchissj` 33 y `arpote0` 21.

Dos jugadores alcanzaron el tope de 200 partidas, por lo que de ellos se conservaron solo las más recientes.

El resumen queda guardado en `data/raw/resumen_scout.json`.

## 4. Flags ajustadas

No se ajustó ninguna flag; se usaron los valores predeterminados:

- `--n 10` se completó con solo 12 de las 250 consultas permitidas (`--max-consultas`), así que no fue necesario ampliar el máximo de consultas.
- `--meses 3` cubre el mismo período que `--dias-activo 90`, como pide el enunciado.
- `--min-partidas 20` y `--max-partidas 200` dejaron una muestra con jugadores de distinta actividad (de 21 a 200 partidas), sin que ninguno quedara con muy pocas partidas.

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

- Los 12 perfiles revisados estaban activos, por lo que en esta corrida el filtro de actividad no descartó jugadores. Con solo 12 perfiles no se puede afirmar que la lista del país contenga únicamente cuentas activas.
- Las estadísticas de cada jugador se guardaron en `data/raw/stats_<usuario>.json`. Además de las modalidades, la respuesta trae claves que no son modalidades (`tactics`, `lessons`, `puzzle_rush` y `fide`), que `ch stats` excluye.
- El campo `timeout_percent` solo aparece en las modalidades por correspondencia (`chess_daily` y `chess960_daily`).
