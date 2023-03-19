mutable struct SurrealDBConnection
    url::String
    user::String
    password::String
    database::String
    namespace::String
    SurrealDBConnection(url,user,password) = new(url,user,password,"","")
    SurrealDBConnection(user,password) = new("http://localhost:8000",user,password,"","")
    SurrealDBConnection(user,password) = new("http://localhost:8000",user,password,"","")
    SurrealDBConnection(user,password;database="",namespace="") = new("http://localhost:8000",user,password,database,namespace)
end


struct SurrealNS
    ns::String
end

struct SurrealDB
    ns::SurrealNS
    name::String
end

mutable struct SurrealField
    name::String
    type::String
    assertion::String
    SurrealField(name::String,type::String,assertion::String) = new(name,type,assertion)
    SurrealField(name::String,type::String) = new(name,type,"")
end



mutable struct SurrealTable
    ns::SurrealNS
    db::SurrealDB
    name::String
    schema::String
    fields::Vector{SurrealField}

    SurrealTable(ns,db,name,schema) = 
    !in(lowercase(schema),["schemaful","schemaless"]) ? error("must be schemaful or schemaless") : new(ns,db,name,schema,[])
end



