using HTTP, JSON3, DataFrames, Base64
include("structs.jl")

url = "https://localhost:8080"
user = "root"
pw = "root"
db = "test"
namespace = "test"

conn = SurrealDBConnection(user,pw,database=db,namespace = namespace)
query = """SELECT * FROM person"""


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

execute(conn,query)

query = """
CREATE person SET name = "Nick";
CREATE person SET name = "Cassie", role = "bad ass";"""

execute(conn,"select * from person;") |> todf