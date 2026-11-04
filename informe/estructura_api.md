# Estructura JSON de la API de Chess.com

## 1. Introducción

Para desarrollar los comandos de Player One se utilizó la API pública de Chess.com (PubAPI), que entrega información en formato JSON.

Se realizaron consultas independientes utilizando `curl` y `jq` para estudiar la estructura de las respuestas y comprobar los resultados obtenidos mediante los comandos desarrollados en Nushell.

## 2. Rankings: `ch top`

**Endpoint:**

`https://api.chess.com/pub/leaderboards`

La API devuelve un objeto JSON que contiene una clave por cada categoría de clasificación.

Las categorías observadas fueron: `battle`, `daily`, `daily960`, `live_blitz`, `live_blitz960`, `live_bughouse`, `live_bullet`, `live_rapid`, `live_threecheck`, `rush` y `tactics`.

Cada categoría contiene una lista de jugadores.

Los campos utilizados por nuestro comando son:

| Campo JSON | Descripción |
|---|---|
| username | Nombre de usuario |
| rank | Posición en el ranking |
| score | Puntaje |
| country | URL del país |
| title | Título del jugador |
| win_count | Victorias |
| loss_count | Derrotas |
| draw_count | Empates |

El comando `ch top` selecciona la modalidad solicitada, limita la cantidad de jugadores y convierte la URL del país a su código correspondiente.

## 3. Países: `ch pais`

**Endpoint:**

`https://api.chess.com/pub/country/CL/players`

La respuesta contiene dos claves principales: `comment` y `players`.

La clave `players` almacena una lista de nombres de usuario en formato texto.

Durante las pruebas realizadas, la API devolvió 10.000 jugadores para Chile. Esta cifra corresponde al límite de registros devueltos y no necesariamente al total de jugadores chilenos registrados.

El comando `ch pais` calcula la cantidad de elementos de la lista y muestra los primeros nombres según el parámetro `--n`.

## 4. Clubes: `ch club`

**Endpoints:**

- `https://api.chess.com/pub/club/chesscom`
- `https://api.chess.com/pub/club/chesscom/members`

El primer endpoint entrega información general del club.

Los campos principales utilizados son:

| Campo JSON | Descripción |
|---|---|
| name | Nombre del club |
| members_count | Cantidad de miembros informada |
| created | Fecha de creación |
| last_activity | Fecha de última actividad |

El segundo endpoint devuelve tres grupos de miembros:

- `weekly`
- `monthly`
- `all_time`

Cada grupo contiene una lista de objetos con los campos `username` y `joined`.

El campo `joined` corresponde a una marca de tiempo Unix expresada en segundos.

El comando `ch club` convierte estas marcas de tiempo a fechas y muestra los integrantes de cada grupo. También considera grupos vacíos y listas de miembros no disponibles.

En las pruebas realizadas con el club `chesscom`, se obtuvieron 0 integrantes en `weekly`, 0 en `monthly` y 7 en `all_time`.

## 5. Puzzles: `ch puzzle`

**Endpoints:**

- `https://api.chess.com/pub/puzzle`
- `https://api.chess.com/pub/puzzle/random`

El primer endpoint devuelve el puzzle diario y el segundo devuelve uno aleatorio.

Se comprobó que ambos presentan los mismos seis campos:

| Campo JSON | Descripción |
|---|---|
| title | Título del puzzle |
| fen | Posición del tablero |
| image | URL de la imagen |
| pgn | Notación de la partida |
| publish_time | Fecha de publicación |
| url | Enlace al puzzle |

El comando `ch puzzle` muestra el título, la posición FEN y la URL de la imagen.

La opción `--random` permite utilizar el endpoint de puzzles aleatorios.

## 6. Comparaciones con curl y jq

Se realizaron tres consultas independientes para validar los resultados de los comandos implementados en Nushell.

### 6.1. Ranking

```bash
curl -s -A "PlayerOne-UBB/1.0" https://api.chess.com/pub/leaderboards | jq '.live_blitz[:5] | map({rank, username, score})'
```

El resultado coincidió con `ch top live_blitz --n 5` en los cinco jugadores, sus posiciones y puntajes.

### 6.2. Jugadores de Chile

```bash
curl -s -A "PlayerOne-UBB/1.0" https://api.chess.com/pub/country/CL/players | jq '{total: (.players | length), primeros: .players[:3]}'
```

Se obtuvieron 10.000 registros y los tres primeros nombres coincidieron con `ch pais CL --n 3`.

### 6.3. Miembros de un club

```bash
curl -s -A "PlayerOne-UBB/1.0" https://api.chess.com/pub/club/chesscom/members | jq '{weekly: (.weekly | length), monthly: (.monthly | length), all_time: (.all_time | length)}'
```

Se obtuvieron 0, 0 y 7 integrantes, respectivamente, coincidiendo con `ch club chesscom`.

## 7. Conclusión

Las consultas permitieron identificar cómo se organiza la información JSON de la PubAPI de Chess.com y cómo los comandos de Player One transforman estas respuestas en tablas y registros de Nushell.

Las tres comparaciones independientes realizadas con `curl` y `jq` coincidieron con los resultados de los comandos implementados.

Esto proporciona evidencia del funcionamiento de los comandos y permite documentar las decisiones de extracción y presentación de los datos.

**Nota:** la API puede actualizar sus datos, por lo que los valores de rankings, jugadores y clubes pueden cambiar entre consultas.
