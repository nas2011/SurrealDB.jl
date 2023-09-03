begin
    using HTTP, JSON3, DataFrames, Base64, UUIDs, Random
    using HTTP.WebSockets: send, receive
    include("structs.jl")
end

function varstring(vars::Dict{String,String})
    join(["\"$k\" : \"$v\"" for (k,v) in pairs(vars)], ",\n")
end

function sendreceive(conn::SurrealConnection,message::String)
    send(conn.ws,message)
    t = @async receive(conn.ws) |> JSON3.read
    fetch(t)
end

function buildMessage(conn::SurrealConnection,method::String;vecParams::Vector{String}=String[],objParams::Dict{String,String}=Dict{String,String}())
    id = conn.ws.id |> string
    vecParamString = length(vecParams) > 0 ?
        join(["\"$i\"" for i in vecParams], ",") * "," :
         ""
    objParamString =  length(objParams) >0 ?
        "{" * varstring(objParams) * "}" :
        ""
    """{
        "id": "$id",
        "method": "$method",
        "params": [ 
            $vecParamString
            $objParamString
         ]
    }"""
end


function signin(conn::SurrealConnection;root::Bool = true, sc::Union{String,Nothing}=nothing)
    if root
        paramDict = Dict(
            "user" => conn.user,
            "pass" => conn.pass,
        )
    else
        paramDict = Dict(
            "NS" => conn.ns,
            "DB" => conn.db,
            "user" => conn.user,
            "pass" => conn.pass,
        )
    end
    if !isnothing(sc) paramDict["SC"] = sc end
    message = buildMessage(conn,"signin";objParams = paramDict)
    sendreceive(conn,message)
end
   

function use(conn::SurrealConnection)
    message = buildMessage(conn,"use",vecParams = [conn.ns,conn.db])
    sendreceive(conn,message)
end



function select(conn::SurrealConnection,param::String)
    message = buildMessage(conn,"select",vecParams = [param])
    sendreceive(conn,message)
end




function query(conn::SurrealConnection,query::String,vars::Dict{String,String}=Dict{String,String}())
    message = buildMessage(conn,"query",vecParams = [query], objParams = vars)
    sendreceive(conn,message)
end

function info(conn::SurrealConnection)
    message = buildMessage(conn,"info")
    sendreceive(conn,message)
end

function signup(conn::SurrealConnection,sc::String)
    paramDict = Dict(
            "NS" => conn.ns,
            "DB" => conn.db,
            "user" => conn.user,
            "pass" => conn.pass,
            "SC" => sc,
        )
    message = buildMessage(conn,"signup",objParams=paramDict)
    sendreceive(conn,message)
end


function authenticate(conn::SurrealConnection,token::String)
    message = buildMessage(conn,"authenticate",vecParams = [token])
    sendreceive(conn,message)
end

function invalidate(conn::SurrealConnection)
    message = buildMessage(conn,"invalidate")
    sendreceive(conn,message)
end

function insert(conn::SurrealConnection,thing::String;data::Dict{String,String}=Dict())
    message = buildMessage(conn,"insert",vecParams=[thing],objParams=data)
    sendreceive(conn,message)
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