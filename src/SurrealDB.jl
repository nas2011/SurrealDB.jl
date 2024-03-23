module SurrealDB

begin
    using HTTP, JSON3, DataFrames, Base64, UUIDs, Random
    using HTTP.WebSockets: send, receive
    include("structs.jl")
end


include("structs.jl")
include("core.jl")

export 
    SurrealConnection,
    signin,
    use,
    select,
    query,
    execute,
    rawws
end
