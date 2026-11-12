# Tareas semanales

## Semana 1 (30-oct a 5-nov): base y comandos de la API

**Trinidad**
- [x] Estructura del repo y `.gitignore`
- [x] Repo en GitHub y ramas `trinidad` / `juanpablo`
- [x] Helper `api-get` (User-Agent desde `CHESS_EMAIL`, caché 12 h, 429/404/410)
- [x] Utilidades (fechas, código de país, traducción de `result`, ECO)
- [x] `ch perfil`
- [x] `ch stats`
- [x] `ch partidas`

**Juan Pablo**
- [x] Documentar la estructura JSON de cada endpoint con `curl` + `jq` (`informe/estructura_api.md`)
- [x] 3 consultas `curl`/`jq` para comparar con los comandos
- [x] `ch top`
- [x] `ch pais`
- [x] `ch club`
- [x] `ch puzzle`

**Acuerdo:** `api-get <url>` devuelve el JSON ya convertido en datos, o `null` con un mensaje si recibe 404 o 410.

## Semana 2 (6 a 12-nov): obtención y depuración

**Trinidad**
- [x] `ch scout --pais CL` (orden con semilla, recorrido serial, activos, mínimo y máximo de partidas, resumen)
- [x] Corrida real con valores por defecto: 12 perfiles revisados, 12 activos, 0 omitidas, 2 descartados por pocas partidas, 10 jugadores, 1.199 partidas
- [x] Fuente elegida para el análisis: país CL (muestra grande, orden reproducible con semilla, sin el sesgo de afinidad de un club)
- [x] Anotar para el informe: la lista de CL viene cortada alfabéticamente (solo nombres de "-" a "ch")
- [x] Anotar qué flags se ajustaron y por qué (`informe/notas_obtencion.md`)

**Juan Pablo**
- [x] `ch clean` (jq + parallel, filtros, resultado vs PGN, ECO y familia, deduplicación, `rating_previo`)
- [x] Registro de filas perdidas en cada paso (`data/resumen_limpieza.json`)

**Acuerdo:**
- Partidas: `data/raw/<usuario>_<AAAA>_<MM>.json`, con la misma estructura de la API (clave `games`)
- Estadísticas: `data/raw/stats_<usuario>.json`
- Resumen de la obtención: `data/raw/resumen_scout.json` (incluye la lista `muestra`, útil para la deduplicación)
- Salida limpia: `data/partidas_limpias.csv`

## Semana 3 (13 a 19-nov): exploración, modelo y avanzados

**Trinidad**

`ch model`
- [ ] Leer `data/partidas_limpias.csv` y construir las variables: objetivo (victoria = 1; derrota y empate = 0), `d = rating_previo - rating_rival`, color y modalidad
- [ ] Partición cronológica por `fecha_fin`: 70 % más antiguo para entrenar y 30 % más reciente para evaluar
- [ ] Escribir los archivos de entrada de `vw` desde Nushell (entrenamiento y prueba)
- [ ] Ajustar con `vw --loss_function logistic` y guardar el script o la configuración en `motor/`, con la versión de `vw`
- [ ] Convertir la salida de `vw` en probabilidades con la sigmoide, en Nushell
- [ ] Comparar en prueba: (a) proporción de victorias del entrenamiento, (b) Elo `E = 1/(1 + 10^(-d/400))` y (c) logística
- [ ] Exactitud (umbral 0,5) y pérdida logarítmica (probabilidades acotadas a [1e-15, 1 - 1e-15])
- [ ] Sesgo de `rating_rival`: promedio de |rating posterior - `rating_previo`| de los jugadores analizados
- [ ] Coeficientes del modelo y si el color muestra una ventaja medible
- [ ] Guardar los coeficientes en `data/modelo/coeficientes.json`

`ch duelo <usuario1> <usuario2> [--modo]`
- [ ] Rating actual de cada jugador en la modalidad (con `ch stats`)
- [ ] Probabilidad de victoria de cada uno con Elo y con el modelo (lee `coeficientes.json`)
- [ ] Mostrar en qué casos difieren Elo y el modelo

`ch pipeline`
- [ ] Ejecuta en orden `ch scout`, `ch clean`, `ch explore` y `ch model`

Para el informe (Semana 4)
- [ ] Por qué la partición es cronológica y no aleatoria
- [ ] Motor elegido (`vw`), versión y por qué
- [ ] Composición de la muestra: ratings, partidas por jugador y si alguno concentra una parte desproporcionada

**Juan Pablo**
- [ ] `ch explore` con polars: % de victorias por color y modalidad, por tramos de `d`, top 10 de ECO, % de victorias por familia, partidas por mes y por jugador
- [ ] Borrador de los 3 hallazgos
- [ ] `ch puzzle --tablero` (FEN a tablero de 8 × 8)
- [ ] Validar con `curl` + `jq` un resultado intermedio contra la API

**Acuerdo:**
- `ch model` lee `data/partidas_limpias.csv` con las columnas del enunciado: `url`, `fecha_fin`, `jugador`, `rival`, `color`, `modalidad`, `eco`, `familia_eco`, `resultado`, `rating_previo` y `rating_rival`
- `resultado` usa los valores `victoria`, `derrota` y `empate`
- `ch model` guarda `data/modelo/coeficientes.json`, que `ch duelo` lee
