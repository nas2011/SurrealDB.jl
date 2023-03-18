
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

