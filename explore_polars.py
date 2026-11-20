import polars as pl

# ==========================================
# PLAYER ONE - EXPLORACION CON POLARS
# ==========================================

archivo = "data/partidas_limpias.csv"

# Leer las partidas
partidas = pl.read_csv(archivo)

print("=== EXPLORACION CON POLARS ===")
print(f"Total de partidas: {partidas.height}")

# Funcion para calcular porcentajes de victorias
def calcular_victorias(datos, columna):
    return (
        datos
        .group_by(columna)
        .agg(
            pl.len().alias("partidas"),
            (pl.col("resultado") == "victoria")
                .sum()
                .alias("victorias")
        )
        .with_columns(
            (
                pl.col("victorias") * 100
                / pl.col("partidas")
            )
            .round(2)
            .alias("porcentaje_victorias")
        )
        .sort(columna)
    )


# 1. Victorias por color
print("\n=== VICTORIAS POR COLOR ===")
print(calcular_victorias(partidas, "color"))


# 2. Victorias por modalidad
print("\n=== VICTORIAS POR MODALIDAD ===")
print(calcular_victorias(partidas, "modalidad"))


# 3. Victorias por diferencia de rating
con_rating = (
    partidas
    .with_columns(
        (
            pl.col("rating_previo").cast(pl.Int64, strict=False)
            - pl.col("rating_rival").cast(pl.Int64, strict=False)
        ).alias("d")
    )
    .filter(pl.col("d").is_not_null())
    .with_columns(
        pl.when(pl.col("d") < -200)
        .then(pl.lit("Menor a -200"))
        .when(pl.col("d") < -100)
        .then(pl.lit("-200 a -101"))
        .when(pl.col("d") < 0)
        .then(pl.lit("-100 a -1"))
        .when(pl.col("d") == 0)
        .then(pl.lit("Igual rating"))
        .when(pl.col("d") <= 100)
        .then(pl.lit("1 a 100"))
        .when(pl.col("d") <= 200)
        .then(pl.lit("101 a 200"))
        .otherwise(pl.lit("Mayor a 200"))
        .alias("tramo")
    )
)

print("\n=== VICTORIAS POR DIFERENCIA DE RATING ===")
print(calcular_victorias(con_rating, "tramo"))


# 4. Top 10 aperturas ECO
top_eco = (
    partidas
    .filter(pl.col("eco").is_not_null() & (pl.col("eco") != ""))
    .group_by("eco")
    .agg(pl.len().alias("partidas"))
    .sort("partidas", descending=True)
    .head(10)
)

print("\n=== TOP 10 APERTURAS ECO ===")
print(top_eco)


# 5. Victorias por familia ECO
print("\n=== VICTORIAS POR FAMILIA ECO ===")

con_familia = partidas.filter(
    pl.col("familia_eco").is_not_null()
    & (pl.col("familia_eco") != "")
)

print(calcular_victorias(con_familia, "familia_eco"))


# 6. Partidas por mes y jugador
por_mes = (
    partidas
    .with_columns(
        pl.col("fecha_fin")
        .cast(pl.String)
        .str.slice(0, 7)
        .alias("mes")
    )
    .group_by("mes")
    .agg(pl.len().alias("partidas"))
    .sort("mes")
)

print("\n=== PARTIDAS POR MES ===")
print(por_mes)

por_jugador = (
    partidas
    .group_by("jugador")
    .agg(pl.len().alias("partidas"))
    .sort("partidas", descending=True)
)

print("\n=== PARTIDAS POR JUGADOR ===")
print(por_jugador)
