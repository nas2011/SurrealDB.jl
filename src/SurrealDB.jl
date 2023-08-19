module SurrealDB

include("structs.jl")
include("core.jl")

export 
    SurrealConnection,
    signin,
    use,
    select,
    query,
    execute,
    todf
end
