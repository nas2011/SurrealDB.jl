using Libdl
using HTTP

# Options structure mapped to Rust Options in surrealdb.c
struct SurrealOptions
    strict::Bool
    queryTimeout::UInt8
    transactionTimeout::UInt8
end

# Default constructor
SurrealOptions() = SurrealOptions(false, 0, 0)

# Abstract type representing a transport layer
abstract type SurrealTransport end

# Embedded FFI Transport wrapping the opaque C SurrealRpc pointer
struct EmbeddedTransport <: SurrealTransport
    rpcPtr::Ptr{Cvoid}
end

# Remote WebSocket Transport wrapping the HTTP WebSocket connection
struct RemoteTransport <: SurrealTransport
    wsClient::HTTP.WebSockets.WebSocket
    lock::ReentrantLock
end

"""
    sendRequest(transport::EmbeddedTransport, cborRequest::Vector{UInt8}) -> Vector{UInt8}

Sends a CBOR request to the in-process SurrealDB engine via the FFI dynamic library.
"""
function sendRequest(transport::EmbeddedTransport, cborRequest::Vector{UInt8})
    # Load the library handle from the main module
    lib_handle = SurrealDB.LIB_HANDLE[]
    if lib_handle == C_NULL
        error("surrealdb_c shared library is not loaded.")
    end

    err_ptr = Ref{Ptr{Cchar}}(C_NULL)
    res_ptr = Ref{Ptr{UInt8}}(C_NULL)
    len = Cint(length(cborRequest))
    
    # Use cached function pointer
    func = SurrealDB.SR_SURREAL_RPC_EXECUTE[]
    res_len = ccall(func, Cint,
        (Ptr{Cvoid}, Ptr{Ptr{Cchar}}, Ptr{Ptr{UInt8}}, Ptr{UInt8}, Cint),
        transport.rpcPtr, err_ptr, res_ptr, cborRequest, len)
        
    if res_len < 0
        err_msg = "Error executing SurrealDB RPC request"
        if err_ptr[] != C_NULL
            err_msg = unsafe_string(err_ptr[])
            # Free error string using cached function pointer
            free_str = SurrealDB.SR_FREE_STRING[]
            ccall(free_str, Cvoid, (Ptr{Cchar},), err_ptr[])
        end
        error(err_msg)
    end
    
    # Wrap response pointer in a Julia Array and copy the bytes
    cbor_response = unsafe_wrap(Array, res_ptr[], res_len)
    copied_response = copy(cbor_response)
    
    # Free the Rust allocated byte array using cached function pointer
    free_bytes = SurrealDB.SR_FREE_BYTE_ARR[]
    ccall(free_bytes, Cvoid, (Ptr{UInt8}, Cint), res_ptr[], res_len)
    
    return copied_response
end

"""
    sendRequest(transport::RemoteTransport, cborRequest::Vector{UInt8}) -> Vector{UInt8}

Sends a CBOR request over WebSockets to a remote SurrealDB server.
"""
function sendRequest(transport::RemoteTransport, cborRequest::Vector{UInt8})
    # Use lock to prevent frame collision on concurrent queries
    lock(transport.lock) do
        # Send raw CBOR bytes as binary WebSocket frame
        HTTP.WebSockets.send(transport.wsClient, cborRequest)
        
        # Block and receive the response frame
        response = HTTP.WebSockets.receive(transport.wsClient)
        
        if response isa String
            return Vector{UInt8}(response)
        end
        return response
    end
end

"""
    closeTransport(transport::EmbeddedTransport)

Frees the in-process database RPC context. On Windows the OS file lock on the
RocksDB/SurrealKV LOCK file may not be released until some time after the ccall
returns, so we sleep briefly to allow kernel cleanup before returning.
"""
function closeTransport(transport::EmbeddedTransport)
    lib_handle = SurrealDB.LIB_HANDLE[]
    if lib_handle != C_NULL && transport.rpcPtr != C_NULL
        func = SurrealDB.SR_SURREAL_RPC_FREE[]
        ccall(func, Cvoid, (Ptr{Cvoid},), transport.rpcPtr)
        sleep(0.25)
    end
end

"""
    closeTransport(transport::RemoteTransport)

Closes the WebSocket connection.
"""
function closeTransport(transport::RemoteTransport)
    close(transport.wsClient)
end
