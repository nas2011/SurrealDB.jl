using CBOR

"""
    serializeRequest(method::String, params::Vector) -> Vector{UInt8}

Serializes a SurrealDB RPC request into CBOR bytes. The request map contains 
the "method" and "params" keys.
"""
function serializeRequest(method::String, params::Vector)
    # Create the request payload structure
    payload = Dict{String, Any}(
        "method" => method,
        "params" => params
    )
    return CBOR.encode(payload)
end

# Provide a convenience method for empty params
serializeRequest(method::String) = serializeRequest(method, Any[])

"""
    deserializeResponse(bytes::Vector{UInt8}) -> Any

Deserializes a CBOR-encoded database response payload back into Julia values.
"""
function deserializeResponse(bytes::Vector{UInt8})
    return CBOR.decode(bytes)
end
