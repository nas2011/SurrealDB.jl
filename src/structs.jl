function rawws(url,headers =[])
    headers = [
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => base64encode(rand(Random.RandomDevice(), UInt8, 16)),
        "Sec-WebSocket-Version" => "13",
        headers...
    ]
    r = HTTP.openraw("GET",url,headers)[1]

    ws = WebSockets.WebSocket(r)
    return ws
end

@kwdef mutable struct SurrealConnection
    url::String = "ws://localhost:8000/rpc"
    user::String = "root"
    pass::String = "root"
    ns::String = ""
    db::String = ""
    type::String
    connected::Bool = false
    ws::Union{HTTP.WebSockets.WebSocket,Nothing}
    SurrealConnection(url, user, pass; ns="", db="") = (
        x = new(url, user, pass, ns, db);
        x.ws = occursin("ws:", x.url) ? rawws(x.url) : nothing;
        x.type = occursin("ws:", x.url) ? "websocket" : "HTTP";
        x.connected = x.type == "websocket" ? HTTP.isopen(x.ws.io) : false;
        return x
    )
end


mutable struct SurrealWSConnection
    url::String
    user::String
    pass::String
    db::String
    ns::String
    connected::Bool
    ws::HTTP.WebSockets.WebSocket
    SurrealWSConnection(url,user,pass) = new(url,user,pass,"","",true,rawws(url))
    SurrealWSConnection(user,pass) = new("ws://localhost:8000/rpc",user,pass,"","",true,rawws(url))
    SurrealWSConnection(user,pass;db="",ns="") = new("ws://localhost:8000/rpc",user,pass,db,ns,true,rawws("ws://localhost:8000/rpc"))
end


mutable struct SurrealHTTPConnection
    url::String
    user::String
    pass::String
    db::String
    ns::String
    SurrealHTTPConnection(user,pass) = new("http://localhost:8000",user,pass,"","")
    SurrealHTTPConnection(url,user,pass) = new(url,user,pass,"","")
    SurrealHTTPConnection(user,pass;db="",ns="") = new("http://localhost:8000",user,pass,db,ns)
end