#!/usr/bin/env bash
set -e
H="$(cd "$(dirname "$0")" && pwd)"; P="$(dirname "$H")"
rm -rf "$H/plug" && cp -r "$P" "$H/plug" && rm -rf "$H/plug/test" "$H/plug/.git"
sed -i 's/exclusionMode: ExclusionMode.Ignore/exclusionMode: 0/; /WlrLayershell\./d; /anchors { top: true; bottom: true; left: true; right: true }/d' "$H/plug/Service.qml"
mkdir -p "$H/home"
cd "$H" && QML2_IMPORT_PATH="$H" QML_IMPORT_PATH="$H" xvfb-run -a -s "-screen 0 1280x720x24" env QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 timeout 60 /usr/lib/qt6/bin/qmlscene run.qml 2>&1 | grep -iv "deprecated\|XDG_RUNTIME\|qt.rhi\|scenegraph"
