module SurrealDB

using Libdl
using CBOR
using HTTP
using JSON3
using DataFrames
using UUIDs
using Dates
using TOML


# Initialize state variable for FFI library handle
const LIB_HANDLE = Ref{Ptr{Cvoid}}(C_NULL)

# Cache FFI function pointers to avoid dlsym lookup overhead on every request
const SR_SURREAL_RPC_NEW = Ref{Ptr{Cvoid}}(C_NULL)
const SR_SURREAL_RPC_EXECUTE = Ref{Ptr{Cvoid}}(C_NULL)
const SR_SURREAL_RPC_FREE = Ref{Ptr{Cvoid}}(C_NULL)
const SR_FREE_BYTE_ARR = Ref{Ptr{Cvoid}}(C_NULL)
const SR_FREE_STRING = Ref{Ptr{Cvoid}}(C_NULL)

# Include modules
include("loader.jl")
include("cbor.jl")
include("transport.jl")


# Exports
export Surreal, SurrealOptions, RecordID, SurrealConnection
export connect, close, use, query, create, select, update, merge, delete
export toDataFrame, toDatabase, serve!

"""
    struct RecordID

Represents a SurrealDB Record ID consisting of a table name and a unique identifier (which can be a string, number, array, or dictionary).
"""
struct RecordID
    table::String
    id::Any
end

"""
    mutable struct Surreal

Represents a connection to a SurrealDB database (either embedded in-process or remote).
"""
mutable struct Surreal
    url::String
    transport::SurrealTransport
    isConnected::Bool
end

function __init__()
    # Dynamically load the FFI shared library at package load time
    try
        libpath = locate_library()
        handle = Libdl.dlopen(libpath)
        LIB_HANDLE[] = handle
        
        SR_SURREAL_RPC_NEW[] = Libdl.dlsym(handle, :sr_surreal_rpc_new)
        SR_SURREAL_RPC_EXECUTE[] = Libdl.dlsym(handle, :sr_surreal_rpc_execute)
        SR_SURREAL_RPC_FREE[] = Libdl.dlsym(handle, :sr_surreal_rpc_free)
        SR_FREE_BYTE_ARR[] = Libdl.dlsym(handle, :sr_free_byte_arr)
        SR_FREE_STRING[] = Libdl.dlsym(handle, :sr_free_string)
    catch e
        @warn "SurrealDB: Failed to load dynamic library. Embedded mode will not be available. Error: $e"
    end
end

