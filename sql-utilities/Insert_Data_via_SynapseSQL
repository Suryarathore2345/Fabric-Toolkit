# ============================================================
#  INSERT DATA via synapsesql (Spark)
#  Change the parameters below as needed
# ============================================================

from pyspark.sql.types import (
    StructType, StructField,
    IntegerType, StringType, DecimalType, DateType
)
from decimal import Decimal
import datetime

# ── Parameters ──────────────────────────────────────────────
WAREHOUSE_NAME = ""          # ← Fabric Warehouse name
SCHEMA         = ""          # ← Target schema
TABLE          = ""          # ← Target table name
WRITE_MODE     = ""          # ← "append" or "overwrite"

# ── Define Schema ────────────────────────────────────────────
SCHEMA_DEF = StructType([
    StructField("ProductID",    IntegerType(),     False),
    StructField("ProductName",  StringType(),      True),
    StructField("Category",     StringType(),      True),
    StructField("Quantity",     IntegerType(),     True),
    StructField("UnitPrice",    DecimalType(10,2), True),
    StructField("SupplierName", StringType(),      True),
    StructField("LastUpdated",  DateType(),        True),
])

#Example 
# ── Define Rows ──────────────────────────────────────────────
ROWS = [
    (1, "Widget A",    "Electronics", 100, Decimal("29.99"), "Supplier Co",      datetime.date(2026, 5, 29)),
    (2, "Gadget B",    "Tools",        50, Decimal("14.50"), "Parts Ltd",        datetime.date(2026, 5, 29)),
    (3, "Component C", "Electronics", 200, Decimal("99.99"), "Tech Supplies",   datetime.date(2026, 5, 29)),
    (4, "Part D",      "Hardware",     75, Decimal("49.00"), "HW Distributors", datetime.date(2026, 5, 29)),
    (5, "Module E",    "Software",     30, Decimal("9.99"),  "Soft Corp",        datetime.date(2026, 5, 29)),
]
# ── End Parameters ──────────────────────────────────────────

# Build DataFrame
df = spark.createDataFrame(ROWS, schema=SCHEMA_DEF)

# Write to Warehouse
WAREHOUSE_FULL_NAME = f"{WAREHOUSE_NAME}.{SCHEMA}.{TABLE}"

df.write \
  .mode(WRITE_MODE) \
  .synapsesql(WAREHOUSE_FULL_NAME)

print(f"✅ {len(ROWS)} rows written to [{WAREHOUSE_FULL_NAME}] (mode: {WRITE_MODE})")
