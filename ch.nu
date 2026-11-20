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


# Helper HTTP: User-Agent, caché y manejo de códigos de estado


# User-Agent con el correo  leído de la variable de entorno
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

# Utilidades
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

# Valor de la etiqueta Result ("1-0", "0-1", "1/2-1/2") visto desde el color del jugador
def resultado-etiqueta [etiqueta: string, color: string] {
    match [$etiqueta $color] {
        ["1-0" "blancas"] | ["0-1" "negras"] => "victoria"
        ["0-1" "blancas"] | ["1-0" "negras"] => "derrota"
        ["1/2-1/2" _] => "empate"
        _ => "*"
    }
}

# Etiqueta Result del PGN vista desde el color del jugador
def resultado-pgn [pgn, color: string] {
    if $pgn == null { return null }
    let etiqueta = ($pgn | parse --regex '\[Result "(?<r>[^"]+)"\]')
    if ($etiqueta | is-empty) { return null }
    resultado-etiqueta $etiqueta.0.r $color
}

# Código ECO desde el PGN (letra A-E y dos dígitos); null si no existe
def extraer-eco [pgn] {
    if $pgn == null { return null }
    let eco = ($pgn | parse --regex '\[ECO "(?<eco>[A-E]\d{2})"\]')
    if ($eco | is-empty) { null } else { $eco.0.eco }
}

