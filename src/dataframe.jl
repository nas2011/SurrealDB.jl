using DataFrames

"""
    toDataFrame(results::Vector) -> DataFrame

Converts a vector of database record dictionaries into a Julia `DataFrame`.
If the raw outer query result wrapper `[Dict("status" => "OK", "result" => [...])]` 
is passed, it automatically extracts the rows from the first successful statement.

Safely handles schemaless data by mapping missing fields to Julia's `missing` type.
"""
function toDataFrame(results::Vector)
    # Check if empty
    if isempty(results)
        return DataFrame()
    end
    
    # Automatically extract statement results if outer query envelope is passed
    rows = if length(results) == 1 && results[1] isa Dict && haskey(results[1], "status") && haskey(results[1], "result")
        stmt = results[1]
        if stmt["status"] != "OK"
            error("Query statement failed: $(stmt["result"])")
        end
        stmt["result"]
    else
        results
    end
    
    # If the query result itself is empty (e.g. no records found)
    if isempty(rows) || !(rows isa Vector)
        return DataFrame()
    end
    
    # Extract row dictionaries
    row_dicts = [row for row in rows if row isa Dict]
    if isempty(row_dicts)
        # If it's a vector of primitive values, wrap them in a single column DataFrame
        df = DataFrame()
        df[!, :value] = rows
        return df
    end
    
    # 1. Collect all unique keys present across all rows (columns)
    all_keys = Set{String}()
    for row in row_dicts
        for k in keys(row)
            push!(all_keys, String(k))
        end
    end
    sorted_keys = sort(collect(all_keys))
    
    # 2. Build the columns, replacing missing properties with `missing`
    df = DataFrame()
    for col_str in sorted_keys
        col_data = Any[get(row, col_str, missing) for row in row_dicts]
        df[!, Symbol(col_str)] = col_data
    end
    
    return df
end

"""
    toDatabase(client::Surreal, table::String, df::DataFrame; batch_size::Int=100)

Writes a Julia `DataFrame` into the specified database table.
The rows are converted to dictionaries (omitting `missing` values) and inserted 
in batches of `batch_size` using high-performance parameterized query bindings.
"""
function toDatabase(client::Surreal, table::String, df::DataFrame; batch_size::Int=100)
    # If DataFrame is empty, do nothing
    if isempty(df)
        return nothing
    end
    
    # Get column names as strings
    cols = [String(c) for c in names(df)]
    
    # Process rows in batches
    num_rows = nrow(df)
    for i in 1:batch_size:num_rows
        # Determine batch range
        last_idx = min(i + batch_size - 1, num_rows)
        batch_rows = view(df, i:last_idx, :)
        
        # Build vector of dicts for this batch
        batch_data = Vector{Dict{String, Any}}()
        for row in eachrow(batch_rows)
            d = Dict{String, Any}()
            for col in cols
                val = row[col]
                if !ismissing(val)
                    d[col] = val
                end
            end
            push!(batch_data, d)
        end
        
        # Execute parameterized insert
        query(client, "INSERT INTO $table \$data", Dict("data" => batch_data))
    end
    
    return nothing
end

