using DBInterface
using Tables

struct SurrealConnection <: DBInterface.Connection
    client::Surreal
end

struct SurrealStatement <: DBInterface.Statement
    conn::SurrealConnection
    sql::String
end

struct SurrealCursor <: DBInterface.Cursor
    rows::Vector{Dict{String, Any}}
    colnames::Vector{Symbol}
end

function SurrealCursor(rows::Vector{Dict{String, Any}})
    all_keys = Set{Symbol}()
    for r in rows
        for k in keys(r)
            push!(all_keys, Symbol(k))
        end
    end
    colnames = sort(collect(all_keys))
    return SurrealCursor(rows, colnames)
end

struct SurrealRow
    data::Dict{String, Any}
    cursor::SurrealCursor
end

# Connection lifecycle
function DBInterface.connect(::Type{SurrealConnection}, url::String; options...)
    client = connect(url; options...)
    return SurrealConnection(client)
end

function DBInterface.close!(conn::SurrealConnection)
    close(conn.client)
end

# Statement lifecycle
function DBInterface.prepare(conn::SurrealConnection, sql::String)
    return SurrealStatement(conn, sql)
end

function DBInterface.close!(stmt::SurrealStatement)
    nothing
end

# Helper to normalize query outputs into row dictionaries
function extract_results(query_res)
    if isnothing(query_res)
        return Dict{String, Any}[]
    end
    if query_res isa Vector && all(x -> x isa Dict && haskey(x, "status") && haskey(x, "result"), query_res)
        if isempty(query_res)
            return Dict{String, Any}[]
        end
        stmt = query_res[1]
        if stmt["status"] != "OK"
            error("Database query failed: $(stmt["result"])")
        end
        result_data = stmt["result"]
        if result_data isa Vector
            return [Dict{String, Any}(String(k) => v for (k, v) in r) for r in result_data if r isa Dict]
        elseif result_data isa Dict
            return Dict{String, Any}[Dict{String, Any}(String(k) => v for (k, v) in result_data)]
        else
            return Dict{String, Any}[]
        end
    elseif query_res isa Dict
        return Dict{String, Any}[Dict{String, Any}(String(k) => v for (k, v) in query_res)]
    elseif query_res isa Vector
        return [Dict{String, Any}(String(k) => v for (k, v) in r) for r in query_res if r isa Dict]
    else
        return Dict{String, Any}[]
    end
end

# Execute implementations
function DBInterface.execute(stmt::SurrealStatement, params::Vector)
    # Map positional parameters index 1 to $_1, index 2 to $_2, etc.
    vars = Dict{String, Any}("_" * string(i) => v for (i, v) in enumerate(params))
    
    # Rewrite placeholders in the SQL string
    rewritten_sql = if occursin("?", stmt.sql)
        let counter = 0
            replace(stmt.sql, "?" => _ -> begin
                counter += 1
                "\$_" * string(counter)
            end)
        end
    else
        replace(stmt.sql, r"\$(?=\d)" => raw"$_")
    end
    
    query_res = query(stmt.conn.client, rewritten_sql, vars)
    return SurrealCursor(extract_results(query_res))
end

function DBInterface.execute(stmt::SurrealStatement, params::Union{Dict, NamedTuple})
    query_res = query(stmt.conn.client, stmt.sql, params)
    return SurrealCursor(extract_results(query_res))
end

function DBInterface.execute(stmt::SurrealStatement)
    query_res = query(stmt.conn.client, stmt.sql)
    return SurrealCursor(extract_results(query_res))
end

function DBInterface.execute(conn::SurrealConnection, sql::String, params...)
    stmt = DBInterface.prepare(conn, sql)
    if isempty(params)
        return DBInterface.execute(stmt)
    elseif length(params) == 1 && (params[1] isa Dict || params[1] isa NamedTuple || params[1] isa Vector)
        return DBInterface.execute(stmt, params[1])
    else
        return DBInterface.execute(stmt, collect(params))
    end
end

# Tables.jl Cursor & Row implementation
Tables.isrowtable(::Type{<:SurrealCursor}) = true
Base.length(cursor::SurrealCursor) = length(cursor.rows)
Base.eltype(::Type{SurrealCursor}) = SurrealRow

function Base.iterate(cursor::SurrealCursor, state=1)
    if state > length(cursor.rows)
        return nothing
    end
    row = SurrealRow(cursor.rows[state], cursor)
    return row, state + 1
end

Tables.columnnames(row::SurrealRow) = row.cursor.colnames

function Tables.getcolumn(row::SurrealRow, i::Int)
    colname = Tables.columnnames(row)[i]
    return get(row.data, string(colname), missing)
end

function Tables.getcolumn(row::SurrealRow, nm::Symbol)
    return get(row.data, string(nm), missing)
end

toDatabase(conn::SurrealConnection, table::String, df::DataFrame; batch_size::Int=100) = toDatabase(conn.client, table, df; batch_size=batch_size)
