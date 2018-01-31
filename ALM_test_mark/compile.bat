
@echo off

set fns=ALM_test_mark
set fn=%fns%

set tcln=tclkitsh-win32.upx
set tcln=tclkit-win32.upx
set tcln=tclkitsh-8.5.17-win32-ix86

set sdx=sdx-20110317.kit

DEL /f %fn%.kit
DEL /f %fn%.exe

RMDIR /s /q %fn%.vfs
COPY /y %tcln%.exe %tcln%_Copy.exe

echo %tcln%.exe %sdx% qwrap %fn%.tcl
%tcln%.exe %sdx% qwrap %fn%.tcl
echo %tcln%.exe %sdx% unwrap %fn%.kit
%tcln%.exe %sdx% unwrap %fn%.kit
IF NOT EXIST %fn%.vfs\lib\app-%fns% GOTO END

XCOPY lib %fn%.vfs\lib /i /y /s /c /f

%tcln%.exe %sdx% wrap %fns%.exe -runtime %tcln%_Copy.exe

DEL /f %tcln%_Copy.exe
RMDIR /s /q %fn%.vfs
DEL /f %fn%.kit
echo ....completed....

:END