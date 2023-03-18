module SurrealDB

include("structs.jl")
include("core.jl")

export 
    SurrealDBConnection,
    execute,
    todf

end
