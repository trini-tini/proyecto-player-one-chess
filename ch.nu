# Player One: consola de scouting de ajedrez sobre la PubAPI de Chess.com
#
# Uso (desde la raíz del repositorio):
#   $env.CHESS_EMAIL = "su_correo@ejemplo.cl"
#   use ch.nu *
#   ch perfil hikaru

const API = "https://api.chess.com/pub"
const CACHE_DIR = "cache"
const VIGENCIA_CACHE = 12hr
const MAX_REINTENTOS = 3

# ---------------------------------------------------------------------------
# Helper HTTP: User-Agent, caché y manejo de códigos de estado
# ---------------------------------------------------------------------------

# User-Agent con el correo de contacto leído de la variable de entorno
def user-agent [] {
    let correo = ($env.CHESS_EMAIL? | default "")
    if ($correo | is-empty) {
        error make {msg: "Falta la variable de entorno CHESS_EMAIL. Ejemplo: $env.CHESS_EMAIL = \"nombre@correo.cl\""}
    }
    $"PlayerOne-UBB/1.0 \(contacto: ($correo)\)"
}

# Archivo de caché asociado a una URL (las "/" pasan a "__")
def ruta-cache [url: string] {
    let nombre = ($url | str replace $"($API)/" "" | str replace --all "/" "__")
    $"($CACHE_DIR)/($nombre).json"
}

