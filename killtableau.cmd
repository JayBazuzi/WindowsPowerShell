@echo off
for %%i in (
    tableau.exe
    java.exe
    javaw.exe
    jruby.exe
    tabspawnde.exe
    tabspawn.exe
    unittest.exe
    tdeserver64.exe
    tabsvc.exe
    httpd.exe
    backgrounder.exe
    tabrepo.exe
    postgres.exe
    wgserver.exe
    vizqlserver.exe
    tabsystray.exe
    dataserver.exe
    tabsvcmonitor.exe
    lmgrd.exe
    tabsrvlic.exe
    ruby.exe
    tabadmin.exe
    hostedproxy.exe
    remoteagentserver.exe
    appzookeeper.exe
) do taskkill /f /im %%i
