# Player One: scouting de ajedrez en Chess.com

Proyecto Juan Pablo Vargas y Trinidad Saez
Consola en Nushell que consulta la PubAPI de Chess.com y un pipeline reproducible sobre las partidas de jugadores.

## Requisitos

- Nushell 0.117
- Python 3.12 con Polars 2.1.0 (instalado mediante requirements.txt)
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

## Instalación de Polars

El comando `ch explore` utiliza Polars de Python para realizar el análisis exploratorio de las partidas, manteniendo Nushell como interfaz principal.

Desde la raíz del proyecto, ejecutar en Nushell:

```nu
^python3 -m venv .venv
^./.venv/bin/python -m pip install -r requirements.txt
```

Estos comandos crean un entorno virtual e instalan las dependencias necesarias.

**Nota:** La carpeta `.venv/` no se incluye en GitHub, por lo que cada integrante debe ejecutar estos comandos una vez en su computador.

## Ejecutar el análisis exploratorio

Después de instalar Polars, ejecutar:

```nu
use ch.nu *
ch explore
```

El comando utiliza `explore_polars.py` para procesar `data/partidas_limpias.csv` y mostrar los resultados de los análisis exploratorios.

Para ejecutar directamente el script de Python:

```nu
^./.venv/bin/python explore_polars.py
```

**Importante:** esta implementación utiliza la biblioteca Polars de Python, no el plugin nativo de Nushell.