# 1.2.1 Perfil y estadísticas
# Perfil de un jugador
export def "ch perfil" [
    usuario: string  # nombre de usuario en chess.com
] {
    let perfil = (api-get $"($API)/player/($usuario | str lowercase)")
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
    --modo (-m): string    # modalidad: blitz, rapid, bullet, daily, chess960_daily,etc
] {
    let stats = (api-get $"($API)/player/($usuario | str lowercase)/stats")
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

# 1.2.2 Partidas
# Partidas de un jugador en un mes
export def "ch partidas" [
    usuario: string            # nombre de usuario en Chess.com
    anio: int                  # año
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

    let u = ($usuario | str lowercase)
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
        let es_blancas = (($g.white.username | str lowercase) == $u)
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

# 2.1 Obtención
const RAW_DIR = "data/raw"
const ALFABETO = "abcdefghijklmnopqrstuvwxyz0123456789-_"
const PRIMO = 2147483647    # 2^31 - 1 (generador de Park-Miller)
const MULT = 48271

# Valor pseudoaleatorio reproducible a partir del nombre y la semilla.
# Cada carácter se suma y se multiplica por MULT módulo PRIMO; así nombres
# parecidos quedan lejos entre sí y el orden no depende del alfabeto.
def clave-semilla [nombre: string, semilla: int] {
    let inicial = (($semilla mod $PRIMO) + 1)
    let mezcla = ($nombre | str lowercase | split chars | enumerate | reduce -f $inicial {|c, acc|
        let codigo = (($ALFABETO | str index-of $c.item) + 2)
        (($acc + $codigo + $c.index) * $MULT) mod $PRIMO
    })
    ($mezcla * $MULT) mod $PRIMO
}

# Meses calendario que cubren desde `inicio` hasta hoy (del más reciente al más antiguo)
def meses-periodo [inicio: datetime] {
    let desde = (($inicio | format date "%Y" | into int) * 12 + ($inicio | format date "%m" | into int) - 1)
    let hasta = ((date now | format date "%Y" | into int) * 12 + (date now | format date "%m" | into int) - 1)
    $desde..$hasta | each {|total| {anio: ($total // 12), mes: ($total mod 12 + 1)} } | reverse
}

# Obtiene la muestra de jugadores y guarda sus partidas en data/raw/
export def "ch scout" [
    --club: string                 # id del club (último tramo de su URL)
    --pais: string                 # código ISO del país, por ejemplo CL
    --n: int = 10                  # cantidad de jugadores a analizar
    --actividad: string = "all_time"  # grupo de miembros del club: weekly, monthly o all_time
    --dias-activo: int = 90        # activo si last_online está dentro de estos días
    --max-consultas: int = 250     # máximo de perfiles a consultar
    --meses: int = 3               # meses de partidas por jugador (bloques de 30 días hacia atrás)
    --min-partidas: int = 20       # mínimo de partidas con rules = chess
    --max-partidas: int = 200      # máximo de partidas por jugador (las más recientes)
    --semilla: int = 42            # orden reproducible de la lista del país
] {
    if ($club == null) == ($pais == null) {
        error make {msg: "Indique exactamente una fuente: --club <id> o --pais <ISO>"}
    }

    # Candidatos según la fuente
    let candidatos = if $pais != null {
        let lista = (api-get $"($API)/country/($pais | str uppercase)/players")
        if $lista == null { return }
        print -e $"País ($pais | str uppercase): ($lista.players | length) nombres; ordenando con semilla ($semilla)..."
        $lista.players
        | each {|u| {usuario: $u, clave: (clave-semilla $u $semilla)} }
        | sort-by clave usuario
        | get usuario
    } else {
        if $actividad not-in [weekly monthly all_time] {
            error make {msg: "--actividad debe ser weekly, monthly o all_time"}
        }
        let miembros = (api-get $"($API)/club/($club)/members")
        if $miembros == null {
            print -e $"Aviso: la lista de miembros del club ($club) no está disponible."
            return
        }
        let grupo = ($miembros | get -o $actividad | default [])
        print -e $"Club ($club), grupo ($actividad): ($grupo | length) miembros."
        $grupo | get -o username | default []
    }

    if ($candidatos | is-empty) {
        print -e "Aviso: la fuente no tiene candidatos."
        return
    }

    # Se parte de data/raw vacío para que la muestra corresponda a esta ejecución
    mkdir $RAW_DIR
    let previos = (ls $RAW_DIR | where name =~ '\.json$')
    if ($previos | is-not-empty) { $previos | each {|f| rm $f.name } | ignore }

    # Período de partidas: últimos meses × 30 días; debe cubrir el período de actividad
    let ahora = (date now)
    let inicio = ($ahora - ($meses * 30day))
    let inicio_unix = (($inicio | into int) // 1_000_000_000)
    let periodo = (meses-periodo $inicio)
    if ($meses * 30) < $dias_activo {
        print -e $"Aviso: --meses ($meses) cubre ($meses * 30) días, menos que --dias-activo ($dias_activo). Un jugador activo podría quedar sin partidas en el período."
    }
    print -e $"Período de partidas: desde ($inicio | format date '%Y-%m-%d') \(meses ($periodo | each {|p| $'($p.anio)-($p.mes)' } | str join ', ')\)"

    mut revisados = 0
    mut activos = 0
    mut omitidas = 0
    mut pocas_partidas = 0
    mut partidas = 0
    mut muestra = []

    for usuario in $candidatos {
        if ($muestra | length) >= $n or $revisados >= $max_consultas { break }

        let perfil = (api-get $"($API)/player/($usuario | str lowercase)")
        $revisados = $revisados + 1

        # Cuentas inexistentes o cerradas se omiten y se cuentan
        if $perfil == null or ($perfil.status? | default "" | str starts-with "closed") {
            $omitidas = $omitidas + 1
            continue
        }

        let ultimo = (a-fecha $perfil.last_online?)
        if $ultimo == null or (($ahora - $ultimo) / 1day) > $dias_activo { continue }
        $activos = $activos + 1

        # Partidas de los meses del período que existan en el archivo del jugador
        let u = $perfil.username
        let archivos = (api-get $"($API)/player/($u | str lowercase)/games/archives" | get -o archives | default [])
        let juegos = ($periodo
            | each {|p|
                let mes_txt = ($p.mes | into string | fill -a r -c "0" -w 2)
                let url = $"($API)/player/($u | str lowercase)/games/($p.anio)/($mes_txt)"
                if $url in $archivos {
                    api-get $url | get -o games | default []
                    | where {|g| ($g.end_time? | default 0) >= $inicio_unix }
                    | each {|g| $g | insert archivo_mes $"($p.anio)_($mes_txt)" }
                } else { [] }
            }
            | flatten)

        # Tope: se conservan las más recientes; el mínimo se exige sobre rules = chess
        let conservadas = ($juegos | sort-by end_time -r | first $max_partidas)
        let estandar = ($conservadas | where rules == "chess" | length)
        if $estandar < $min_partidas {
            $pocas_partidas = $pocas_partidas + 1
            print -e $"  ($u): activo, ($estandar) partidas estándar \(< ($min_partidas)\), descartado"
            continue
        }

        # Un archivo por jugador y mes, con la misma estructura de la API (clave games)
        $conservadas | group-by archivo_mes | transpose archivo_mes juegos | each {|grupo|
            {games: ($grupo.juegos | reject archivo_mes)} | to json | save -f $"($RAW_DIR)/($u)_($grupo.archivo_mes).json"
        } | ignore

        let stats = (api-get $"($API)/player/($u | str lowercase)/stats")
        if $stats != null { $stats | to json | save -f $"($RAW_DIR)/stats_($u).json" }

        $partidas = $partidas + ($conservadas | length)
        $muestra = ($muestra | append $u)
        print -e $"  ($u): conservado con ($conservadas | length) partidas \(($estandar) estándar\) [($muestra | length)/($n)]"
    }

    let resumen = {
        fuente: (if $pais != null { $"pais ($pais | str uppercase)" } else { $"club ($club) / ($actividad)" })
        semilla: (if $pais != null { $semilla } else { null })
        fecha_obtencion: ($ahora | format date "%Y-%m-%d %H:%M:%S")
        periodo_desde: ($inicio | format date "%Y-%m-%d %H:%M:%S")
        revisados: $revisados
        activos: $activos
        cuentas_omitidas: $omitidas
        descartados_pocas_partidas: $pocas_partidas
        jugadores: ($muestra | length)
        partidas_descargadas: $partidas
        muestra: $muestra
    }
    $resumen | to json | save -f $"($RAW_DIR)/resumen_scout.json"

    if ($muestra | length) < $n {
        print -e $"Aviso: solo se reunieron ($muestra | length) de ($n) jugadores \(se alcanzó el límite de consultas o se agotaron los candidatos\)."
    }
    $resumen
}



# ==========================================
# JUAN PABLO - COMANDO CH TOP
# Ranking de jugadores de Chess.com
# ==========================================

export def "ch top" [
    modalidad: string          # Modalidad del ranking
    --n: int = 10              # Cantidad de jugadores (maximo 50)
] {
    # Validar la cantidad solicitada
    if $n < 1 or $n > 50 {
        error make {msg: "--n debe estar entre 1 y 50"}
    }

    # Consultar los rankings de Chess.com
    let rankings = (api-get $"($API)/leaderboards")

    if $rankings == null {
        return
    }

    # Verificar si existe la modalidad solicitada
    let modalidades = ($rankings | columns)

    if $modalidad not-in $modalidades {
        error make {
            msg: $"Modalidad no valida: ($modalidad). Disponibles: ($modalidades | str join ', ')"
        }
    }

    # Seleccionar los jugadores
    let jugadores = (
        $rankings
        | get $modalidad
        | first $n
    )

    # Construir la tabla de resultados
    $jugadores | each {|jugador|
        {
            posicion: $jugador.rank
            usuario: $jugador.username
            puntaje: $jugador.score
            pais: (codigo-pais $jugador.country?)
            titulo: $jugador.title?
            ganadas: $jugador.win_count?
            perdidas: $jugador.loss_count?
            empatadas: $jugador.draw_count?
        }
    }
}


# ==========================================
# JUAN PABLO - COMANDO CH PAIS
# Consulta jugadores de un pais en Chess.com
# ==========================================

export def "ch pais" [
    iso: string               # Codigo del pais, por ejemplo CL
    --n: int = 10             # Cantidad de nombres a mostrar
] {
    # Validar el codigo del pais
    let pais = ($iso | str uppercase)

    if ($pais | str length) != 2 or ($pais !~ '^[A-Z]{2}$') {
        error make {msg: "El pais debe indicarse con un codigo ISO de dos letras, por ejemplo CL"}
    }

    # Validar la cantidad solicitada
    if $n < 1 {
        error make {msg: "--n debe ser mayor o igual a 1"}
    }

    # Consultar los jugadores del pais
    let respuesta = (api-get $"($API)/country/($pais)/players")

    if $respuesta == null {
        return
    }

    let jugadores = ($respuesta.players | default [])
    let total = ($jugadores | length)

    # Mostrar informacion general
    print $"Pais: ($pais)"
    print $"Cantidad de jugadores devueltos por la API: ($total)"

    # Mostrar los primeros n nombres
    $jugadores
    | first $n
    | enumerate
    | each {|fila|
        {
            posicion: ($fila.index + 1)
            usuario: $fila.item
        }
    }
}


# ==========================================
# JUAN PABLO - COMANDO CH CLUB
# Consulta informacion de clubes en Chess.com
# ==========================================

export def "ch club" [
    id_club: string  # Identificador del club
] {
    # Consultar el perfil del club
    let club = (api-get $"($API)/club/($id_club)")

    if $club == null {
        print $"No se encontro el club: ($id_club)"
        return
    }

    # Mostrar informacion general
    let informacion = {
        nombre: $club.name
        cantidad_miembros: $club.members_count?
        fecha_creacion: (a-fecha $club.created?)
        ultima_actividad: (a-fecha $club.last_activity?)
    }

    print "INFORMACION DEL CLUB"
    print $informacion

    # Consultar lista de miembros
    let respuesta = (api-get $"($API)/club/($id_club)/members")

    if $respuesta == null {
        print "La lista de miembros no esta disponible (404)."
        return
    }

    # Recorrer los tres grupos de miembros
    for grupo in [weekly monthly all_time] {
        let miembros = ($respuesta | get -o $grupo | default [])

        print $"GRUPO: ($grupo)"
        print $"Cantidad de miembros: ($miembros | length)"

        if ($miembros | is-empty) {
            print "Este grupo no tiene miembros."
                } else {
            $miembros
            | each {|miembro|
                {
                    usuario: $miembro.username
                    ingreso: (a-fecha $miembro.joined?)
                }
            }
            | print
        }
    }
}


# ==========================================
# JUAN PABLO - COMANDO CH PUZZLE
# Consulta puzzles de Chess.com
# ==========================================

export def "ch puzzle" [
    --random  # Mostrar un puzzle aleatorio
] {
    # Elegir el endpoint segun la opcion
    let url = if $random {
        $"($API)/puzzle/random"
    } else {
        $"($API)/puzzle"
    }

    # Consultar la API
    let respuesta = (api-get $url)

    if $respuesta == null {
        print "No se pudo obtener el puzzle."
        return
    }

    # Mostrar la informacion del puzzle
    {
        titulo: $respuesta.title?
        fen: $respuesta.fen?
        imagen: $respuesta.image?
    }
}



# ==========================================
# JUAN PABLO - COMANDO CH CLEAN
# Limpieza automatica de partidas
# ==========================================

const COLUMNAS_CRUDAS = "url,fecha_unix,jugador,rival,color,modalidad,reglas,clasificatoria,result_propio,rating_propio,rating_rival,etiqueta_pgn,eco"

export def "ch clean" [] {

    # Buscar archivos de partidas descargadas
    let archivos = (
        ls data/raw
        | where name =~ '_[0-9]{4}_[0-9]{2}\.json$'
        | get name
    )

    if ($archivos | is-empty) {
        error make {msg: "No hay archivos de partidas en data/raw"}
    }

    # Paso 1: JSON a CSV con GNU Parallel y jq (archivos locales, una fila por partida y jugador analizado)
    ^parallel --keep-order 'jq -r --arg archivo {/} -f jq/partidas.jq {}' ::: ...$archivos
    | lines
    | where $it != ""
    | prepend $COLUMNAS_CRUDAS
    | str join "\n"
    | save -f data/partidas_crudas.csv

    let crudas = (open data/partidas_crudas.csv)
    let total = ($crudas | length)

    # Paso 2: solo ajedrez estandar
    let estandar = ($crudas | where reglas == "chess")

    # Paso 2b: solo partidas clasificatorias; en las demas el rating no se actualiza
    # y el rival no se empareja por nivel, asi que rating_previo y rating_rival no son comparables
    let clasificatorias = ($estandar | where {|p| ($p.clasificatoria | into string) == "true" })

    # Paso 3: datos faltantes (se descartan si falta un campo necesario o el result no tiene traduccion)
    let traducidas = (
        $clasificatorias | insert resultado {|p| traducir-resultado $p.result_propio }
    )
    let completas = (
        $traducidas | where {|p|
            [$p.url $p.fecha_unix $p.rival $p.rating_propio $p.rating_rival $p.resultado]
            | all {|v| $v != null and $v != "" }
        }
    )
    let eco_vacio = ($completas | where eco == "" | length)

    # Paso 4: resultado de la API contra la etiqueta Result del PGN (se conserva el de la API)
    let verificadas = (
        $completas | insert resultado_pgn {|p| resultado-etiqueta $p.etiqueta_pgn $p.color }
    )
    let con_asterisco = ($verificadas | where resultado_pgn == "*")
    let discrepancias = (
        $verificadas | where {|p| $p.resultado_pgn != "*" and $p.resultado_pgn != $p.resultado }
        | select url jugador resultado resultado_pgn
    )

    # Paso 5: rating_previo = rating de la partida anterior del mismo jugador y modalidad
    # (se calcula antes de deduplicar para usar el historial completo de cada jugador)
    let con_previo = (
        $verificadas
        | insert clave {|p| $"($p.jugador)|($p.modalidad)" }
        | group-by clave
        | values
        | each {|grupo|
            let orden = ($grupo | sort-by fecha_unix)
            $orden | enumerate | each {|f|
                let previo = if $f.index == 0 { null } else { ($orden | get ($f.index - 1)).rating_propio }
                $f.item | insert rating_previo $previo
            }
        }
        | flatten
    )

    # Paso 6: una fila por partida; si ambos jugadores estan en la muestra, queda el de menor nombre
    let unicas = ($con_previo | sort-by jugador | uniq-by url)

    # Paso 7: se descarta la primera partida de cada jugador y modalidad (sin rating_previo)
    let finales = ($unicas | where rating_previo != null)

    # Paso 8: fechas, familia ECO y columnas finales
    let tabla = (
        $finales
        | insert fecha_fin {|p| a-fecha $p.fecha_unix | format date "%Y-%m-%d %H:%M:%S" }
        | insert familia_eco {|p| $p.eco | str substring 0..0 }
        | sort-by fecha_fin jugador
        | select url fecha_fin jugador rival color modalidad eco familia_eco resultado rating_previo rating_rival
    )

    $tabla | to csv | save -f data/partidas_limpias.csv

    # Registro de filas en cada paso
    let resumen = {
        filas_originales: $total
        descartadas_no_estandar: ($total - ($estandar | length))
        descartadas_no_clasificatorias: (($estandar | length) - ($clasificatorias | length))
        descartadas_faltantes: (($clasificatorias | length) - ($completas | length))
        eco_vacio: $eco_vacio
        resultado_pgn_asterisco: ($con_asterisco | length)
        discrepancias_pgn: ($discrepancias | length)
        detalle_discrepancias: $discrepancias
        descartadas_duplicadas: (($con_previo | length) - ($unicas | length))
        descartadas_sin_rating_previo: (($unicas | length) - ($finales | length))
        filas_finales: ($tabla | length)
        archivo_salida: "data/partidas_limpias.csv"
    }

    $resumen | to json | save -f data/resumen_limpieza.json

    print "LIMPIEZA COMPLETADA"
    $resumen | reject detalle_discrepancias
}

# 2.4 Modelación
const MODELO_DIR = "data/modelo"
const PROP_ENTRENAMIENTO = 0.7
const ESCALA_D = 100
const CLIP = 1e-15
const MODALIDAD_BASE = "rapid"

# Puntaje del motor a probabilidad
def sigmoide [z] {
    1 / (1 + ((0 - $z) | math exp))
}

# Probabilidad de Elo para una diferencia de rating d
def prob-elo [d] {
    1 / (1 + (10 ** ((0 - $d) / 400)))
}

# Exactitud con umbral 0,5
def exactitud [y: list, p: list] {
    let aciertos = ($y | zip $p | where {|par| ($par.1 >= 0.5) == ($par.0 == 1) } | length)
    $aciertos / ($y | length)
}

# Pérdida logarítmica con probabilidades acotadas a [CLIP, 1 - CLIP]
def log-loss [y: list, p: list] {
    $y | zip $p | each {|par|
        let q = ([([$par.1 $CLIP] | math max) (1 - $CLIP)] | math min)
        if $par.0 == 1 { 0 - ($q | math ln) } else { 0 - ((1 - $q) | math ln) }
    } | math avg
}

# Fila en formato vw: etiqueta (1 o -1) y rasgos d, blancas y modalidad (rapid es la base)
def linea-vw [p] {
    let etiqueta = if $p.y == 1 { "1" } else { "-1" }
    let rasgos = (
        [$"d:($p.d / $ESCALA_D)"]
        | append (if $p.color == "blancas" { ["blancas"] } else { [] })
        | append (if $p.modalidad != $MODALIDAD_BASE { [$p.modalidad] } else { [] })
        | str join " "
    )
    $"($etiqueta) |p ($rasgos)"
}

# Peso de un rasgo en la salida --invert_hash de vw (0 si no aparece)
def peso-vw [pesos, nombre: string] {
    let fila = ($pesos | where nombre == $nombre)
    if ($fila | is-empty) { 0.0 } else { $fila.0.peso | into float }
}

# Ajusta la logística con vw y la compara con la proporción constante y con Elo
export def "ch model" [
    --passes: int = 500   # Pasadas de vw; con menos de 500 los coeficientes aún no se estabilizan
] {
    let archivo = "data/partidas_limpias.csv"
    if not ($archivo | path exists) {
        error make {msg: "Falta data/partidas_limpias.csv; ejecute ch clean primero."}
    }
    mkdir $MODELO_DIR

    # Variables: victoria (el empate cuenta como 0), d, color y modalidad
    let partidas = (
        open $archivo
        | insert y {|p| if $p.resultado == "victoria" { 1 } else { 0 } }
        | insert d {|p| $p.rating_previo - $p.rating_rival }
        | sort-by fecha_fin
    )

    # Partición cronológica: 70 % más antiguo para entrenar, 30 % más reciente para evaluar
    let n_train = (($partidas | length) * $PROP_ENTRENAMIENTO | math floor)
    let train = ($partidas | first $n_train)
    let test = ($partidas | skip $n_train)

    # Tablas para el motor, preparadas en Nushell
    let f_train = $"($MODELO_DIR)/entrenamiento.vw"
    let f_test = $"($MODELO_DIR)/prueba.vw"
    let f_modelo = $"($MODELO_DIR)/modelo.vw"
    let f_pesos = $"($MODELO_DIR)/pesos.txt"
    let f_pred = $"($MODELO_DIR)/puntajes_prueba.txt"
    $train | each {|p| linea-vw $p } | str join "\n" | save -f $f_train
    $test | each {|p| linea-vw $p } | str join "\n" | save -f $f_test

    # Motor externo: solo ajuste y puntajes
    ^vw -d $f_train -f $f_modelo --loss_function logistic --passes $passes -c -k --holdout_off --random_seed 42 --quiet
    ^vw -t -d $f_train -i $f_modelo --invert_hash $f_pesos --quiet
    ^vw -t -d $f_test -i $f_modelo -p $f_pred --quiet
    let version_vw = (^vw --version | str trim)

    # Coeficientes del modelo
    let pesos = (open $f_pesos | lines | parse --regex '^(?<nombre>[^:]+):(?<hash>\d+):(?<peso>\S+)$')
    let modalidades = ($train | get modalidad | uniq | where $it != $MODALIDAD_BASE | sort)
    let coeficientes = {
        motor: $"vw ($version_vw)"
        escala_d: $ESCALA_D
        modalidad_base: $MODALIDAD_BASE
        constante: (peso-vw $pesos "Constant")
        d: (peso-vw $pesos "p^d")
        blancas: (peso-vw $pesos "p^blancas")
        modalidades: ($modalidades | each {|m| {modalidad: $m, peso: (peso-vw $pesos $"p^($m)")} } | transpose -r -d)
        n_entrenamiento: ($train | length)
        n_prueba: ($test | length)
        ultima_fecha_entrenamiento: ($train | last | get fecha_fin)
    }
    $coeficientes | to json | save -f $"($MODELO_DIR)/coeficientes.json"

    # Probabilidades en Nushell
    let y_test = ($test | get y)
    let p_constante = ($train | get y | math avg)
    let probs_constante = ($test | each { $p_constante })
    let probs_elo = ($test | each {|p| prob-elo $p.d })
    let probs_logistica = (open $f_pred | lines | each {|l| sigmoide ($l | split row " " | first | into float) })

    let comparacion = [
        {modelo: "constante", exactitud: (exactitud $y_test $probs_constante), log_loss: (log-loss $y_test $probs_constante)}
        {modelo: "elo", exactitud: (exactitud $y_test $probs_elo), log_loss: (log-loss $y_test $probs_elo)}
        {modelo: "logistica", exactitud: (exactitud $y_test $probs_logistica), log_loss: (log-loss $y_test $probs_logistica)}
    ]

    # Sesgo de rating_rival: cuánto cambia el rating del jugador en una partida
    let f_crudas = "data/partidas_crudas.csv"
    let sesgo = if ($f_crudas | path exists) {
        let posteriores = (
            open $f_crudas
            | insert clave {|p| $"($p.url)|($p.jugador)" }
            | select clave rating_propio
        )
        $partidas
        | insert clave {|p| $"($p.url)|($p.jugador)" }
        | join $posteriores clave
        | each {|p| $p.rating_propio - $p.rating_previo | math abs }
        | math avg
    } else {
        print -e "Aviso: falta data/partidas_crudas.csv; no se calcula el sesgo de rating_rival."
        null
    }

    # Color: proporción de victorias con blancas y negras (intervalo aproximado del 95 %)
    let color = (
        ["blancas" "negras"] | each {|c|
            let y = ($partidas | where color == $c | get y)
            let p = ($y | math avg)
            let error = (1.96 * (($p * (1 - $p) / ($y | length)) | math sqrt))
            {color: $c, partidas: ($y | length), pct_victorias: ($p * 100), margen_95: ($error * 100)}
        }
    )

    let metricas = {
        comparacion: $comparacion
        proporcion_victorias_entrenamiento: $p_constante
        sesgo_rating_rival: $sesgo
        promedio_abs_d: ($partidas | get d | math abs | math avg)
        color: $color
    }
    $metricas | to json | save -f $"($MODELO_DIR)/metricas.json"

    # Comandos del motor, para el repositorio
    [
        $"# Motor: vw ($version_vw)"
        $"vw -d ($f_train) -f ($f_modelo) --loss_function logistic --passes ($passes) -c -k --holdout_off --random_seed 42 --quiet"
        $"vw -t -d ($f_train) -i ($f_modelo) --invert_hash ($f_pesos) --quiet"
        $"vw -t -d ($f_test) -i ($f_modelo) -p ($f_pred) --quiet"
    ] | str join "\n" | save -f motor/comandos_vw.txt

    print $"Entrenamiento: ($train | length) partidas \(hasta ($coeficientes.ultima_fecha_entrenamiento)\); prueba: ($test | length)"
    print ($comparacion | table)
    print ($coeficientes | reject motor n_entrenamiento n_prueba ultima_fecha_entrenamiento | table -e)
    print $"Sesgo de rating_rival \(promedio |rating posterior - rating_previo|\): ($sesgo)"
    print ($color | table)
    $metricas
}

# 3. Comandos avanzados
# Probabilidad de victoria según el modelo del pipeline, para una diferencia d y una modalidad.
# Como el color no se conoce antes del duelo, se promedia jugar con blancas y con negras.
def prob-modelo [coef, d, modalidad: string] {
    let peso_modalidad = ($coef.modalidades | get -o $modalidad | default 0.0)
    let z = ($coef.constante + $coef.d * $d / $coef.escala_d + $peso_modalidad)
    ((sigmoide ($z + $coef.blancas)) + (sigmoide $z)) / 2
}

# Rating actual de un jugador en una modalidad (con ch stats)
def rating-actual [usuario: string, modalidad: string] {
    let fila = (ch stats $usuario -m $modalidad)
    if $fila == null {
        error make {msg: $"No se pudieron obtener las estadísticas de ($usuario)."}
    }
    if ($fila | is-empty) or ($fila.0.rating_actual == null) {
        error make {msg: $"($usuario) no tiene rating en ($modalidad)."}
    }
    $fila.0.rating_actual
}

# Compara dos jugadores con Elo y con el modelo del pipeline
export def "ch duelo" [
    usuario1: string
    usuario2: string
    --modo (-m): string = "rapid"   # Modalidad: rapid, blitz, bullet o daily
] {
    let f_coef = $"($MODELO_DIR)/coeficientes.json"
    if not ($f_coef | path exists) {
        error make {msg: $"Falta ($f_coef); ejecute ch model primero."}
    }
    let coef = (open $f_coef)
    let modalidad = ($modo | str replace "chess_" "")
    if $modalidad != $coef.modalidad_base and $modalidad not-in ($coef.modalidades | columns) {
        print -e $"Aviso: el modelo no tiene partidas de ($modalidad); se usa la modalidad base \(($coef.modalidad_base)\)."
    }

    # Rating actual de cada jugador en la modalidad
    let jugadores = [
        {usuario: $usuario1, rating: (rating-actual $usuario1 $modalidad)}
        {usuario: $usuario2, rating: (rating-actual $usuario2 $modalidad)}
    ]

    let d = ($jugadores.0.rating - $jugadores.1.rating)
    let tabla = [
        {usuario: $jugadores.0.usuario, rating: $jugadores.0.rating, prob_elo: (prob-elo $d), prob_modelo: (prob-modelo $coef $d $modalidad)}
        {usuario: $jugadores.1.usuario, rating: $jugadores.1.rating, prob_elo: (prob-elo (0 - $d)), prob_modelo: (prob-modelo $coef (0 - $d) $modalidad)}
    ]

    # Dónde difieren: Elo y el modelo para distintas diferencias de rating
    let comparacion = ([-200 -100 -50 -25 0 25 50 100 200] | each {|x|
        let e = (prob-elo $x)
        let m = (prob-modelo $coef $x $modalidad)
        {d: $x, prob_elo: ($e | math round -p 3), prob_modelo: ($m | math round -p 3), diferencia: ($m - $e | math round -p 3)}
    })

    print $"Modalidad: ($modalidad); d = ($d)"
    print ($tabla | table)
    print "Elo y modelo según la diferencia de rating (jugador 1 menos jugador 2):"
    print ($comparacion | table)
    # Pendiente de Elo en la escala logística: ln(10)/400 por punto de rating
    let pendiente_elo = ((10 | math ln) / 400 * $coef.escala_d)
    print $"Pendiente de d por cada ($coef.escala_d) puntos: modelo ($coef.d | math round -p 2), Elo ($pendiente_elo | math round -p 2) \(el modelo es ($coef.d / $pendiente_elo | math round -p 1) veces Elo\)."
    {modalidad: $modalidad, d: $d, jugadores: $tabla, comparacion: $comparacion}
}

# 2. Pipeline completo
# Ejecuta las etapas en orden: obtención, depuración, exploración y modelación
export def "ch pipeline" [
    --pais: string = "CL"   # Fuente de jugadores
    --semilla: int = 42     # Semilla del orden de la lista del país
    --passes: int = 500     # Pasadas de vw
    --sin-descarga          # Reutiliza data/raw/ (no vuelve a ejecutar ch scout)
] {
    print "== 1/4 Obtención (ch scout)"
    let obtencion = if $sin_descarga {
        let resumen = $"($RAW_DIR)/resumen_scout.json"
        if not ($resumen | path exists) {
            error make {msg: "No hay una obtención previa en data/raw/; ejecute ch pipeline sin --sin-descarga."}
        }
        print $"Se reutiliza la obtención guardada en ($resumen)."
        open $resumen
    } else {
        ch scout --pais $pais --semilla $semilla
    }
    print "== 2/4 Depuración (ch clean)"
    let depuracion = (ch clean)
    print "== 3/4 Exploración (ch explore)"
    # ch explore (Juan Pablo): se agrega aquí cuando esté en ch.nu
    print "== 4/4 Modelación (ch model)"
    let modelacion = (ch model --passes $passes)
    {obtencion: $obtencion, depuracion: $depuracion, modelacion: $modelacion}
}

# ==========================================
# JUAN PABLO - COMANDO CH EXPLORE
# Exploracion de partidas de Chess.com
# ==========================================

export def "ch explore" [] {

    let archivo = "data/partidas_limpias.csv"

    if not ($archivo | path exists) {
        error make {msg: "No existe el archivo de partidas limpias. Ejecute ch clean primero."}
    }

    let partidas = (open $archivo)

    print "=== EXPLORACION DE PARTIDAS ==="
    print $"Total de partidas: ($partidas | length)"

    # Porcentaje de victorias por color
    let por_color = (
        $partidas
        | group-by color
        | transpose color partidas
        | each {|fila|
            let total = ($fila.partidas | length)
            let victorias = ($fila.partidas | where resultado == "victoria" | length)

            {
                color: $fila.color
                partidas: $total
                victorias: $victorias
                porcentaje_victorias: ($victorias * 100 / $total | math round --precision 2)
            }
        }
    )

    print "=== VICTORIAS POR COLOR ==="
    print ($por_color | table)

    # Porcentaje de victorias por modalidad
    let por_modalidad = (
        $partidas
        | group-by modalidad
        | transpose modalidad partidas
        | each {|fila|
            let total = ($fila.partidas | length)
            let victorias = ($fila.partidas | where resultado == "victoria" | length)

            {
                modalidad: $fila.modalidad
                partidas: $total
                victorias: $victorias
                porcentaje_victorias: ($victorias * 100 / $total | math round --precision 2)
            }
        }
        | sort-by modalidad
    )

    print "=== VICTORIAS POR MODALIDAD ==="
    print ($por_modalidad | table)

    # Porcentaje de victorias por diferencia de rating
    let por_rating = (
        $partidas
        | insert d {|p| $p.rating_previo - $p.rating_rival }
        | insert tramo {|p|
            if $p.d < -200 {
                "Menor a -200"
            } else if $p.d < -100 {
                "-200 a -101"
            } else if $p.d < 0 {
                "-100 a -1"
            } else if $p.d == 0 {
                "Igual rating"
            } else if $p.d <= 100 {
                "1 a 100"
            } else if $p.d <= 200 {
                "101 a 200"
            } else {
                "Mayor a 200"
            }
        }
        | group-by tramo
        | transpose tramo partidas
        | each {|fila|
            let total = ($fila.partidas | length)
            let victorias = ($fila.partidas | where resultado == "victoria" | length)

            {
                tramo: $fila.tramo
                partidas: $total
                victorias: $victorias
                porcentaje_victorias: ($victorias * 100 / $total | math round --precision 2)
            }
        }
    )

    print "=== VICTORIAS POR DIFERENCIA DE RATING ==="
    print ($por_rating | table)

    # Top 10 de aperturas ECO mas frecuentes
    let top_eco = (
        $partidas
        | where eco != ""
        | group-by eco
        | transpose eco partidas
        | each {|fila|
            {
                eco: $fila.eco
                partidas: ($fila.partidas | length)
            }
        }
        | sort-by partidas --reverse
        | first 10
    )

    print "=== TOP 10 APERTURAS ECO ==="
    print ($top_eco | table)

    # Porcentaje de victorias por familia ECO
    let por_familia = (
        $partidas
        | where familia_eco != ""
        | group-by familia_eco
        | transpose familia_eco partidas
        | each {|fila|
            let total = ($fila.partidas | length)
            let victorias = ($fila.partidas | where resultado == "victoria" | length)

            {
                familia_eco: $fila.familia_eco
                partidas: $total
                victorias: $victorias
                porcentaje_victorias: ($victorias * 100 / $total | math round --precision 2)
            }
        }
        | sort-by familia_eco
    )

    print "=== VICTORIAS POR FAMILIA ECO ==="
    print ($por_familia | table)

    # Cantidad de partidas por mes
    let por_mes = (
        $partidas
        | insert mes {|p| $p.fecha_fin | str substring 0..6 }
        | group-by mes
        | transpose mes partidas
        | each {|fila|
            {
                mes: $fila.mes
                partidas: ($fila.partidas | length)
            }
        }
        | sort-by mes
    )

    print "=== PARTIDAS POR MES ==="
    print ($por_mes | table)

    # Cantidad de partidas por jugador
    let por_jugador = (
        $partidas
        | group-by jugador
        | transpose jugador partidas
        | each {|fila|
            {
                jugador: $fila.jugador
                partidas: ($fila.partidas | length)
            }
        }
        | sort-by partidas --reverse
    )

    print "=== PARTIDAS POR JUGADOR ==="
    print ($por_jugador | table)
}

