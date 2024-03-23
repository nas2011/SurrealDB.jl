module SurrealDB

using HTTP, JSON3

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
