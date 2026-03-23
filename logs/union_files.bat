@echo off
    setlocal enableextensions disabledelayedexpansion

    rem configure paths
    set "source=*.csv"
    set "target=newfile.csv"

    rem remove output file if needed
    if exist "%target%" del "%target%" >nul 2>nul

    rem search for header row
    set "headerRow="
    for %%f in ("%source%") do (
        <"%%~ff" ( for /l %%a in (1 1 10) do if not defined headerRow set /p "headerRow=" )
        if defined headerRow goto haveHeader
    )
:haveHeader
    if not defined headerRow (
        echo ERROR: impossible to get header row. 
        goto endProcess
    )

    rem output header to header file to use as filter.
    rem header is cut to avoid findstr limitations on search strings
    set "headerFile=%temp%\%~nx0_headerFile.tmp"
    setlocal enableextensions enabledelayedexpansion
    > "%headerFile%" echo(!headerRow:~0,125!
    endlocal


    rem search for input files with matching headers to join to final file
    for /f "tokens=*" %%f in ('findstr /m /b /l /g:"%headerFile%" "%source%"') do (
        if not exist "%target%" (

                rem first file is directly copied
                copy "%%~f" "%target%" /y > nul 2>nul

            ) else (

                rem next files are filtered to exclude the header row
                findstr /v /b /l /g:"%headerFile%" "%%~f" >> "%target%"
        )
        echo ... [%%~ff] joined to %target%
    )

    rem remove the temporary header file
    del "%headerFile%" >nul 2>nul

:endProcess
    endlocal