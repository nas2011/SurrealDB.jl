using DBInterface

@kwdef struct SurrealConnection
    url::String = "ws://localhost:8000/rpc"
    user::String = "root"
    pass::String = "root"
    ns::String = "test"
    db::String = "test"
    type::String = ""
    connected::Bool = false
    ws::Union{HTTP.WebSockets.WebSocket,Nothing}=nothing

    SurrealConnection(url, user, pass;ns=ns,db=db) = (
        ws = occursin("ws:", url) ? rawws(url) : nothing;
        type = occursin("ws:", url) ? "websocket" : "HTTP";
        connected = type == "websocket" ? HTTP.isopen(ws.io) : false;
        ns = ns;
        db = db;
        return new(url,user,pass,ns,db,type,connected,ws)
    )
end

DBInterface.connect(::Type{SurrealConnection},args...;kw...) = SurrealConnection(args...;kw...)


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