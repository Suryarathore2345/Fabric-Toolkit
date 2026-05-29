# ============================================================
#  INSERT DATA via pyodbc
#  Change the parameters below as needed
# ============================================================

import pyodbc
import struct

# ── Parameters ──────────────────────────────────────────────
SERVER   = ""
PORT     = "1433"
DATABASE = ""
SCHEMA   = ""
TABLE    = ""                        # ← Change table name here

# ── Column Names (must match table) ─────────────────────────
COLUMNS = [
    "ProductID",
    "ProductName",
    "Category",
    "Quantity",
    "UnitPrice",
    "SupplierName",
    "LastUpdated",
]

# ── Data Rows ────────────────────────────────────────────────
ROWS = [
    (1, "Widget A",     "Electronics", 100, 29.99, "Supplier Co",       "2026-05-29"),
    (2, "Gadget B",     "Tools",        50, 14.50, "Parts Ltd",         "2026-05-29"),
    (3, "Component C",  "Electronics", 200, 99.99, "Tech Supplies",     "2026-05-29"),
    (4, "Part D",       "Hardware",     75, 49.00, "HW Distributors",   "2026-05-29"),
    (5, "Module E",     "Software",     30,  9.99, "Soft Corp",         "2026-05-29"),
]
# ── End Parameters ──────────────────────────────────────────

# Auto-build INSERT SQL from COLUMNS
col_names    = ", ".join([f"[{c}]" for c in COLUMNS])
placeholders = ", ".join(["?" for _ in COLUMNS])
INSERT_SQL   = f"INSERT INTO [{SCHEMA}].[{TABLE}] ({col_names}) VALUES ({placeholders})"

print(f"INSERT SQL: {INSERT_SQL}")

# ── Auth + Connection ────────────────────────────────────────
token        = notebookutils.credentials.getToken("https://database.windows.net/")
token_bytes  = token.encode("utf-16-le")
token_struct = struct.pack(f'<I{len(token_bytes)}s', len(token_bytes), token_bytes)
SQL_COPT_SS_ACCESS_TOKEN = 1256

conn_str = (
    f"Driver={{ODBC Driver 18 for SQL Server}};"
    f"Server={SERVER},{PORT};"
    f"Database={DATABASE};"
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
)

# ── Execute ──────────────────────────────────────────────────
with pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct}) as conn:
    cursor = conn.cursor()

    # Bulk insert all rows in one call
    cursor.executemany(INSERT_SQL, ROWS)
    conn.commit()

    print(f"{len(ROWS)} rows inserted into [{SCHEMA}].[{TABLE}]")

    # ── Verify ───────────────────────────────────────────────
    cursor.execute(f"SELECT * FROM [{SCHEMA}].[{TABLE}]")
    rows = cursor.fetchall()
    print(f"\n📋 Current rows in [{TABLE}]:")
    for row in rows:
        print(row)
