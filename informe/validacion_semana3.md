# Validación con curl y jq — Semana 3

## Objetivo

Validar la información obtenida desde la API pública de Chess.com mediante una consulta independiente utilizando `curl` y `jq`, y compararla con los resultados del comando `ch puzzle --tablero`.

## 1. Consulta inicial

Se ejecutó el siguiente comando:

```bash
curl -s https://api.chess.com/pub/puzzle | jq '{title, fen}'
```

La consulta produjo un error de interpretación JSON:

```text
jq: parse error: Invalid numeric literal at line 1, column 10
```

Al revisar la respuesta HTTP, se identificó que Chess.com devolvía un código **403**, correspondiente a un bloqueo de Cloudflare. La respuesta era HTML en lugar de JSON.

## 2. Consulta con User-Agent personalizado

Se utilizó el mismo identificador HTTP configurado en el proyecto:

```nu
^curl -sS -A $"PlayerOne-UBB/1.0 \(contacto: ($env.CHESS_EMAIL)\)" https://api.chess.com/pub/puzzle | ^jq '{title, fen}'
```

La consulta respondió correctamente y permitió extraer los campos solicitados.

Resultado:

```json
{
  "title": "That's Forking Deep 🤯",
  "fen": "r1b1k2r/1p3ppp/p2Q1n2/q1pPp3/1n2B3/1P1N4/P1PB1PPP/R3K2R b Qkq - 0 1"
}
```

## 3. Comparación con ch puzzle --tablero

Se ejecutó previamente el comando:

```nu
ch puzzle --tablero
```

El comando mostró un tablero de 8×8 construido a partir de la posición FEN y devolvió el mismo título y la misma cadena FEN obtenidos mediante `curl` y `jq`.

Por lo tanto, se comprobó la coincidencia entre los datos entregados por `ch puzzle` y los extraídos mediante la consulta independiente.

## 4. Conclusión

La validación permitió comprobar que:

- La API de Chess.com entrega los campos `title` y `fen` correctamente cuando la solicitud incluye el User-Agent del proyecto.
- El comando `ch puzzle --tablero` mostró la posición correspondiente al FEN consultado.
- La extracción independiente mediante `curl` y `jq` produjo los mismos valores observados en el comando del proyecto.

Esta prueba proporciona evidencia de consistencia entre la respuesta de la API y la información presentada por Player One.