"""
    serve!(db_path::String; port::Union{Int, Nothing}=nothing, user::Union{String, Nothing}=nothing, pass::Union{String, Nothing}=nothing, bind::Union{String, Nothing}=nothing, config_path::String="config.toml") -> Base.Process

Starts a background SurrealDB server serving a database at `db_path`.
Returns the spawned `Base.Process` object. Call `kill(process)` to stop the server.

- If `db_path` is `"memory"` or `"mem"`, it runs an in-memory database.
- If it starts with `rocksdb:`, `surrealkv:`, or `file:`, it uses that engine scheme.
- Otherwise, it defaults to a `rocksdb:` file-based database engine at the specified path.

Options are loaded from `config_path` if it exists, with function arguments taking priority.
"""
function serve!(db_path::String;
                port::Union{Int, Nothing}=nothing,
                user::Union{String, Nothing}=nothing,
                pass::Union{String, Nothing}=nothing,
                bind::Union{String, Nothing}=nothing,
                config_path::String="config.toml",
                kwargs...)
    # Determine the endpoint
    endpoint = if db_path == "memory" || db_path == "mem"
        "memory"
    elseif startswith(db_path, "rocksdb:") || startswith(db_path, "surrealkv:") || startswith(db_path, "file:")
        db_path
    else
        "rocksdb:" * db_path
    end
    
    # Parse TOML config if it exists
    config = Dict{String, Any}()
    if isfile(config_path)
        try
            config = TOML.parsefile(config_path)
        catch e
            @warn "SurrealDB: Failed to parse TOML configuration file '$config_path': $e"
        end
    end

    # Extract standard fields from TOML (handling possible sections/nesting)
    flat_config = Dict{String, Any}()
    function flatten(d::Dict)
        for (k, v) in d
            if v isa Dict
                flatten(v)
            else
                flat_config[lowercase(string(k))] = v
            end
        end
    end
    flatten(config)

    # Convert kwargs to string keys and normalize names (underscores to dashes)
    user_options = Dict{String, Any}()
    for (k, v) in pairs(kwargs)
        key_str = replace(lowercase(string(k)), "_" => "-")
        user_options[key_str] = v
    end

    # Merge user_options into flat_config (user keyword arguments override TOML configuration values)
    for (k, v) in user_options
        flat_config[k] = v
    end

    # Extract user, pass, bind
    config_user = get(flat_config, "username", get(flat_config, "user", get(flat_config, "u", nothing)))
    config_pass = get(flat_config, "password", get(flat_config, "pass", get(flat_config, "p", nothing)))
    config_bind = get(flat_config, "bind", get(flat_config, "b", nothing))
    
    # Parse config bind to IP and port
    config_bind_ip = nothing
    config_port = nothing
    if config_bind !== nothing
        parts = split(string(config_bind), ':')
        if length(parts) == 2
            config_bind_ip = String(parts[1])
            config_port = tryparse(Int, parts[2])
        elseif length(parts) == 1
            config_bind_ip = String(parts[1])
        end
    end

    # Resolve final options
    final_user = something(user, config_user, "root")
    final_pass = something(pass, config_pass, "root")
    final_bind_ip = something(bind, config_bind_ip, "127.0.0.1")
    final_port = something(port, config_port, 8000)
    
    # Remove standard keys from flat_config to prevent duplication in custom options
    for k in ["username", "user", "u", "password", "pass", "p", "bind", "b", "path", "db-path", "db_path"]
        delete!(flat_config, k)
    end
    
    # Build custom arguments from the remaining TOML keys
    toml_args = String[]
    for (k, v) in flat_config
        # Normalize key names: convert underscores to dashes
        flag_name = replace(k, "_" => "-")
        flag = length(flag_name) == 1 ? "-$flag_name" : "--$flag_name"
        
        if v isa Bool
            if v
                push!(toml_args, flag)
            end
        elseif v isa Vector
            push!(toml_args, flag)
            for item in v
                push!(toml_args, string(item))
            end
        elseif v !== nothing
            push!(toml_args, flag)
            push!(toml_args, string(v))
        end
    end
    
    # Construct final command arguments
    bind_addr = "$final_bind_ip:$final_port"
    cmd_args = String[
        "start",
        "--user", string(final_user),
        "--pass", string(final_pass),
        "--bind", bind_addr
    ]
    append!(cmd_args, toml_args)
    push!(cmd_args, endpoint)
    
    cmd = Cmd(vcat("surreal", cmd_args))
    
    try
        process = run(cmd, wait=false)
        sleep(0.5)
        return process
    catch e
        error("Failed to start SurrealDB server. Make sure the 'surreal' CLI is installed and in your PATH. Error: $e")
    end
end


