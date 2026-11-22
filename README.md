# Player One: scouting de ajedrez en Chess.com

Proyecto Juan Pablo Vargas y Trinidad Saez
Consola en Nushell que consulta la PubAPI de Chess.com y un pipeline reproducible sobre las partidas de jugadores.

## Requisitos

- Nushell 0.114 con el plugin `polars`
- `curl`, `jq`, GNU `parallel`
- Vowpal Wabbit (`vw`)

## Uso

Desde la raíz del repositorio, dentro de Nushell:

```nu
$env.CHESS_EMAIL = "su_correo@ejemplo.cl"   # correo de contacto 
use ch.nu *
```

| Comando | Ejemplo |
|---|---|
| `ch perfil <usuario>` | `ch perfil hikaru` |
| `ch stats <usuario> [-m modo]` | `ch stats hikaru -m blitz` |
| `ch partidas <usuario> <año> <mes> [-m modo] [-c color] [-r resultado]` | `ch partidas erik 2026 10 -c negras -r victoria` |
| `ch top <modalidad> [--n n]` | `ch top live_blitz --n 5` |
| `ch pais <iso> [--n n]` | `ch pais CL --n 20` |
| `ch club <id>` | `ch club chess-com-developer-community` |
| `ch puzzle [--random] [--tablero]` | `ch puzzle --tablero` |
| `ch scout (--pais iso \| --club id) [--n n] [--meses m] ...` | `ch scout --pais CL` |
| `ch clean` | `ch clean` |
| `ch explore` | `ch explore` |
| `ch model [--passes n]` | `ch model` |
| `ch duelo <usuario1> <usuario2> [-m modo]` | `ch duelo hikaru magnuscarlsen -m blitz` |
| `ch pipeline [--pais iso] [--semilla s] [--sin-descarga]` | `ch pipeline --sin-descarga` |

`ch explore` usa el plugin `polars` de Nushell sobre `data/partidas_limpias.csv` y guarda sus tablas en `data/exploracion/`.