# Consulta serial a la API. Devuelve los datos o null si no están disponibles.
def api-get [url: string] {
    let archivo = (ruta-cache $url)
    let eliminadas = $"($CACHE_DIR)/eliminadas_410.txt"

    # 410: la dirección fue eliminada y no se vuelve a solicitar
    if ($eliminadas | path exists) and ($url in (open $eliminadas | lines)) {
        print -e $"Aviso: ($url) respondió 410 antes; no se vuelve a solicitar."
        return null
    }

    # Caché vigente: se usa sin consultar la API
    if ($archivo | path exists) {
        let antiguedad = ((date now) - (ls $archivo | get 0.modified))
        if $antiguedad < $VIGENCIA_CACHE {
            return (open $archivo)
        }
    }

    mut intento = 0
    loop {
        let respuesta = (http get -e -f -H {User-Agent: (user-agent)} $url)
        match $respuesta.status {
            200 => {
                mkdir $CACHE_DIR
                $respuesta.body | to json | save -f $archivo
                return $respuesta.body
            }
            429 => {
                $intento = $intento + 1
                if $intento > $MAX_REINTENTOS {
                    error make {msg: $"429: demasiadas solicitudes a ($url), se agotaron ($MAX_REINTENTOS) reintentos."}
                }
                print -e $"429: esperando ($intento * 5) s antes del reintento ($intento)/($MAX_REINTENTOS)..."
                sleep (5sec * $intento)
            }
            404 => {
                print -e $"Aviso: dato no disponible \(404\) en ($url)"
                return null
            }
            410 => {
                mkdir $CACHE_DIR
                $"($url)\n" | save -a $eliminadas
                print -e $"Aviso: ($url) fue eliminado \(410\); no se volverá a solicitar."
                return null
            }
            _ => {
                error make {msg: $"Error HTTP ($respuesta.status) al consultar ($url)"}
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

# Segundos Unix (UTC) a fecha; null si el campo falta
def a-fecha [segundos] {
    if $segundos == null { return null }
    $segundos * 1_000_000_000 | into datetime -z UTC
}

# "https://api.chess.com/pub/country/CL" -> "CL"
def codigo-pais [url] {
    if $url == null { return null }
    $url | split row "/" | last
}

# Códigos de result (sección "Game results codes") a victoria/derrota/empate
def traducir-resultado [codigo] {
    match $codigo {
        "win" => "victoria"
        "checkmated" | "resigned" | "timeout" | "abandoned" | "lose" | "kingofthehill" | "threecheck" | "bughousepartnerlose" => "derrota"
        "agreed" | "repetition" | "stalemate" | "insufficient" | "50move" | "timevsinsufficient" => "empate"
        _ => null
    }
}

# Etiqueta Result del PGN vista desde el color del jugador
def resultado-pgn [pgn, color: string] {
    if $pgn == null { return null }
    let etiqueta = ($pgn | parse --regex '\[Result "(?<r>[^"]+)"\]')
    if ($etiqueta | is-empty) { return null }
    match [$etiqueta.0.r $color] {
        ["1-0" "blancas"] | ["0-1" "negras"] => "victoria"
        ["0-1" "blancas"] | ["1-0" "negras"] => "derrota"
        ["1/2-1/2" _] => "empate"
        _ => "*"
    }
}

# Código ECO desde el PGN (letra A-E y dos dígitos); null si no existe
def extraer-eco [pgn] {
    if $pgn == null { return null }
    let eco = ($pgn | parse --regex '\[ECO "(?<eco>[A-E]\d{2})"\]')
    if ($eco | is-empty) { null } else { $eco.0.eco }
}

# ---------------------------------------------------------------------------
# 1.2.1 Perfil y estadísticas
# ---------------------------------------------------------------------------

# Perfil de un jugador
export def "ch perfil" [
    usuario: string  # nombre de usuario en Chess.com
] {
    let perfil = (api-get $"($API)/player/($usuario | str downcase)")
    if $perfil == null { return }

    let ultimo = (a-fecha $perfil.last_online?)
    let cerrada = ($perfil.status | str starts-with "closed")
    if $cerrada {
        print -e $"Aviso: la cuenta ($perfil.username) está cerrada \(($perfil.status)\)."
    }

    {
        usuario: $perfil.username
        nombre: $perfil.name?
        titulo: $perfil.title?
        estado: $perfil.status
        cuenta_cerrada: $cerrada
        pais: (codigo-pais $perfil.country?)
        seguidores: $perfil.followers?
        registro: (a-fecha $perfil.joined?)
        ultimo_acceso: $ultimo
        dias_desde_acceso: (if $ultimo == null { null } else { ((date now) - $ultimo) / 1day | math floor })
    }
}

# Estadísticas por modalidad de un jugador
export def "ch stats" [
    usuario: string        # nombre de usuario en Chess.com
    --modo (-m): string    # modalidad: blitz, rapid, bullet, daily, chess960_daily...
] {
    let stats = (api-get $"($API)/player/($usuario | str downcase)/stats")
    if $stats == null { return }

    # fide es un número suelto, no una modalidad; las otras tres no son partidas
    let filas = ($stats
        | transpose modalidad datos
        | where modalidad not-in [tactics lessons puzzle_rush fide]
        | each {|fila|
            let r = $fila.datos.record
            let total = $r.win + $r.loss + $r.draw
            {
                modalidad: $fila.modalidad
                rating_actual: $fila.datos.last?.rating?
                mejor_rating: $fila.datos.best?.rating?
                ganadas: $r.win
                perdidas: $r.loss
                empatadas: $r.draw
                pct_victorias: (if $total == 0 { null } else { $r.win / $total * 100 | math round -p 1 })
                pct_timeout: $r.timeout_percent?
            }
        })

    if $modo == null { return $filas }

    # Acepta "blitz" o "chess_blitz"
    let elegidas = ($filas | where {|f| $f.modalidad == $modo or $f.modalidad == $"chess_($modo)" })
    if ($elegidas | is-empty) {
        print -e $"Aviso: ($usuario) no tiene la modalidad '($modo)'. Disponibles: ($filas.modalidad | str join ', ')"
    }
    $elegidas
}

# ---------------------------------------------------------------------------
# 1.2.2 Partidas
# ---------------------------------------------------------------------------

# Partidas de un jugador en un mes
export def "ch partidas" [
    usuario: string            # nombre de usuario en Chess.com
    anio: int                  # año, por ejemplo 2026
    mes: int                   # mes, de 1 a 12
    --modo (-m): string        # time_class: bullet, blitz, rapid o daily
    --color (-c): string       # blancas o negras
    --resultado (-r): string   # victoria, derrota o empate
] {
    if $color != null and $color not-in [blancas negras] {
        error make {msg: "--color debe ser blancas o negras"}
    }
    if $resultado != null and $resultado not-in [victoria derrota empate] {
        error make {msg: "--resultado debe ser victoria, derrota o empate"}
    }

    let u = ($usuario | str downcase)
    let mes_txt = ($mes | into string | fill -a r -c "0" -w 2)
    let url_mes = $"($API)/player/($u)/games/($anio)/($mes_txt)"

    # Se valida contra la lista de meses disponibles
    let archivos = (api-get $"($API)/player/($u)/games/archives")
    if $archivos == null { return }
    if $url_mes not-in $archivos.archives {
        print -e $"Aviso: ($usuario) no tiene partidas archivadas en ($anio)-($mes_txt)."
        return
    }

    let juegos = (api-get $url_mes | get games? | default [])
    if ($juegos | is-empty) {
        print -e $"Aviso: el mes ($anio)-($mes_txt) no tiene partidas."
        return
    }

    let tabla = ($juegos | each {|g|
        let es_blancas = (($g.white.username | str downcase) == $u)
        let propio = (if $es_blancas { $g.white } else { $g.black })
        let rival = (if $es_blancas { $g.black } else { $g.white })
        let color_txt = (if $es_blancas { "blancas" } else { "negras" })
        {
            fecha_fin: (a-fecha $g.end_time)
            rival: $rival.username
            color: $color_txt
            resultado: (traducir-resultado $propio.result)
            rating_propio: $propio.rating
            rating_rival: $rival.rating
            modalidad: $g.time_class
            reglas: $g.rules
            eco: (extraer-eco $g.pgn?)
            codigo_api: $propio.result
            resultado_pgn: (resultado-pgn $g.pgn? $color_txt)
        }
    })

    # Comparación con la etiqueta Result del PGN
    let sin_resultado = ($tabla | where resultado_pgn == "*" | length)
    let discrepancias = ($tabla | where resultado_pgn != "*" and resultado != $it.resultado_pgn)
    print -e $"Verificación contra el PGN: ($tabla | length) partidas, ($discrepancias | length) discrepancias, ($sin_resultado) con '*'."
    if ($discrepancias | is-not-empty) {
        print -e ($discrepancias | select fecha_fin rival codigo_api resultado resultado_pgn)
    }

    mut salida = ($tabla | reject codigo_api resultado_pgn | sort-by fecha_fin)
    if $modo != null { $salida = ($salida | where modalidad == $modo) }
    if $color != null { $salida = ($salida | where color == $color) }
    if $resultado != null { $salida = ($salida | where resultado == $resultado) }

    if ($salida | is-empty) {
        print -e "Aviso: ninguna partida cumple los filtros indicados."
    }
    $salida
}
