# Hallazgos exploratorios — Player One

## 1. Introducción

Se realizó un análisis exploratorio de 1.426 registros de partidas de Chess.com, utilizando el comando `ch explore` desarrollado en Nushell.

El objetivo fue identificar patrones relacionados con el porcentaje de victorias, las diferencias de rating entre jugadores y rivales, y la distribución de partidas según sus características.

A continuación, se presentan tres hallazgos obtenidos a partir de los resultados.

## 2. Hallazgo 1: El porcentaje de victorias varía según la modalidad

Se observaron diferencias en el porcentaje de victorias entre las distintas modalidades de juego.

- **Rapid:** 49,16 % de victorias en 838 partidas.
- **Blitz:** 43,09 % de victorias en 550 partidas.
- **Bullet:** 27,78 % de victorias en 36 partidas.
- **Daily:** 100 % de victorias en 2 partidas.

La modalidad Rapid presentó el mayor porcentaje de victorias entre las modalidades con una cantidad considerable de registros, superando a Blitz en 6,07 puntos porcentuales.

Sin embargo, los resultados de Daily y Bullet deben interpretarse con precaución debido a sus tamaños de muestra reducidos.

## 3. Hallazgo 2: La diferencia de rating se relaciona con el resultado de las partidas

Se analizó la diferencia entre el rating previo del jugador y el rating de su rival, definida como:

**d = rating_previo - rating_rival**

Los resultados muestran que:

- Los jugadores con una desventaja de 1 a 100 puntos de rating ganaron el 27,97 % de sus partidas (690 registros).
- Los jugadores con una ventaja de 1 a 100 puntos de rating ganaron el 65,28 % de sus partidas (651 registros).
- Los jugadores con una ventaja de 101 a 200 puntos obtuvieron un 93,33 % de victorias, aunque este grupo solo contiene 15 partidas.

Estos resultados sugieren una asociación entre tener un rating superior al del rival y obtener una mayor proporción de victorias.

No obstante, se trata de un análisis descriptivo que no permite establecer relaciones causales.

## 4. Hallazgo 3: La actividad de juego se concentró en octubre de 2026

La distribución mensual de las partidas fue la siguiente:

| Mes | Partidas |
|---|---:|
| Agosto de 2026 | 40 |
| Septiembre de 2026 | 328 |
| Octubre de 2026 | 643 |
| Noviembre de 2026 | 415 |
| **Total** | **1.426** |

Octubre concentró aproximadamente el **45,09 %** de las partidas analizadas, convirtiéndose en el mes con mayor cantidad de registros.

Esto indica que la actividad observada no se distribuyó uniformemente durante el período estudiado. Sin embargo, también puede reflejar diferencias en la disponibilidad de datos entre los meses.

## 5. Conclusión

El análisis exploratorio permitió identificar tres patrones principales:

1. Existen diferencias en los porcentajes de victorias entre modalidades, especialmente entre Rapid y Blitz.
2. Una diferencia positiva de rating se asocia con una mayor proporción de victorias.
3. La mayor cantidad de partidas registradas corresponde a octubre de 2026.

Estos hallazgos proporcionan una descripción inicial de los datos y pueden servir como referencia para interpretar los resultados del modelo predictivo desarrollado en el proyecto.

**Fuente:** `data/partidas_limpias.csv`, procesado mediante `ch explore`.
