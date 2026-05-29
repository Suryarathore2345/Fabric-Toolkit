# ============================================================
#  BLOCK 1 — CREATE TABLE via pyodbc
#  Change the parameters below as needed
# ============================================================

import pyodbc
import struct

# ── Parameters ──────────────────────────────────────────────
SERVER   = ""  #SQL ENDPOINT
PORT     = "1433"
DATABASE = ""  #Database Name
SCHEMA   = ""  # Schema Name 
TABLE    = "" # Table Name                        


#Example - > 

CREATE_TABLE_SQL = f"""
CREATE TABLE [{SCHEMA}].[{TABLE}] (
    ProductID     INT            NOT NULL,
    ProductName   VARCHAR(100),
    Category      VARCHAR(50),
    Quantity      INT,
    UnitPrice     DECIMAL(10,2),
    SupplierName  VARCHAR(100),
    LastUpdated   DATE
)
"""
# ── End Parameters ──────────────────────────────────────────

# Auth + Connection
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

# Execute
with pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct}) as conn:
    cursor = conn.cursor()
    cursor.execute(CREATE_TABLE_SQL)
    conn.commit()
    print(f"Table [{SCHEMA}].[{TABLE}] created successfully in [{DATABASE}]")