"""
    connect(url::String; options::SurrealOptions=SurrealOptions()) -> Surreal

Creates a connection to a SurrealDB database.
- If `url` starts with `mem://`, `file://`, or `surrealkv://`, it initializes an in-process embedded database.
- If `url` starts with `ws://` or `wss://`, it establishes a WebSocket connection to a remote server.
"""
function connect(url::String; options::SurrealOptions=SurrealOptions())
    if startswith(url, "mem://") || startswith(url, "file://") || startswith(url, "surrealkv://") || startswith(url, "rocksdb://")
        # Check if FFI library is loaded
        if LIB_HANDLE[] == C_NULL
            error("Cannot connect in embedded mode: surrealdb_c dynamic library failed to load.")
        end
        
        # Normalize in-memory endpoint to what SurrealDB expects
        endpoint = url == "mem://" ? "memory" : url
        
        # Use cached FFI function pointers to initialize the datastore, retrying on temporary OS lock delays
        new_func = SR_SURREAL_RPC_NEW[]
        free_str = SR_FREE_STRING[]
        
        status = -1
        surreal_ptr = Ref{Ptr{Cvoid}}(C_NULL)
        retries = 5
        
        while retries > 0
            err_ptr = Ref{Ptr{Cchar}}(C_NULL)
            surreal_ptr = Ref{Ptr{Cvoid}}(C_NULL)
            
            status = ccall(new_func, Cint,
                (Ptr{Ptr{Cchar}}, Ptr{Ptr{Cvoid}}, Ptr{Cchar}, SurrealOptions),
                err_ptr, surreal_ptr, endpoint, options)
                
            if status >= 0
                break
            end
            
            # Connection failed, check if it's a lock file/sharing violation/resource unavailable error
            err_msg = err_ptr[] != C_NULL ? unsafe_string(err_ptr[]) : "Failed to initialize embedded SurrealDB instance"
            
            # Free the Rust allocated string immediately
            if err_ptr[] != C_NULL
                ccall(free_str, Cvoid, (Ptr{Cchar},), err_ptr[])
            end
            
            if occursin("lock file", err_msg) || occursin("used by another process", err_msg) || occursin("Resource temporarily unavailable", err_msg) || occursin("lock", lowercase(err_msg))
                sleep(0.2)
                retries -= 1
                if retries == 0
                    error("Lock file timeout: " * err_msg)
                end
            else
                # It's a different fatal error, throw it immediately
                error(err_msg)
            end
        end
        
        transport = EmbeddedTransport(surreal_ptr[])
        client = Surreal(url, transport, true)
        
        # Register a finalizer to ensure database resources are closed on GC
        finalizer(client) do c
            close(c)
        end
        
        return client
        
    elseif startswith(url, "ws://") || startswith(url, "wss://")
        # Normalize WebSocket URL path (SurrealDB RPC expects `/rpc` path)
        ws_url = endswith(url, "/rpc") ? url : (endswith(url, "/") ? url * "rpc" : url * "/rpc")
        
        # Open persistent WebSocket connection negotiating CBOR subprotocol
        ws = HTTP.WebSockets.open(ws_url; subprotocols=["cbor"])
        transport = RemoteTransport(ws, ReentrantLock())
        return Surreal(url, transport, true)
    else
        error("Unsupported URL scheme: $url. Use 'mem://', 'file://', 'surrealkv://', 'rocksdb://', 'ws://', or 'wss://'")
    end
end

import Base: close

"""
    close(client::Surreal)

Closes the database client session, releasing FFI pointers or socket connections.
"""
function close(client::Surreal)
    if client.isConnected
        closeTransport(client.transport)
        client.isConnected = false
    end
    return nothing
end

