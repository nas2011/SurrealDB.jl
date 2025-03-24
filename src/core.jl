begin
    using HTTP, JSON3, DataFrames, Base64, UUIDs, Random, DBInterface, JSONTables
    using HTTP.WebSockets: send, receive
end


"""Implement DBInterface.execute. Does not return an explicit cursor, rather, returns rows at this time.
***Note*** If your query return more than once, the default behavior is to return only the last return."""
function DBInterface.execute(conn::SurrealConnection,sql::String)
    res = query(conn,sql)
    results = res.result[end].result
    return jsontable(results)
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



function define(index::Index)
    """DEFINE INDEX $(index.name) ON TABLE $(index.table.name) COLUMNS $(index.columns.name) $(index.type);"""
end

function define(fields::Vector{Field})
    mapreduce(*,fields) do x
        assertVal = x.assertion == "" ? "" : "ASSERT $(x.assertion)"
        valString = x.value == "" ? "" : "VALUE $(x.value)"
        defaultString = x.defaultVal == "" ? "DEFAULT NONE" : "DEFAULT $(x.defaultVal)"
        flexVal = occursin("object",x.type) ? "FLEXIBLE" : ""
        """DEFINE FIELD $(x.name) ON TABLE %%FUTURETABLE%% $flexVal TYPE $(x.type)\n
        \t$defaultString
        \t$assertVal\n
        \t$valString;\n
        """
    end
end

function define(permissions::Vector{Permission})
    perms = mapreduce(*,permissions) do x
        """\t FOR $(x.type)\n
            \t\t $(x.rule)
        """
    end

    return "PERMISSIONS\n $perms"
end



function define(table::Table)
    fieldTemplate = define(table.fields)
    fields = replace(fieldTemplate,"%%FUTURETABLE%%"=>(table.name))
    permissions = define(table.permissions)
    """
    DEFINE TABLE $(table.name) $(table.type)\n 
    \t$permissions;
    $fields    
    """
end

