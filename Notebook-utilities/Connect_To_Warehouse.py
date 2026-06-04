# ============================================================
#  get_warehouse_conn() – Returns an authenticated pyodbc connection
#  using the notebook's Managed Identity token
# ============================================================

import struct as _struct
import pyodbc

SCHEMA   = "Logs"

WAREHOUSE_SERVER   = ("")     # SQL Endpoint
WAREHOUSE          = ""       # Warehouse Name 

def get_warehouse_conn():
    token        = notebookutils.credentials.getToken("https://database.windows.net/")
    token_bytes  = token.encode("utf-16-le")
    token_struct = _struct.pack(f'<I{len(token_bytes)}s', len(token_bytes), token_bytes)

    SQL_COPT_SS_ACCESS_TOKEN = 1256

    conn_str = (
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server={WAREHOUSE_SERVER};"
        f"Database={WAREHOUSE};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
    )

    return pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct})


print(" get_warehouse_conn() helper defined.")