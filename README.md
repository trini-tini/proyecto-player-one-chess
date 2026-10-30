# Player One: scouting de ajedrez en Chess.com

Trabajo Grupal de Investigación del curso *Ciencia de Datos en la Terminal Linux* (Universidad del Bío-Bío, 2026).

Consola en Nushell que consulta la PubAPI de Chess.com y un pipeline reproducible de ciencia de datos sobre las partidas de jugadores.

## Requisitos

- Nushell 0.114 con el plugin `polars`
- `curl`, `jq`, GNU `parallel`
- Vowpal Wabbit (`vw`)

## Uso

Desde la raíz del repositorio, dentro de Nushell:

```nu
$env.CHESS_EMAIL = "su_correo@ejemplo.cl"   # correo de contacto para el User-Agent
use ch.nu *
```

| Comando | Ejemplo |
|---|---|
| `ch perfil <usuario>` | `ch perfil hikaru` |
| `ch stats <usuario> [-m modo]` | `ch stats hikaru -m blitz` |
| `ch partidas <usuario> <año> <mes> [-m modo] [-c color] [-r resultado]` | `ch partidas erik 2026 10 -c negras -r victoria` |
