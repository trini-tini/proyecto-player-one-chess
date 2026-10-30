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
- [ ] Documentar la estructura JSON de cada endpoint con `curl` + `jq`
- [ ] 3 consultas `curl`/`jq` para comparar con los comandos
- [ ] `ch top`
- [ ] `ch pais`
- [ ] `ch club`
- [ ] `ch puzzle`

**Acuerdo:** `api-get <url>` devuelve el JSON ya convertido en datos, o `null` con un mensaje si recibe 404 o 410.

## Semana 2 (6 a 12-nov): obtención y depuración

**Trinidad**
- [x] `ch scout --pais CL` (orden con semilla, recorrido serial, activos, mínimo y máximo de partidas, resumen)
- [x] Corrida real con valores por defecto: 12 perfiles revisados, 12 activos, 0 omitidas, 2 descartados por pocas partidas, 10 jugadores, 1.199 partidas
- [x] Fuente elegida para el análisis: país CL (muestra grande, orden reproducible con semilla, sin el sesgo de afinidad de un club)
- [ ] Anotar para el informe: la lista de CL viene cortada alfabéticamente (solo nombres de "-" a "ch")

**Juan Pablo**
- [ ] `ch clean` (jq + parallel, filtros, resultado vs PGN, ECO y familia, deduplicación, `rating_previo`)
- [ ] Registro de filas perdidas en cada paso

**Acuerdo:**
- Partidas: `data/raw/<usuario>_<AAAA>_<MM>.json`, con la misma estructura de la API (clave `games`)
- Estadísticas: `data/raw/stats_<usuario>.json`
- Resumen de la obtención: `data/raw/resumen_scout.json` (incluye la lista `muestra`, útil para la deduplicación)
- Salida limpia: `data/partidas_limpias.csv`