"""
    is_record_id_string(s::String) -> Bool

Helper that checks if a string is a valid record ID format (e.g. "table_name:id_key").
"""
function is_record_id_string(s::String)
    parts = split(s, ':')
    if length(parts) != 2
        return false
    end
    tb, id = parts[1], parts[2]
    if isnothing(match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", tb))
        return false
    end
    if isnothing(match(r"^[a-zA-Z0-9_-]+$", id))
        return false
    end
    return true
end

"""
    uuid_to_bytes(u::UUIDs.UUID) -> Vector{UInt8}

Converts a Julia UUID to a 16-byte array.
"""
function uuid_to_bytes(u::UUIDs.UUID)
    v = u.value
    bytes = Vector{UInt8}(undef, 16)
    for i in 16:-1:1
        bytes[i] = UInt8(v & 0xff)
        v >>= 8
    end
    return bytes
end

"""
    bytes_to_uuid(bytes::Vector{UInt8}) -> UUIDs.UUID

Converts a 16-byte array to a Julia UUID.
"""
function bytes_to_uuid(bytes::Vector{UInt8})
    v = UInt128(0)
    for b in bytes
        v = (v << 8) | b
    end
    return UUIDs.UUID(v)
end

"""
    julia_to_cbor(val) -> Any

Recursively converts Julia types to custom CBOR Tags for database requests (e.g. Record ID strings to Tag 8, DateTime to Tag 12, UUID to Tag 37).
"""
function julia_to_cbor(r::RecordID)
    return CBOR.Tag(8, Any[r.table, julia_to_cbor(r.id)])
end

function julia_to_cbor(s::String)
    if is_record_id_string(s)
        parts = split(s, ':')
        return CBOR.Tag(8, String[String(parts[1]), String(parts[2])])
    end
    return s
end

function julia_to_cbor(dt::Dates.DateTime)
    # datetime2unix returns float seconds
    u_seconds = Dates.datetime2unix(dt)
    secs = floor(Int64, u_seconds)
    nsecs = round(Int64, (u_seconds - secs) * 1_000_000_000)
    return CBOR.Tag(12, Int64[secs, nsecs])
end

function julia_to_cbor(u::UUIDs.UUID)
    return CBOR.Tag(37, uuid_to_bytes(u))
end

function julia_to_cbor(val::Dict)
    d = Dict{String, Any}()
    for (k, v) in val
        d[string(k)] = julia_to_cbor(v)
    end
    return d
end

function julia_to_cbor(val::Vector)
    return Any[julia_to_cbor(v) for v in val]
end

julia_to_cbor(val) = val

"""
    cbor_to_julia(val) -> Any

Recursively converts custom CBOR Tags back to standard Julia types (e.g. Tag 8 Record IDs back to strings, Tag 12 back to DateTime, Tag 9/37 back to UUID).
"""
function cbor_to_julia(val::CBOR.Tag)
    if val.id == 8
        if val.data isa Vector || val.data isa Tuple
            tb = val.data[1]
            id_part = val.data[2]
            if id_part isa String || id_part isa Number
                return "$tb:$id_part"
            else
                return RecordID(string(tb), cbor_to_julia(id_part))
            end
        else
            return string(val.data)
        end
    elseif val.id == 6
        return nothing
    elseif val.id == 9
        return UUIDs.UUID(val.data)
    elseif val.id == 37
        return bytes_to_uuid(val.data)
    elseif val.id == 10
        return string(val.data)
    elseif val.id == 12
        if val.data isa Vector || val.data isa Tuple
            secs = val.data[1]
            nsecs = length(val.data) > 1 ? val.data[2] : 0
            u_seconds = secs + nsecs / 1_000_000_000
            return Dates.unix2datetime(u_seconds)
        else
            return Dates.unix2datetime(val.data)
        end
    else
        return cbor_to_julia(val.data)
    end
end

function cbor_to_julia(val::Dict)
    d = Dict{String, Any}()
    for (k, v) in val
        d[string(k)] = cbor_to_julia(v)
    end
    return d
end

function cbor_to_julia(val::Vector)
    return Any[cbor_to_julia(v) for v in val]
end

cbor_to_julia(val) = val

"""
    execute(client::Surreal, method::String, params::Vector) -> Any

Internal helper that executes an RPC call against the database.
If transport is RemoteTransport, uses CBOR-RPC over WebSockets.
If transport is EmbeddedTransport, uses CBOR-RPC over FFI.
Runs asynchronously under `Threads.@spawn` to keep the Julia thread pool responsive.
"""
function execute(client::Surreal, method::String, params::Vector)
    if !client.isConnected
        error("Database client is disconnected.")
    end
    
    if client.transport isa RemoteTransport
        # Convert parameters to CBOR-compliant tags (like Tag 8 for Record IDs)
        cbor_params = julia_to_cbor(params)
        
        # Create CBOR-RPC payload
        payload = Dict{String, Any}(
            "id" => string(UUIDs.uuid4()),
            "method" => method,
            "params" => cbor_params
        )
        cbor_req = CBOR.encode(payload)
        
        # Run the transport send/receive asynchronously on a Julia thread
        task = Threads.@spawn sendRequest(client.transport, cbor_req)
        cbor_res = fetch(task)
        
        # Decode CBOR response
        res = CBOR.decode(cbor_res)
        if haskey(res, "error") && res["error"] !== nothing
            err_msg = haskey(res["error"], "message") ? res["error"]["message"] : "Remote RPC error"
            error(err_msg)
        end
        return cbor_to_julia(res["result"])
    else
        # Convert parameters to CBOR-compliant tags
        embedded_params = julia_to_cbor(params)
        
        # CBOR-RPC payload for embedded/FFI transport
        cbor_req = serializeRequest(method, embedded_params)
        
        # Run the transport send/receive asynchronously on a Julia thread
        task = Threads.@spawn sendRequest(client.transport, cbor_req)
        cbor_res = fetch(task)
        
        # Deserialize response from CBOR and convert tags back to Julia types
        res = deserializeResponse(cbor_res)
        return cbor_to_julia(res)
    end
end

"""
    use(client::Surreal, namespace::String, database::String)

Configures the database namespace and database name for the current session.
"""
function use(client::Surreal, namespace::String, database::String)
    execute(client, "use", Any[namespace, database])
    return nothing
end

"""
    query(client::Surreal, sql::String, vars::Dict=Dict{String, Any}())

Executes a general SurrealQL statement. `vars` maps variables (e.g. `\$name`) to their values.
"""
function query(client::Surreal, sql::String, vars::Dict=Dict{String, Any}())
    clean_vars = Dict{String, Any}(String(k) => v for (k, v) in vars)
    execute(client, "query", Any[sql, clean_vars])
end

# Support passing NamedTuple for vars (e.g. query(db, sql, (name="John",)))
function query(client::Surreal, sql::String, vars::NamedTuple)
    clean_vars = Dict{String, Any}(String(k) => v for (k, v) in pairs(vars))
    query(client, sql, clean_vars)
end

"""
    create(client::Surreal, thing::Union{String, RecordID}, data::Dict=Dict{String, Any}())

Creates a record in the database. `thing` can be a table (e.g. `"person"`) or a record ID (e.g. `"person:john"` or `RecordID`).
"""
function create(client::Surreal, thing::Union{String, RecordID}, data::Dict=Dict{String, Any}())
    clean_data = Dict{String, Any}(String(k) => v for (k, v) in data)
    execute(client, "create", Any[thing, clean_data])
end

function create(client::Surreal, thing::Union{String, RecordID}, data::NamedTuple)
    clean_data = Dict{String, Any}(String(k) => v for (k, v) in pairs(data))
    create(client, thing, clean_data)
end

function create(client::Surreal, table::String, data::Vector{<:Dict})
    if isempty(data)
        return Any[]
    end
    # Convert Vector of Dict to Vector of Dict{String, Any}
    clean_data = [Dict{String, Any}(String(k) => v for (k, v) in d) for d in data]
    
    # Process in batches of 100
    batch_size = 100
    num_rows = length(clean_data)
    results = Any[]
    for i in 1:batch_size:num_rows
        last_idx = min(i + batch_size - 1, num_rows)
        batch_data = clean_data[i:last_idx]
        
        # Execute parameterized insert
        res = query(client, "INSERT INTO $table \$data", Dict("data" => batch_data))
        
        # Extract individual record results from the query response
        if res isa Vector && !isempty(res) && res[1]["status"] == "OK"
            append!(results, res[1]["result"])
        end
    end
    
    return results
end

function create(client::Surreal, table::String, data::Vector{<:NamedTuple})
    dict_data = [Dict{String, Any}(String(k) => v for (k, v) in pairs(nt)) for nt in data]
    create(client, table, dict_data)
end

"""
    select(client::Surreal, thing::Union{String, RecordID})

Selects records from the database. `thing` can be a table (e.g. `"person"`) or a record ID (e.g. `"person:john"` or `RecordID`).
"""
function select(client::Surreal, thing::Union{String, RecordID})
    execute(client, "select", Any[thing])
end

"""
    update(client::Surreal, thing::Union{String, RecordID}, data::Dict=Dict{String, Any}())

Replaces the data of the record(s) `thing` with `data`.
```
"""
function update(client::Surreal, thing::Union{String, RecordID}, data::Dict=Dict{String, Any}())
    clean_data = Dict{String, Any}(String(k) => v for (k, v) in data)
    execute(client, "update", Any[thing, clean_data])
end

function update(client::Surreal, thing::Union{String, RecordID}, data::NamedTuple)
    clean_data = Dict{String, Any}(String(k) => v for (k, v) in pairs(data))
    update(client, thing, clean_data)
end

"""
    merge(client::Surreal, thing::Union{String, RecordID}, data::Dict=Dict{String, Any}())

Merges the fields in `data` into the record(s) `thing`.
"""
function merge(client::Surreal, thing::Union{String, RecordID}, data::Dict=Dict{String, Any}())
    clean_data = Dict{String, Any}(String(k) => v for (k, v) in data)
    execute(client, "merge", Any[thing, clean_data])
end

function merge(client::Surreal, thing::Union{String, RecordID}, data::NamedTuple)
    clean_data = Dict{String, Any}(String(k) => v for (k, v) in pairs(data))
    merge(client, thing, clean_data)
end

"""
    delete(client::Surreal, thing::Union{String, RecordID})

Deletes the record(s) `thing`.
"""
function delete(client::Surreal, thing::Union{String, RecordID})
    execute(client, "delete", Any[thing])
end

include("dataframe.jl")
include("dbinterface.jl")

end # module
