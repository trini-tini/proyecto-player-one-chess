# Tareas semanales

## Semana 1 (30-oct a 5-nov): base y comandos de la API

**Trinidad**
- [x] Estructura del repo y `.gitignore`
- [ ] Repo en GitHub y ramas `pia` / `juanpablo`
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
