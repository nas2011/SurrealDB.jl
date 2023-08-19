begin
    using HTTP, JSON3, DataFrames, Base64, UUIDs, Random
    using HTTP.WebSockets: send, receive
    include("structs.jl")
end





function signin(conn::SurrealConnection;root::Bool=true,sc::Union{Nothing,String}=nothing)
    additional = ""
    if !root
        scope = isnothing(sc) ? "" : "\"SC\": \"$sc\""
        ns = "\"NS\" : \"$(conn.ns)\","
        db = "\"DB\" : \"$(conn.db)\","
        additional = ns * db * scope
    end    
    id = conn.ws.id |> string
    body = """{
        "id": "$id",
        "method": "signin",
        "params": [
            {
                "user": "$(conn.user)",
                "pass": "$(conn.pass)",
                $additional
            }
        ]
    }"""

    send(conn.ws,body)
    receive(conn.ws)
end
   

function use(conn::SurrealConnection)
    id = conn.ws.id |> string
    use = """{
        "id": "$id",
        "method": "use",
        "params": [ "$(conn.ns)", "$(conn.db)" ]
    }"""
    send(conn.ws,use)
    receive(conn.ws)
end



function select(conn::SurrealConnection,param::String)
    id = conn.ws.id |> string
    body = """{
        "id": "$id",
        "method": "select",
        "params": [
           "$param"
        ]
    }"""
    send(conn.ws,body)
    receive(conn.ws)
end


function varstring(vars::Dict{String,String})
    join(["\"$k\" : \"$v\"" for (k,v) in pairs(vars)], ",\n")
end

function query(conn::SurrealWSConnection,query::String,vars::Dict{String,String}=Dict{String,String}())
    id = conn.ws.id |> string
    varstr = varstring(vars)
    body = """{
        "id": "$id",
        "method": "query",
        "params": [
            "$query",
            {
                $varstr
            }
        ]
    }"""
    send(conn.ws,body)
    receive(conn.ws)
end


function execute(conn::SurrealConnection,query::String)
    ep = string(conn.url,"/sql")
    header = [
        "Authorization" => string("Basic ", base64encode("$(conn.user):$(conn.pass)")),
        "Accept" => "application/json",
        "NS" => conn.ns,
        "DB" => conn.db,
    ]
    HTTP.request("POST",ep,headers = header, body=query).body |> String |> JSON3.read
end



function todf(result::JSON3.Array)
    if result[1].result == []
        return DataFrame()
    end
    try
        mapreduce((x,y)->vcat(x,y,cols=:union),result[1].result) do x
            DataFrame(x)
        end
    catch
        "something went wrong"
    end
end