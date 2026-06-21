# SurrealDB.jl

A high-performance, multi-backend SurrealDB client for Julia. `SurrealDB.jl` supports both **embedded in-process engines** (leveraging a compiled FFI Rust shared library with in-memory or RocksDB persistence) and **remote database sessions** (over WebSockets with binary CBOR serialization).

---

## Features

- **Multi-Backend support:**
  - `mem://` — In-process in-memory database.
  - `rocksdb://<path>` — In-process file-persistent RocksDB database.
  - `ws://` / `wss://` — Remote server over WebSocket.
- **Full CBOR-RPC Integration:** High-throughput binary serialization protocol negotiating the `cbor` subprotocol.
- **Natively Typed Roundtrips:** Native Julia types transparently serialize and deserialize to/from SurrealDB custom CBOR tags:
  - **Record IDs** (Tag 8) maps to standard Strings or the custom `RecordID` struct.
  - **Datetimes** (Tag 12) maps to Julia's `Dates.DateTime`.
  - **UUIDs** (Tag 37 / 9) maps to `UUIDs.UUID`.
- **DataFrames Integration:** Turn query result sets into Julia `DataFrame` tables with missing properties safely handled using Julia's `missing` type.
- **Asynchronous Execution:** FFI boundaries and WebSocket transmissions run inside `Threads.@spawn` tasks for responsive Julia thread pools.

---

## Installation

Activate your project environment and add the package:

```julia
using Pkg
Pkg.activate(".")
Pkg.add(url="https://github.com/nas2011/SurrealDB.jl.git")
```

*Note: Embedded mode requires the compiled FFI library (`surrealdb_c.dll` on Windows, `.so` on Linux, `.dylib` on macOS) to be located in the package's `/src` directory.*

---

## Quick Start Guide

### 1. In-Process Embedded Database (Memory / RocksDB)

Embedded mode runs the SurrealDB database engine in-process. 

```julia
using SurrealDB
using Dates
using UUIDs

# 1. Connect to an in-memory instance
db = connect("mem://")

# Or for persistent RocksDB storage:
# db = connect("rocksdb://path/to/my_database")

# 2. Select Namespace and Database
use(db, "production", "analytics")

# 3. Create a record
sensor_data = Dict(
    "name" => "Core Temperature",
    "value" => 98.6,
    "timestamp" => Dates.now(),
    "session" => UUIDs.uuid4()
)
create_res = create(db, "metric:sensor_1", sensor_data)

# 4. Select a record
select_res = select(db, "metric:sensor_1")
println("Temperature: ", select_res["value"])

# 5. Update a record (Replace)
update(db, "metric:sensor_1", Dict("name" => "Core Temp", "value" => 99.1))

# 6. Merge properties (Patch)
merge(db, "metric:sensor_1", Dict("status" => "warning"))

# 7. Query with bindings
query_res = query(db, "SELECT * FROM metric WHERE value > \$limit", Dict("limit" => 95.0))

# 8. Delete record
delete(db, "metric:sensor_1")

# 9. Close session
close(db)
```

---

### 2. Remote WebSocket Database

Remote mode communicates with a standalone SurrealDB server over a WebSocket.

```julia
using SurrealDB

# 1. Start a temporary background server using the serve! helper:
server = serve!("memory"; port=8000)

# Or serve a file-persistent RocksDB database:
# server = serve!("rocksdb:path/to/db"; port=8000)

# 2. Connect to remote SurrealDB instance
db = connect("ws://127.0.0.1:8000")

# 3. Authenticate
SurrealDB.execute(db, "signin", Any[Dict("user" => "root", "pass" => "root")])

# 4. Select Namespace and Database
use(db, "production", "analytics")

# 5. Perform CRUD/Query actions (API is identical to embedded mode)
create_res = create(db, "person:john", Dict("name" => "John Doe"))
println("Selected: ", select(db, "person:john"))

# 6. Close connection and stop the background server
close(db)
kill(server)
```

#### Configuring the Server using `config.toml`

The `serve!` function can dynamically load configurations from a `config.toml` file. This allows you to configure any command-line options accepted by the `surreal start` command (such as logs, timeouts, or capabilities):

```toml
# config.toml
[server]
bind = "127.0.0.1:8777"
user = "admin"
pass = "secret"
log = "warn"

[capabilities]
allow-all = true

[database]
query-timeout = "10s"
```

```julia
# Reads "config.toml" in the working directory by default:
server = serve!("memory")

# Or pass a custom configuration path:
# server = serve!("memory"; config_path="scratch/config.toml")
```

---

### 3. DataFrames Integration

You can easily convert query statement arrays directly into a Julia `DataFrame`.

