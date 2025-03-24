# struct SurrealDB
#     path::String
#     config::Dict
#     SurrealDB() = new("memory",config)
# end


function buildEnv(config::Dict)
    if Base.Sys.iswindows()
        cmdStr = ""
        for pair in config["env"]
            if pair[2] != "None"
                cmdStr = cmdStr * "\$env:$(pair[1])=$(pair[2]) "
            end
        end
        run(`powershell '$cmdStr'`)
    else
        println("only windows currently supported")
    end
end

function buildStartCmd(path::String,config::Dict)
    cmdStr = ""    
    for pair in config["start"]
        if pair[2] != false
            if pair[2] == true
                cmdStr = cmdStr * " --$(pair[1])"
            else
                cmdStr = cmdStr * " --$(pair[1]) $(pair[2])"
            end
        end
    end
    if path == "memory"
        pathVal = "memory"
    else
        pathVal = "$(config["storage"]["storage"])://$path"
    end
    cmd = `powershell "$surrealExeLoc start$(cmdStr) $pathVal"`
end

function surrealIsRunning()
    err = nothing
    try
        read(`powershell 'get-process surreal'`,String)
    catch err
    end
    if isnothing(err)
        return true
    else
        return false
    end
end


function runSurreal(cmd::Cmd)
    try
        Threads.@spawn redirect_stdio(stdout="./surreal/out.txt",stderr="./surreal/err.txt") do
            run(cmd)
            end
    catch e
        println("Error starting SurrealDB: $e")
    end
end

function startSurreal(path::String)
    print("Surreal Starting...")
    buildEnv(config)
    startCmd = buildStartCmd(path,config)
    @debug "\n$startCmd\n"
    runSurreal(startCmd)
    running = surrealIsRunning()
    while !running
        print(".")
        sleep(0.2)
        running = surrealIsRunning()
    end
    return "Surreal Started"
end

function closeSurreal()
    try
        read(`powershell 'get-process surreal | kill'`)
        println("Surreal Closed.")
    catch
        println("Surreal not running")
    end
end
