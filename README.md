# SurrealDB

## A Basic Client for Working With SurrealDB in Julia

This is a basic client library. It allows you to define a SurrealDB connection to a running
instance of SurrealDB and execute SurrealQL statements on that instance using the SurrealDB
REST API or websocket text protocol. 

I intend to build this out with more full fledged features over time.

Example usage:

```julia

conn = SurrealConnection(
    "ws://localhost:8000/rpc",
    "test2",
    "pw1234",
    ns ="test",
    db = "test",
)


signin(conn)

# JSON3.Object{Base.CodeUnits{UInt8, String}, Vector{UInt64}} with 2 entries:
#  :id     => "2c2c2e7c-8e25-4991-91fc-75bc7b13827f"
#  :result => "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzUxMiJ9.eyJpYXQiOjE3NDI2NjAxMjEsIm5iZiI6MTc0MjY2MDEyMSwiZXhwIjoxNzQyNj…

use(conn)

# JSON3.Object{Base.CodeUnits{UInt8, String}, Vector{UInt64}} with 2 entries:
#  :id     => "2c2c2e7c-8e25-4991-91fc-75bc7b13827f"
#  :result => nothing


query(conn,"info for db").result

# 1-element JSON3.Array{JSON3.Object, Base.CodeUnits{UInt8, String}, SubArray{UInt64, 1, Vector{UInt64}, Tuple{UnitRange{Int64}}, true}}:
#  {
#    "result": {
#                  "accesses": {},
#                 "analyzers": {},
#                      "apis": {},
#                   "configs": {},
#                 "functions": {},
#                    "models": {},
#                    "params": {},
#                    "tables": {},
#                     "users": {}
#              },
#    "status": "OK",
#      "time": "750.7µs"
# }
```
