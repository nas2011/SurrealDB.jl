# SurrealDB

## A Basic Clien Library for Working With SurrealDB in Julia

This is a basic client library. It allows you to define a SurrealDB connection to a running
instance of SurrealDB and execute SurrealQL statements on that instance using the SurrealDB
REST API. This package also provides a convenience function `todf` to convert results of
executed queries to a `DataFrame` for further use.

I intend to build this out with more full fledged features over time.