```julia
using SurrealDB
using DataFrames

db = connect("mem://")
use(db, "test", "test")

# Create records with uneven schemas
create(db, "user:1", Dict("name" => "Alice", "role" => "Admin"))
create(db, "user:2", Dict("name" => "Bob", "age" => 30))

# Run query and format to DataFrame
res = query(db, "SELECT * FROM user")
df = toDataFrame(res)

# Missing columns/properties are safely mapped to `missing`
println(df)
# Row │ age      │ id      │ name   │ role
#     │ Any      │ String  │ String │ Any
# ────┼──────────┼─────────┼────────┼─────────
#   1 │ missing  │ user:1  │ Alice  │ Admin
#   2 │ 30       │ user:2  │ Bob    │ missing

# Write a DataFrame back to the database in batches (defaults to batch_size=100)
toDatabase(db, "user", df)

close(db)
```

---

### 4. DBInterface.jl & Tables.jl Integration

`SurrealDB.jl` implements the standard `DBInterface.jl` database API. This allows you to run queries using standard database lifecycle methods and materialize the cursor directly into tables like `DataFrames`.

```julia
using SurrealDB
using DBInterface
using DataFrames

# 1. Connect using DBInterface
conn = DBInterface.connect(SurrealConnection, "mem://")
use(conn.client, "production", "analytics")

# 2. Create some data
DBInterface.execute(conn,"DEFINE TABLE IF NOT EXISTS person")
DBInterface.execute(conn,
"""
create person:1 content {'name': 'Bob','age':45};
create person:2 content {'name': 'Alice','age': 42}
"""
)

# 3. Execute a query directly
cursor = DBInterface.execute(conn, "SELECT * FROM person")
df = DataFrame(cursor)

# 4. Use positional parameter binds (e.g. ?)
cursor_pos = DBInterface.execute(conn, "SELECT * FROM person WHERE age > ?", 30)
df_pos = DataFrame(cursor_pos)

# 5. Use prepared statements
stmt = DBInterface.prepare(conn, "SELECT * FROM person WHERE name = ?")
cursor_prep = DBInterface.execute(stmt, ["Alice"])
df_prep = DataFrame(cursor_prep)

# 6. Close connection
DBInterface.close!(conn)
```

---

### 5. Working with Complex Record IDs (`RecordID`)

SurrealDB supports complex record ID keys, such as arrays or object dictionaries. The package exports the `RecordID` struct to handle these keys natively.

```julia
using SurrealDB
using Dates

db = connect("mem://")
use(db, "test", "test")

# Define a RecordID with an array key: ["sensorName", timestamp]
timestamp = Dates.now()
sensor_id = RecordID("reading", Any["thermometer_01", timestamp])

# Create the record using the RecordID struct
create(db, sensor_id, Dict("value" => 22.4, "unit" => "Celsius"))

# Select the record using the RecordID struct
record = select(db, sensor_id)

println("Table: ", record["id"].table) # "reading"
println("Sensor: ", record["id"].id[1]) # "thermometer_01"
println("Time: ", record["id"].id[2])   # Dates.DateTime object

close(db)
```

---

## Thread Safety & Concurrency

- **Embedded FFI:** Thread-safe lock-free transport execution. Spawning tasks on multiple Julia threads (`Threads.@spawn`) will execute concurrent database transactions directly on the core Rust engine. In case of write conflicts on shared indices, implement appropriate retry/backoff logic.
- **Remote WebSocket:** Multi-thread safe. Spawns tasks asynchronously, utilizing a connection-level `ReentrantLock` under the hood to ensure binary frame serialization and avoid interleaved WebSocket frames.

---

## Throughput Performance Benchmark

Below is the throughput summary measured sequentially on a Windows client with 50,000 queries against both backends (using implicit batching of 100 for writes):

| Backend | Writes / sec | Reads / sec |
| :--- | :--- | :--- |
| **Embedded In-Memory (`mem://`)** | **~16,350 writes/s** | **~4,930 reads/s** |
| **Remote WebSocket (`ws://`)** | **~23,710 writes/s** | **~4,160 reads/s** |

### Batch Write Performance (`toDatabase` / Parameterized Batches)

For bulk writes, using the parameterized batching convenience function `toDatabase` yields a massive throughput increase on the `mem://` backend compared to the individual write baseline of **~2,680 writes/s** (without batching):

| Batch Size | writes / sec |
| :--- | :--- |
| **10 records** | ~630 writes/s |
| **100 records** | **~25,170 writes/s** (9.3x improvement) |
| **500 records** | **~19,380 writes/s** (7.2x improvement) |
| **1,000 records** | **~13,880 writes/s** (5.1x improvement) |
