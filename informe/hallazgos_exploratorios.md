# Hallazgos exploratorios — Player One

## 1. Introducción

Se realizó un análisis exploratorio de **1.440 registros de partidas de Chess.com**, utilizando el comando `ch explore`, desarrollado en Nushell e integrado con la biblioteca Polars de Python.

El objetivo fue identificar patrones relacionados con el porcentaje de victorias, las diferencias de rating entre jugadores y rivales, y la distribución de partidas según sus características.

A continuación, se presentan tres hallazgos obtenidos a partir de los resultados.

## 2. Hallazgo 1: El porcentaje de victorias varía según la modalidad

Se observaron diferencias en el porcentaje de victorias entre las distintas modalidades de juego.

- **Rapid:** 51,45 % de victorias en 760 partidas.
- **Blitz:** 43,38 % de victorias en 491 partidas.
- **Bullet:** 41,18 % de victorias en 187 partidas.
- **Daily:** 100 % de victorias en 2 partidas.

La modalidad Rapid presentó el mayor porcentaje de victorias entre las modalidades con una cantidad considerable de registros, superando a Blitz en **8,07 puntos porcentuales**.

Por su parte, Bullet registró un porcentaje de victorias inferior al de Rapid y Blitz.

El resultado de Daily debe interpretarse con especial precaución, debido a que solamente se analizaron dos partidas de esta modalidad.

## 3. Hallazgo 2: La diferencia de rating se relaciona con el resultado de las partidas

Se analizó la diferencia entre el rating previo del jugador y el rating de su rival, definida como:

**d = rating_previo - rating_rival**

Los resultados muestran que:

- Los jugadores con una desventaja de 1 a 100 puntos de rating ganaron el **28,57 %** de sus partidas (693 registros).
- Los jugadores con una ventaja de 1 a 100 puntos de rating ganaron el **65,36 %** de sus partidas (690 registros).
- Los jugadores con una ventaja de 101 a 200 puntos obtuvieron un **100 %** de victorias, aunque este grupo solo contiene 14 partidas.

Estos resultados sugieren una asociación entre tener un rating superior al del rival y obtener una mayor proporción de victorias.

No obstante, se trata de un análisis descriptivo que no permite establecer relaciones causales. Además, los grupos con pocos registros deben interpretarse con precaución.

## 4. Hallazgo 3: La actividad de juego se concentró en octubre de 2026

La distribución mensual de las partidas fue la siguiente:

| Mes | Partidas |
|---|---:|
| Septiembre de 2026 | 223 |
| Octubre de 2026 | 770 |
| Noviembre de 2026 | 447 |
| **Total** | **1.440** |

Octubre concentró aproximadamente el **53,47 %** de las partidas analizadas, convirtiéndose en el mes con mayor cantidad de registros.

Esto indica que la actividad observada no se distribuyó uniformemente durante el período estudiado. Sin embargo, también puede reflejar diferencias en la disponibilidad de datos entre los meses.

## 5. Conclusión

El análisis exploratorio permitió identificar tres patrones principales:

1. Existen diferencias en los porcentajes de victorias entre modalidades, especialmente entre Rapid y Blitz.
2. Una diferencia positiva de rating se asocia con una mayor proporción de victorias.
3. La mayor cantidad de partidas registradas corresponde a octubre de 2026.

Estos hallazgos proporcionan una descripción inicial de los datos y pueden servir como referencia para interpretar los resultados del modelo predictivo desarrollado en el proyecto.

**Fuente:** `data/partidas_limpias.csv`, procesado mediante `ch explore` con Polars de Python.
