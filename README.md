# SurrealDB

## A Basic Client for Working With SurrealDB in Julia

This is a basic client library. It allows you to define a SurrealDB connection to a running
instance of SurrealDB and execute SurrealQL statements on that instance using the SurrealDB
REST API or websocket text protocol. 

I intend to build this out with more full fledged features over time.

Example WebSocket usage:

```julia

julia> wsconn = SurrealConnection("ws://localhost:8000/rpc","root","root")
SurrealConnection("ws://localhost:8000/rpc", "root", "root", "", "", "websocket", true, HTTP.WebSockets.WebSocket(UUID("b41ea096-fe11-46be-8b9c-acc84d8b7b80"), 🔗    0s localhost:8000:31807 
Base.Libc.WindowsRawSocket(0x00000000000005fc), HTTP.Messages.Request:
"""
 / HTTP/1.1

""", HTTP.Messages.Response:
"""
HTTP/1.1 0 Unknown Code

""", 9223372036854775807, 1024, true, UInt8[], UInt8[], false, false))

julia> signin(wsconn)
{       
    "id": "b41ea096-fe11-46be-8b9c-acc84d8b7b80",
    "result": null
}

julia> wsconn.ns = "test"; wsconn.db = "test"

julia> use(wsconn)
{
    "id": "b41ea096-fe11-46be-8b9c-acc84d8b7b80",
    "result": null
}

julia> query(wsconn,"select * from person limit 2") |> JSON3.pretty
{
    "id": "b41ea096-fe11-46be-8b9c-acc84d8b7b80",
    "result": [
        {
            "time": "644.6µs",
            "status": "OK",
            "result": [
                {
                    "address": {
                        "address_line_1": "767 Culkeeran",
                        "address_line_2": null,
                        "city": "Matlock",
                        "coordinates": [
                            "-51.195338",
                            "114.885025"
                        ],
                        "country": "England",
                        "post_code": "MU1P 0XX"
                    },
                    "company_name": null,
                    "email": "said1813@example.com",
                    "first_name": "Caprice",
                    "id": "person:00e1nc508h9f7v63x72o",
                    "last_name": "Huber",
                    "name": "Caprice Huber",
                    "phone": "0115 262 2984"
                },
                {
                    "address": {
                        "address_line_1": "1088 Hazeldene",
                        "address_line_2": null,
                        "city": "Newport Pagnell",
                        "coordinates": [
                            "71.497459",
                            "87.715959"
                        ],
                        "country": "Northern Ireland",
                        "post_code": "YX6S 5VO"
                    },
                    "company_name": null,
                    "email": "law1800@yandex.com",
                    "first_name": "Serina",
                    "id": "person:00g8os512h0k7l19p05g",
                    "last_name": "Mitchell",
                    "name": "Serina Mitchell",
                    "phone": "055 5165 3957"
                }
            ]
        }
    ]
}

julia> close(wsconn.ws)
```

Example HTTP usage:

```julia

julia> conn = julia> SurrealConnection("http://localhost:8000", "root", "root",ns = "test",db = "test")
SurrealConnection("http://localhost:8000", "root", "root", "test", "test", "HTTP", false, nothing)

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
```
