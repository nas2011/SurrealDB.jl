module SurrealDB

begin
    using HTTP, JSON3, DataFrames, Base64, UUIDs, Random
    using HTTP.WebSockets: send, receive
end


include("structs.jl")
include("core.jl")
include("websockets.jl")

function rawws(url,headers =[])
    headers = [
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => base64encode(rand(Random.RandomDevice(), UInt8, 16)),
        "Sec-WebSocket-Version" => "13",
        "Sec-Websocket-Protocol" => "rpc",
        headers...
    ]
    r = HTTP.openraw("GET",url,headers)[1]

    ws = WebSockets.WebSocket(r)
    return ws
end

export 
    SurrealConnection,
    signin,
    use,
    select,
    query,
    execute,
    rawws
end
