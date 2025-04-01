module SurrealDB

begin
    using HTTP, JSON3, DataFrames, Base64, UUIDs, Random, TOML, DBInterface, JSONTables
    using HTTP.WebSockets: send, receive
end


include("structs.jl")
include("core.jl")
include("websockets.jl")
include("downloader.jl")
include("startSurreal.jl")

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

global surrealExeLoc = joinpath(pwd(),"surreal","surreal")
global config = TOML.parsefile("../config.toml")

export 
    SurrealConnection,
    signin,
    use,
    select,
    query,
    rawws,
    DBInterface,
    #downloader
    getSurreal,
    #Start
    startSurreal,
    closeSurreal
end


