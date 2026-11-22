# Hallazgos exploratorios — Player One

## 1. Introducción

Se analizaron las 1.399 filas de `data/partidas_limpias.csv` (corrida oficial del 22-nov-2026: 10 jugadores de Chile, partidas desde el 24-ago-2026). Cada fila es una partida vista desde un jugador de la muestra.

Las tablas se obtuvieron con `ch explore`, que usa el plugin `polars` de Nushell y guarda cada tabla en `data/exploracion/`.

## 2. Hallazgo 1: la diferencia de rating parece decidir el resultado, pero es un efecto de la fuga en `rating_rival`

Con `d = rating_previo - rating_rival`, el porcentaje de victorias cambia de forma brusca entre tramos muy cercanos:

| Tramo de `d` | Partidas | % victorias |
|---|---:|---:|
| ≤ -51 | 32 | 12,50 |
| -50 a -26 | 119 | 2,52 |
| -25 a -1 | 552 | 32,43 |
| 0 | 34 | 61,76 |
| 1 a 25 | 491 | 60,49 |
| 26 a 50 | 123 | 91,87 |
| ≥ 51 | 48 | 89,58 |

Según Elo, una diferencia de 25 a 50 puntos debería dar entre un 54 % y un 57 % de victorias, no un 92 %. El salto se explica porque la API entrega el rating del rival después de la partida es decir si el jugador gana, el rival pierde puntos y `d` sube; si pierde, `d` baja. El cambio promedio por partida es de unos 10 puntos (`sesgo_rating_rival` = 10,6 en `data/modelo/metricas.json`), comparable al promedio de |`d`| (22,1).

Para comprobarlo, se estimó el rating del rival antes de la partida sumándole el cambio del propio jugador (los cambios de ambos jugadores son simétricos). Con esa diferencia aproximada, el porcentaje de victorias queda casi plano:

| Tramo de `d` aproximada | Partidas | % victorias |
|---|---:|---:|
| ≤ -26 | 93 | 46,2 |
| -25 a -1 | 605 | 42,6 |
| 0 | 43 | 53,5 |
| 1 a 25 | 549 | 49,5 |
| ≥ 26 | 109 | 58,7 |

Implicancia: la ventaja de la logística sobre Elo en la prueba (pérdida logarítmica 0,544 contra 0,656) y su coeficiente de `d` (5,53 por 100 puntos, cerca de 10 veces la pendiente de Elo, 0,576) se deben en gran parte a esta fuga, y no anticipan cómo resultaría una partida futura. Chess.com empareja rivales de rating muy parecido, así que antes de jugar la diferencia real es pequeña y aporta poca información.

## 3. Hallazgo 2: no hay una ventaja medible por jugar con blancas

| Color | Partidas | % victorias | Margen 95 % |
|---|---:|---:|---:|
| Blancas | 702 | 47,72 | ± 3,69 |
| Negras | 697 | 46,63 | ± 3,70 |

La diferencia (1,1 puntos) es mucho menor que el margen de cada proporción, y por modalidad no tiene un signo constante: en rapid las blancas ganan más (51,65 % contra 46,27 %), pero en blitz y bullet ganan menos.

Implicancia: en este nivel de juego (rating previo medio por jugador entre 139 y 1.429), la ventaja teórica de las blancas no se distingue del ruido con unas 700 partidas por color.

## 4. Hallazgo 3: la muestra se concentra en pocos jugadores y en las semanas más recientes

| Jugador | Filas | % de la muestra | Rating previo medio |
|---|---:|---:|---:|
| alex_geell | 199 | 14,22 | 663 |
| apr2025 | 199 | 14,22 | 1.429 |
| alvaropuchi | 198 | 14,15 | 357 |
| 3squin4 | 191 | 13,65 | 707 |
| otros 6 jugadores | 612 | 43,75 | 139 a 802 |

Los cuatro jugadores que alcanzaron el tope de 200 partidas (`--max-partidas`) suman el 56 % de las filas. Como el tope conserva las partidas más recientes, la muestra también se concentra en el tiempo:

| Mes | Partidas |
|---|---:|
| Agosto de 2026 (desde el 24) | 5 |
| Septiembre de 2026 | 91 |
| Octubre de 2026 | 396 |
| Noviembre de 2026 (hasta el 22) | 907 |

Implicancia: esta distribución viene del diseño de la obtención (ventana de 90 días y tope por jugador), no de un cambio en la actividad de los jugadores. Los resultados pesan más los hábitos de esos cuatro jugadores, y la partición cronológica deja en la prueba (30 % más reciente) casi solo partidas de noviembre.

## 5. Otras observaciones

- Modalidad: blitz tiene el menor porcentaje de victorias (42,14 % en 560 partidas), frente a rapid (48,98 %) y bullet (53,22 %). Cada jugador juega distintas modalidades en distinta proporción, así que esta diferencia puede deberse a quién juega cada una.
- Aperturas: las más frecuentes son B01 (defensa escandinava, 122), A00 (aperturas irregulares, 105) y D02 (84). D tiene el menor porcentaje de victorias (41,92 %) y B el mayor (50,24 %). La familia E tiene solo 2 partidas.
- Daily: solo hay 3 partidas, por lo que su porcentaje (66,67 %) no es interpretable.

Fuente: `data/partidas_limpias.csv` y las tablas de `data/exploracion/`, generadas con `ch explore`.
