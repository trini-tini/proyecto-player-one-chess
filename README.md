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
