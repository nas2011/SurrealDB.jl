using Downloads
using REPL
using REPL.TerminalMenus

begin
    baseURL = "https://download.surrealdb.com"
    textBuf = IOBuffer()
    Downloads.download("https://version.surrealdb.com", textBuf)
    latest = take!(textBuf) |> String |> strip
    latestSemVer = replace(latest,r"[^0-9\.]" => "")
    surrealExe = joinpath(pwd(),"surreal","surreal.exe")
    downloadPath = baseURL * "/$latest/surreal-$latest.windows-amd64.exe"
end


function surrealExists()
    isfile(surrealExe)
end    

function installedVersion()
    try
        cmd = `powershell "$surrealExe --version"`
        verData = read(cmd,String)
        semVerRE = r"((0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?)"
        curInstalled = match(semVerRE,verData).captures[1]
    catch
        @warn "Could not find installed verison of SurrealDB. If you aren't on windows this function will not work."
        nothing
    end
end


function surrealIsLatest()
    installedVersion() == latestSemVer
end

function downloadLatest()
    try
        saveLoc = joinpath(pwd(),"surreal","surreal.exe")
        mkpath(dirname(saveLoc))
        Downloads.download(downloadPath,saveLoc)
    catch e
        "Something went wrong during download: $e"
    end
end

function updateSurreal()
    currentVersion = installedVersion()
    options = ["Update to the latest version: $latest", "Keep my version: v$currentVersion"]    
    menu = RadioMenu(options,pagesize=4)
    choice = TerminalMenus.request("Surreal v$currentVersion is currently installed but there is a newer version available: $latest. What would you like to do?:",menu)
    if choice == 1
        println("Downloading latest version...")
        downloadLatest()
    elseif choice == -1
        println("Selection canceled. Run `getSurreal() to run menu again.")
    else
        println("Keeping $currentVersion")
    end
end

function getSurreal()
    surrealAlreadyExists = surrealExists()
    latestIsInstalled = surrealIsLatest()
    if surrealAlreadyExists && latestIsInstalled
        println("You already have the latest version of SurrealDB!")
    elseif surrealAlreadyExists && !latestIsInstalled
        updateSurreal()
    else
        println("You don't have a version of SurrealDB installed. Fetching latest...")
        downloadLatest()
    end
end