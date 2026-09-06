import QtQuick
QtObject { property var command: []; property bool running: false; property bool stdinEnabled: false; property var stdout; property var stderr; signal exited(int code); function write(s) {} }
