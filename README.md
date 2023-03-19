# SurrealDB

## A Basic Client for Working With SurrealDB in Julia

This is a basic client library. It allows you to define a SurrealDB connection to a running
instance of SurrealDB and execute SurrealQL statements on that instance using the SurrealDB
REST API. This package also provides a convenience function `todf` to convert results of
executed queries to a `DataFrame` for further use.

I intend to build this out with more full fledged features over time.

Example usage:

```julia

julia> conn = SurrealDBConnection("root","root",database = "test", namespace = "test")
SurrealDBConnection("http://localhost:8000", "root", "root", "test", "test")

julia> query = "select * from person"
"select * from person"

julia> execute(conn,query)
1-element JSON3.Array{JSON3.Object, Base.CodeUnits{UInt8, String}, Vector{UInt64}}:
 {
     "time": "140µs",
   "status": "OK",
   "result": [
               {
                    "id": "person:4ue7j2d0g43otmsq4ilc",
                  "name": "Cassie",
                  "role": "bad ass"
               },
               {
                    "id": "person:77m8a8pwognplrhwzj7e",
                  "name": "Nick"
               }
             ]
}

julia> ans |> todf
2×3 DataFrame
 Row │ id                           name    role
     │ String                       String  String?
─────┼──────────────────────────────────────────────
   1 │ person:4ue7j2d0g43otmsq4ilc  Cassie  bad ass
   2 │ person:77m8a8pwognplrhwzj7e  Nick    missing
```
