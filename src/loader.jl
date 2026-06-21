using Libdl

"""
    locate_library() -> String

Locates the compiled `surrealdb_c` shared library within the package directories, 
accounting for the operating system extension, and falls back to system paths.
"""
function locate_library()
    pkgdir = dirname(@__DIR__)
    
    # Determine the file extension based on the operating system
    ext = if Sys.iswindows()
        ".dll"
    elseif Sys.isapple()
        ".dylib"
    else
        ".so"
    end
    
    libname = "surrealdb_c"
    
    # 1. Check in the /src directory (production path)
    srcpath = joinpath(pkgdir, "src", libname * ext)
    if isfile(srcpath)
        return srcpath
    end
    
    # 2. Check in the Rust target release directory (local dev fallback)
    devpath = joinpath(pkgdir, "refs", "surrealdb.c", "target", "release", libname * ext)
    if isfile(devpath)
        return devpath
    end
    
    # 3. Fallback to system-wide search paths
    return libname
end
