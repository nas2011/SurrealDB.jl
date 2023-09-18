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
    type::String = ""
    connected::Bool = false
    ws::Union{HTTP.WebSockets.WebSocket,Nothing}=nothing
    SurrealConnection(url,user,pass,ns,db,type,connected,ws)= (
        x = new(url,user,pass,ns,db,type,connected,ws);
        x.ws = occursin("ws:", x.url) ? rawws(x.url) : nothing;
        x.type = occursin("ws:", x.url) ? "websocket" : "HTTP";
        x.connected = x.type == "websocket" ? HTTP.isopen(x.ws.io) : false;
        return x
    )
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

mutable struct Field
    name::String
    type::String
    assertion::String
    value::String
    defaultVal::String
end

mutable struct Permission
    type::String
    rule::String

    Permission(type,rule) = 
    begin
        types = ["select","create","update","delete"] 
        if lowercase(type) in types
            new(lowercase(type),rule)
        else
            error("Permission type must be one of $types")
        end        
    end
end

mutable struct Table
    name::String
    fields::Vector{Field}
    type::String
    permissions::Vector{Permission}
    
    Table(name,fields,type,permissions) = 
    begin
        types = ["schemafull", "schemaless"] 
        if lowercase(type) in types
            new(lowercase(name),fields,lowercase(type),permissions)
        else
            error("Table type must be one of $types")
        end        
    end
end

struct Namespace
    name::String
end

struct Database
    name::String
end

mutable struct User
    namespace::Namespace
    database::Database
    user::String
    pass::String
    role::String
    User(namespace,database,user,pass,role) = 
    begin
        roles = ["owner", "editor", "viewer"]
        if lowercase(role) in roles
            new(namespace,database,user,pass,uppercase(role))
        else
            error("Role must be one of $roles")
        end
    end
end

mutable struct Index
    name::String
    table::Table
    columns::Field
    type::String
    Index(name,table,columns,type) = 
    begin
        types = ["unique","search analyzer", ""]
        if lowercase(type) in types
            new(name,table,columns,uppercase(type))
        else
            error("type must be one of $types")
        end
    end
end