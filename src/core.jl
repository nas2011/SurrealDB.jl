using HTTP, JSON3, DataFrames, Base64
include("structs.jl")


function execute(conn::SurrealDBConnection,query::String)
    ep = string(conn.url,"/sql")
    header = [
        "Authorization" => string("Basic ", base64encode("$(conn.user):$(conn.password)")),
        "Accept" => "application/json",
        "NS" => conn.namespace,
        "DB" => conn.database,
    ]
    HTTP.request("POST",ep,headers = header, body=query) |>
    y-> JSON3.read(y.body|>String)
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